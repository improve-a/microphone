"""Rolling UDP receiver for long physical microphone stability runs.

The receiver validates every datagram but keeps only short first/middle/last
windows, so an hour run does not create a multi-gigabyte capture.
"""

from __future__ import annotations

import argparse
from collections import deque
import json
from pathlib import Path
import socket
import struct
import sys
import time

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model.udp_protocol import ProtocolError, parse_packet, write_packet_file


def write_length_prefixed(path: Path, packets: list[bytes]) -> None:
    write_packet_file(path, packets)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=45123)
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--window-seconds", type=float, default=10.0)
    parser.add_argument("--expected-pcm-packets", type=int, default=0)
    args = parser.parse_args()
    if args.seconds <= 0 or args.window_seconds <= 0:
        parser.error("seconds and window-seconds must be positive")
    args.output.mkdir(parents=True, exist_ok=True)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
    sock.bind((args.bind, args.port))
    sock.settimeout(0.1)

    start = time.monotonic()
    deadline = start + args.seconds
    window = args.window_seconds
    captures: dict[str, list[bytes]] = {"first": [], "middle": [], "last": []}
    recent = deque(maxlen=2000)
    trailing = deque()
    traffic_start: float | None = None
    minute_rows: list[dict[str, object]] = []
    next_minute = 60.0
    minute_acc = np.zeros((8, 5), dtype=np.float64)
    # columns: count, sum, sumsq, abs_peak, clipped
    pcm_packets = heartbeats = malformed = crc_errors = 0
    non_protocol_datagrams = 0
    raw_datagrams = 0
    sequences: list[int] = []
    frames: set[int] = set()
    last_seq: int | None = None
    expected_seq: int | None = None
    missing = duplicates = late = 0
    bad_headers = bad_lengths = 0

    def reset_minute() -> None:
        nonlocal minute_acc
        minute_acc = np.zeros((8, 5), dtype=np.float64)

    def save_minute(elapsed: float) -> None:
        row: dict[str, object] = {"elapsed_seconds": elapsed,
                                   "pcm_packets": pcm_packets,
                                   "frames_observed": len(frames),
                                   "missing": missing, "duplicates": duplicates,
                                   "late_or_out_of_order": late,
                                   "malformed": malformed, "crc_errors": crc_errors}
        metrics = []
        for channel in range(8):
            count, total, sumsq, peak, clipped = minute_acc[channel]
            n = max(count, 1.0)
            mean = total / n
            rms = max(sumsq / n - mean * mean, 0.0) ** 0.5
            metrics.append({"channel": channel + 1, "samples": int(count),
                            "mean": mean, "rms": rms, "peak": peak,
                            "clipping_ratio": clipped / n})
        row["channels"] = metrics
        minute_rows.append(row)

    try:
        while time.monotonic() < deadline:
            try:
                data, _address = sock.recvfrom(4096)
            except socket.timeout:
                continue
            raw_datagrams += 1
            elapsed = time.monotonic() - start
            if traffic_start is None and data.startswith(b"MIC0"):
                traffic_start = elapsed
            traffic_elapsed = elapsed - traffic_start if traffic_start is not None else -1.0
            if 0.0 <= traffic_elapsed <= window:
                captures["first"].append(data)
            elif abs(traffic_elapsed - args.seconds / 2.0) <= window / 2.0:
                captures["middle"].append(data)
            if traffic_start is not None:
                trailing.append((elapsed, data))
                while trailing and elapsed - trailing[0][0] > window:
                    trailing.popleft()
            recent.append(data)

            if data.startswith(b"MIC_HEARTBEAT seq=") and data.endswith(b"\n"):
                heartbeats += 1
                continue
            if not data.startswith(b"MIC0"):
                # Raw-L2/ARP diagnostics are intentionally emitted before PCM
                # and are not members of the MIC0 protocol stream.
                non_protocol_datagrams += 1
                continue
            try:
                header, matrix = parse_packet(data)
            except ProtocolError as error:
                malformed += 1
                crc_errors += int("CRC" in str(error))
                continue
            pcm_packets += 1
            sequences.append(header.packet_sequence)
            frames.add(header.frame_index)
            if header.channel_count != 8 or header.samples_per_channel not in (38, 90):
                bad_headers += 1
            if header.samples_per_channel == 90 and header.sample_start != 0:
                bad_lengths += 1
            if header.samples_per_channel == 38 and header.sample_start != 90:
                bad_lengths += 1
            sequence = header.packet_sequence
            if expected_seq is None:
                expected_seq = sequence
            elif sequence == expected_seq:
                expected_seq += 1
            elif sequence > expected_seq:
                missing += sequence - expected_seq
                expected_seq = sequence + 1
            elif sequence == expected_seq - 1:
                duplicates += 1
            else:
                late += 1
            last_seq = sequence
            values = matrix.astype(np.float64, copy=False)
            minute_acc[:, 0] += values.shape[1]
            minute_acc[:, 1] += values.sum(axis=1)
            minute_acc[:, 2] += np.square(values).sum(axis=1)
            minute_acc[:, 3] = np.maximum(minute_acc[:, 3], np.max(np.abs(values), axis=1))
            minute_acc[:, 4] += np.count_nonzero((values <= -32768) | (values >= 32767), axis=1)
            if elapsed >= next_minute:
                save_minute(elapsed)
                reset_minute()
                next_minute += 60.0
    finally:
        elapsed_total = time.monotonic() - start
        if np.any(minute_acc[:, 0]):
            save_minute(elapsed_total)
        sock.close()

    for name, packets in captures.items():
        if name == "last":
            packets = [data for _timestamp, data in trailing]
        write_length_prefixed(args.output / f"{name}_packets.bin", packets)
        captures[name] = packets
    unique_sequences = set(sequences)
    span_missing = ((max(unique_sequences) - min(unique_sequences) + 1 - len(unique_sequences))
                    if unique_sequences else 0)
    # A packet can arrive late after a gap was observed.  Use the final
    # sequence span for loss accounting, while retaining the streaming
    # counters above for diagnostics.
    missing = max(0, int(span_missing))
    duplicates = max(0, len(sequences) - len(unique_sequences))
    stats = {
        "requested_seconds": args.seconds,
        "elapsed_seconds": elapsed_total,
        "bind": args.bind,
        "port": args.port,
        "datagrams": raw_datagrams,
        "heartbeats": heartbeats,
        "pcm_packets": pcm_packets,
        "frames_observed": len(frames),
        "first_sequence": sequences[0] if sequences else None,
        "last_sequence": last_seq,
        "sequence_gaps": missing,
        "duplicates": duplicates,
        "late_or_out_of_order": late,
        "malformed": malformed,
        "crc_errors": crc_errors,
        "non_protocol_datagrams": non_protocol_datagrams,
        "bad_headers": bad_headers,
        "bad_lengths": bad_lengths,
        "expected_pcm_packets": args.expected_pcm_packets or None,
        "expected_count_match": (not args.expected_pcm_packets or pcm_packets == args.expected_pcm_packets),
        "rolling_capture_packets": {name: len(packets) for name, packets in captures.items()},
        "minute_snapshots": minute_rows,
        "capture_files": {name: str(args.output / f"{name}_packets.bin") for name in captures},
    }
    stats["pass"] = bool(
        elapsed_total >= args.seconds * 0.98 and pcm_packets > 0 and
        malformed == 0 and crc_errors == 0 and missing == 0 and
        duplicates == 0 and late == 0 and bad_headers == 0 and bad_lengths == 0 and
        stats["expected_count_match"]
    )
    (args.output / "udp_soak_stats.json").write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(stats, indent=2))
    return 0 if stats["pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
