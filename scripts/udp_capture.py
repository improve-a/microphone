"""Capture the board's heartbeat and MIC0 UDP stream for bounded evidence."""

from __future__ import annotations

import argparse
import json
import re
import socket
import struct
import sys
import time
from pathlib import Path

import numpy as np

# Allow `python scripts/udp_capture.py` from the repository root.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model.udp_protocol import parse_packet, ProtocolError, write_packet_file


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=45123)
    parser.add_argument("--seconds", type=float, default=12.0)
    parser.add_argument("--output", type=Path, default=Path("evidence/physical/udp_capture"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    raw_path = args.output / "udp_raw_capture.bin"
    pcm_path = args.output / "mic_packets.bin"
    stats_path = args.output / "udp_stats.json"
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    # The board can legally emit back-to-back MTU datagrams; enlarge the
    # Windows receive queue so evidence reflects wire loss, not a tiny socket
    # buffer.
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
    sock.bind((args.bind, args.port))
    sock.settimeout(0.1)
    deadline = time.monotonic() + args.seconds
    raw: list[bytes] = []
    pcm: list[bytes] = []
    heartbeats: list[int] = []
    raw_udp = 0
    sequences: list[int] = []
    malformed = crc_errors = valid_samples = nonzero_samples = 0
    while time.monotonic() < deadline:
        try:
            data, _ = sock.recvfrom(4096)
        except socket.timeout:
            continue
        raw.append(data)
        match = re.fullmatch(rb"MIC_HEARTBEAT seq=(\d+)\n", data)
        if match:
            heartbeats.append(int(match.group(1)))
            continue
        if b"MIC_RAW_UDP_UNIQUE_20260903" in data:
            raw_udp += 1
            continue
        try:
            header, matrix = parse_packet(data)
        except ProtocolError as exc:
            malformed += 1
            crc_errors += int("CRC" in str(exc))
            continue
        pcm.append(data)
        sequences.append(header.packet_sequence)
        valid_samples += int(matrix.size)
        nonzero_samples += int(np.count_nonzero(matrix))
    sock.close()
    write_packet_file(pcm_path, pcm)
    with raw_path.open("wb") as handle:
        for data in raw:
            handle.write(struct.pack("<I", len(data)))
            handle.write(data)
    missing = 0
    duplicates = 0
    late = 0
    for previous, current in zip(sequences, sequences[1:]):
        if current > previous + 1:
            missing += current - previous - 1
        elif current == previous:
            duplicates += 1
        elif current < previous:
            late += 1
    stats = {
        "duration_seconds": args.seconds,
        "datagrams": len(raw),
        "heartbeats": len(heartbeats),
        "heartbeat_sequences": heartbeats,
        "pcm_packets": len(pcm),
        "raw_udp_diagnostic_packets": raw_udp,
        "expected_pcm_packets": 8192,
        "pcm_complete": len(pcm) == 8192 and malformed == 0 and missing == 0 and late == 0,
        "pcm_first_sequence": sequences[0] if sequences else None,
        "pcm_last_sequence": sequences[-1] if sequences else None,
        "sequence_gaps": missing,
        "duplicates": duplicates,
        "late_or_out_of_order": late,
        "malformed": malformed,
        "crc_errors": crc_errors,
        "valid_pcm_samples": valid_samples,
        "nonzero_pcm_samples": nonzero_samples,
        "raw_capture": str(raw_path),
        "pcm_capture": str(pcm_path),
    }
    stats_path.write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(stats, indent=2))
    return 0 if heartbeats and len(pcm) == 8192 and malformed == 0 and missing == 0 and late == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
