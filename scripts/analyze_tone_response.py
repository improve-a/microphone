"""Analyze two controlled 1 kHz intervals in MATLAB live-capture evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np
from scipy.io import loadmat, savemat
from scipy.signal import welch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model.udp_protocol import ProtocolError, parse_packet


def db_ratio(numerator: float, denominator: float) -> float:
    floor = np.finfo(np.float64).tiny
    return float(20.0 * np.log10(max(numerator, floor) / max(denominator, floor)))


def contiguous_runs(mask: np.ndarray) -> list[tuple[int, int]]:
    padded = np.pad(mask.astype(np.int8), (1, 1))
    edges = np.diff(padded)
    return list(zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1) - 1))


def protocol_metrics(datagrams: np.ndarray) -> dict[str, int | bool | None]:
    seen: set[int] = set()
    duplicates = out_of_order = malformed = crc_errors = 0
    pcm_packets = heartbeats = raw_diagnostics = frame_layout_errors = 0
    max_seen: int | None = None
    for item in datagrams:
        data = bytes(np.asarray(item, dtype=np.uint8).ravel())
        if data.startswith(b"MIC_HEARTBEAT "):
            heartbeats += 1
            continue
        if b"MIC_RAW_UDP_UNIQUE_20260903" in data:
            raw_diagnostics += 1
            continue
        try:
            header, _ = parse_packet(data)
        except ProtocolError as error:
            malformed += 1
            if "CRC" in str(error):
                crc_errors += 1
            continue
        pcm_packets += 1
        sequence = int(header.packet_sequence)
        if sequence in seen:
            duplicates += 1
        else:
            if max_seen is not None and sequence < max_seen:
                out_of_order += 1
            seen.add(sequence)
            max_seen = sequence if max_seen is None else max(max_seen, sequence)
        expected_count = 90 if header.sample_start == 0 else 38
        expected_flags = 1 if header.sample_start == 0 else 2
        if (
            header.channel_count != 8
            or header.samples_per_channel != expected_count
            or header.flags != expected_flags
            or header.sample_start not in (0, 90)
        ):
            frame_layout_errors += 1
    missing = max(seen) - min(seen) + 1 - len(seen) if seen else 0
    return {
        "datagrams": int(np.size(datagrams)),
        "pcm_packets": pcm_packets,
        "heartbeats": heartbeats,
        "raw_diagnostics": raw_diagnostics,
        "first_sequence": min(seen) if seen else None,
        "last_sequence": max(seen) if seen else None,
        "missing": missing,
        "duplicates": duplicates,
        "out_of_order": out_of_order,
        "malformed": malformed,
        "crc_errors": crc_errors,
        "frame_layout_errors": frame_layout_errors,
        "pass": all(value == 0 for value in (
            missing, duplicates, out_of_order, malformed, crc_errors, frame_layout_errors
        )),
    }


def segment_channel_metrics(
    raw: np.ndarray, fs: float, quiet_rms: float, target_frequency: float
) -> dict[str, float | bool]:
    x = raw.astype(np.float64)
    dc = float(np.mean(x))
    centered = x - dc
    rms = float(np.sqrt(np.mean(centered * centered)))
    peak = float(np.max(np.abs(centered)))
    clip_ratio = float(np.mean((x <= -32768.0) | (x >= 32767.0)))
    nonzero_ratio = float(np.count_nonzero(raw) / raw.size)
    nperseg = min(raw.size, int(round(2.0 * fs)))
    frequency, psd = welch(
        centered, fs=fs, window="hann", nperseg=nperseg,
        noverlap=nperseg // 2, detrend="constant", scaling="spectrum",
    )
    search = (frequency >= target_frequency - 100.0) & (frequency <= target_frequency + 100.0)
    peak_index = np.flatnonzero(search)[int(np.argmax(psd[search]))]
    dominant_frequency = float(frequency[peak_index])
    dominant_rms = float(np.sqrt(psd[peak_index]))
    response_db = db_ratio(rms, quiet_rms)
    return {
        "dc": dc,
        "rms": rms,
        "peak": peak,
        "rail_clip_ratio": clip_ratio,
        "nonzero_ratio": nonzero_ratio,
        "dominant_frequency_hz": dominant_frequency,
        "dominant_rms": dominant_rms,
        "rms_vs_quiet_ratio": float(rms / max(quiet_rms, np.finfo(float).tiny)),
        "rms_vs_quiet_db": response_db,
        "frequency_pass": abs(dominant_frequency - target_frequency) <= 10.0,
        "rms_response_pass": response_db >= 6.0,
        "clip_pass": clip_ratio < 0.001,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mat", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frequency", type=float, default=1000.0)
    parser.add_argument("--sample-rate", type=float, default=48828.0)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    values = loadmat(args.mat, squeeze_me=True, struct_as_record=False)
    pcm = np.asarray(values["pcm"], dtype=np.int16)
    if pcm.ndim != 2:
        raise ValueError(f"expected a 2-D PCM matrix, got {pcm.shape}")
    if pcm.shape[0] > pcm.shape[1]:
        pcm = pcm.T
    if pcm.shape[0] != 8:
        raise ValueError(f"expected 8 channels, got {pcm.shape[0]}")

    fs = args.sample_rate
    frame_samples = int(round(fs))
    hop_samples = frame_samples // 2
    starts = np.arange(0, pcm.shape[1] - frame_samples + 1, hop_samples, dtype=int)
    times = (starts + frame_samples / 2.0) / fs
    window = np.hanning(frame_samples)[:, None]
    frequency = np.fft.rfftfreq(frame_samples, 1.0 / fs)
    tone_bin = int(np.argmin(np.abs(frequency - args.frequency)))
    local = (frequency >= args.frequency - 200.0) & (frequency <= args.frequency + 200.0)
    local[max(0, tone_bin - 2):tone_bin + 3] = False
    frame_rms = np.zeros((len(starts), 8), dtype=np.float64)
    tone_amplitude = np.zeros_like(frame_rms)
    tone_snr = np.zeros_like(frame_rms)
    for row, start in enumerate(starts):
        block = pcm[:, start:start + frame_samples].T.astype(np.float64)
        block -= np.mean(block, axis=0, keepdims=True)
        frame_rms[row] = np.sqrt(np.mean(block * block, axis=0))
        spectrum = np.abs(np.fft.rfft(block * window, axis=0)) * (2.0 / np.sum(window))
        tone_amplitude[row] = spectrum[tone_bin]
        noise = np.median(spectrum[local], axis=0)
        tone_snr[row] = 20.0 * np.log10(np.maximum(spectrum[tone_bin], 1e-12) / np.maximum(noise, 1e-12))

    # Preserve the established 10 dB detector and require agreement from five
    # of the seven populated channels before declaring a frame active.
    active = np.count_nonzero(tone_snr[:, :7] >= 10.0, axis=1) >= 5
    candidates = []
    for first, last in contiguous_runs(active):
        duration = (last - first) * hop_samples / fs + frame_samples / fs
        if duration >= 2.0:
            candidates.append((first, last, duration, float(np.median(tone_snr[first:last + 1, :7]))))
    selected = sorted(sorted(candidates, key=lambda item: (item[2], item[3]), reverse=True)[:2])
    if len(selected) != 2:
        raise ValueError(f"expected two controlled-tone intervals, detected {len(selected)}")

    quiet_rms = np.median(frame_rms[~active], axis=0)
    segment_results = []
    for index, (first, last, detected_duration, aggregate_snr) in enumerate(selected):
        # Remove the one-second detector's boundary overlap and retain the tone plateau.
        first_sample = starts[first] + frame_samples
        last_sample = starts[last]
        if last_sample <= first_sample:
            first_sample = starts[first]
            last_sample = starts[last] + frame_samples
        channels = [
            segment_channel_metrics(pcm[channel, first_sample:last_sample], fs, quiet_rms[channel], args.frequency)
            for channel in range(8)
        ]
        segment_results.append({
            "name": "left" if index == 0 else "right",
            "detected_start_seconds": float(starts[first] / fs),
            "detected_end_seconds": float((starts[last] + frame_samples) / fs),
            "detected_duration_seconds": float(detected_duration),
            "analysis_start_seconds": float(first_sample / fs),
            "analysis_end_seconds": float(last_sample / fs),
            "analysis_duration_seconds": float((last_sample - first_sample) / fs),
            "aggregate_tone_snr_db": aggregate_snr,
            "channels": channels,
        })

    comparisons = []
    for channel in range(8):
        left = segment_results[0]["channels"][channel]
        right = segment_results[1]["channels"][channel]
        comparisons.append({
            "channel": channel + 1,
            "left_rms": left["rms"],
            "right_rms": right["rms"],
            "right_vs_left_db": db_ratio(right["rms"], left["rms"]),
            "left_dominant_rms": left["dominant_rms"],
            "right_dominant_rms": right["dominant_rms"],
            "right_vs_left_tone_db": db_ratio(right["dominant_rms"], left["dominant_rms"]),
        })

    real_channels = [segment["channels"][channel] for segment in segment_results for channel in range(7)]
    unused_channels = [segment["channels"][7] for segment in segment_results]
    weakest_real_tone = min(item["dominant_rms"] for item in real_channels)
    ch8_pass = all(
        item["dominant_rms"] <= max(0.5, weakest_real_tone * 0.01)
        and item["nonzero_ratio"] < 0.001
        for item in unused_channels
    )
    frequency_pass = all(item["frequency_pass"] for item in real_channels)
    rms_response_pass = all(item["rms_response_pass"] for item in real_channels)
    clipping_pass = all(item["clip_pass"] for item in real_channels)
    protocol = protocol_metrics(np.atleast_1d(values["datagrams"]))
    overall_pass = frequency_pass and rms_response_pass and ch8_pass and clipping_pass and bool(protocol["pass"])

    result = {
        "mat": str(args.mat),
        "channels": 8,
        "samples_per_channel": int(pcm.shape[1]),
        "sample_rate_hz": fs,
        "duration_seconds": float(pcm.shape[1] / fs),
        "target_frequency_hz": args.frequency,
        "detector_threshold_db": 10.0,
        "quiet_rms": [float(value) for value in quiet_rms],
        "detected_intervals": segment_results,
        "left_right_comparison": comparisons,
        "protocol": protocol,
        "criteria": {
            "two_intervals_detected": True,
            "real_channels_frequency_pass": frequency_pass,
            "real_channels_rms_response_pass": rms_response_pass,
            "ch8_unused_pass": ch8_pass,
            "real_channels_clipping_pass": clipping_pass,
            "protocol_pass": bool(protocol["pass"]),
        },
        "controlled_tone_pass": overall_pass,
    }
    (args.output / "tone_response.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    (args.output / "udp_stats.json").write_text(json.dumps(protocol, indent=2) + "\n", encoding="utf-8")
    excerpt_start = max(0, starts[selected[0][0]] - int(round(5.0 * fs)))
    excerpt_end = min(pcm.shape[1], starts[selected[1][1]] + frame_samples + int(round(5.0 * fs)))
    savemat(
        args.output / "controlled_tone_excerpt.mat",
        {
            "pcm": pcm[:, excerpt_start:excerpt_end],
            "sample_rate_hz": fs,
            "source_start_sample": excerpt_start,
            "source_end_sample": excerpt_end,
            "source_mat": str(args.mat),
        },
        do_compression=True,
    )

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 1, figsize=(14, 9), sharex=True)
    for channel in range(8):
        label = f"CH{channel + 1}" if channel < 7 else "CH8 UNUSED"
        axes[0].plot(times, tone_amplitude[:, channel], linewidth=0.9, label=label)
        axes[1].plot(times, tone_snr[:, channel], linewidth=0.9, label=label)
    for first, last, _, _ in selected:
        for axis in axes:
            axis.axvspan(starts[first] / fs, (starts[last] + frame_samples) / fs, alpha=0.12, color="green")
    axes[0].set_ylabel("1 kHz amplitude (PCM peak)")
    axes[1].axhline(10.0, color="black", linestyle="--", linewidth=0.8)
    axes[1].set_ylabel("1 kHz / local noise (dB)")
    axes[1].set_xlabel("Capture time (s)")
    for axis in axes:
        axis.grid(True)
    axes[0].legend(ncol=4)
    fig.suptitle("Controlled 1 kHz left/right response")
    fig.tight_layout()
    fig.savefig(args.output / "tone_response.png", dpi=150)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(14, 6))
    x = np.arange(1, 9)
    width = 0.36
    ax.bar(x - width / 2, [item["left_rms"] for item in comparisons], width, label="left")
    ax.bar(x + width / 2, [item["right_rms"] for item in comparisons], width, label="right")
    ax.set_xticks(x, [f"CH{i}" for i in x])
    ax.set_ylabel("Centered RMS")
    ax.set_title("Left/right controlled-tone RMS")
    ax.grid(True, axis="y")
    ax.legend()
    fig.tight_layout()
    fig.savefig(args.output / "left_right_rms.png", dpi=150)
    plt.close(fig)

    fig, axes = plt.subplots(2, 1, figsize=(14, 9), sharex=True)
    for segment, axis in zip(segment_results, axes):
        first_sample = int(round(segment["analysis_start_seconds"] * fs))
        last_sample = int(round(segment["analysis_end_seconds"] * fs))
        for channel in range(8):
            x_channel = pcm[channel, first_sample:last_sample].astype(np.float64)
            nperseg = min(x_channel.size, int(round(2.0 * fs)))
            spec_frequency, psd = welch(
                x_channel - np.mean(x_channel), fs=fs, window="hann",
                nperseg=nperseg, noverlap=nperseg // 2,
                detrend="constant", scaling="spectrum",
            )
            band = (spec_frequency >= 100.0) & (spec_frequency <= 5000.0)
            label = f"CH{channel + 1}" if channel < 7 else "CH8 UNUSED"
            axis.semilogy(spec_frequency[band], np.sqrt(psd[band]), linewidth=0.8, label=label)
        axis.axvline(args.frequency, color="black", linestyle="--", linewidth=0.8)
        axis.set_ylabel("RMS amplitude")
        axis.set_title(f"{segment['name']} interval")
        axis.grid(True, which="both")
    axes[0].legend(ncol=4)
    axes[1].set_xlabel("Frequency (Hz)")
    fig.suptitle("Controlled-tone spectra")
    fig.tight_layout()
    fig.savefig(args.output / "tone_spectrum.png", dpi=150)
    plt.close(fig)

    markers = args.output / "physical_pass_markers.txt"
    if overall_pass:
        markers.write_text(
            "MIC_ACOUSTIC_1KHZ_PHYSICAL_PASS\n"
            "MIC_ACOUSTIC_RESPONSE_PHYSICAL_PASS\n"
            "MIC_MATLAB_LIVE_PHYSICAL_PASS\n",
            encoding="ascii",
        )
    elif markers.exists():
        markers.unlink()
    print(json.dumps(result, indent=2))
    return 0 if overall_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
