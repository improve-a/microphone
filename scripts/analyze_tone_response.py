"""Measure a controlled sinusoidal response in MATLAB live-capture evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat
from scipy.signal import welch


def db_ratio(numerator: float, denominator: float) -> float:
    floor = np.finfo(np.float64).tiny
    return float(20.0 * np.log10(max(numerator, floor) / max(denominator, floor)))


def longest_run(mask: np.ndarray) -> int:
    best = current = 0
    for value in mask:
        current = current + 1 if value else 0
        best = max(best, current)
    return best


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mat", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frequency", type=float, default=1000.0)
    parser.add_argument("--sample-rate", type=float, default=48828.0)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    values = loadmat(args.mat, squeeze_me=True, struct_as_record=False)
    pcm = np.asarray(values["pcm"], dtype=np.float64)
    if pcm.ndim != 2:
        raise ValueError(f"expected a 2-D PCM matrix, got {pcm.shape}")
    if pcm.shape[0] > pcm.shape[1]:
        pcm = pcm.T

    fs = args.sample_rate
    frame_samples = int(round(fs))
    hop_samples = frame_samples // 2
    window = np.hanning(frame_samples)
    frequency_bins = np.fft.rfftfreq(frame_samples, 1.0 / fs)
    tone_bin = int(np.argmin(np.abs(frequency_bins - args.frequency)))
    local = (frequency_bins >= args.frequency - 200.0) & (frequency_bins <= args.frequency + 200.0)
    local[max(0, tone_bin - 2):tone_bin + 3] = False
    starts = np.arange(0, pcm.shape[1] - frame_samples + 1, hop_samples, dtype=int)
    times = (starts + frame_samples / 2.0) / fs

    metrics = []
    tone_amplitudes = np.zeros((len(starts), pcm.shape[0]), dtype=np.float64)
    tone_snrs = np.zeros_like(tone_amplitudes)
    spectra = []
    spectrum_frequency = None
    for channel in range(pcm.shape[0]):
        x = pcm[channel]
        centered = x - np.mean(x)
        spectrum_frequency, psd = welch(
            centered, fs=fs, window="hann", nperseg=frame_samples,
            noverlap=hop_samples, detrend="constant", scaling="spectrum",
        )
        spectra.append(psd)
        search = (spectrum_frequency >= 100.0) & (spectrum_frequency <= 5000.0)
        peak_index = np.flatnonzero(search)[int(np.argmax(psd[search]))]
        tone_index = int(np.argmin(np.abs(spectrum_frequency - args.frequency)))
        noise = (spectrum_frequency >= args.frequency - 200.0) & (
            spectrum_frequency <= args.frequency + 200.0
        )
        noise[max(0, tone_index - 2):tone_index + 3] = False
        tone_rms = float(np.sqrt(psd[tone_index]))
        local_noise_rms = float(np.sqrt(np.median(psd[noise])))

        for row, start in enumerate(starts):
            block = x[start:start + frame_samples]
            block = (block - np.mean(block)) * window
            fft = np.abs(np.fft.rfft(block)) * (2.0 / np.sum(window))
            tone_amplitudes[row, channel] = fft[tone_bin]
            tone_snrs[row, channel] = db_ratio(fft[tone_bin], float(np.median(fft[local])))

        active = tone_snrs[:, channel] >= 10.0
        metrics.append({
            "channel": channel + 1,
            "rms": float(np.sqrt(np.mean(centered * centered))),
            "rail_clip_ratio": float(np.mean((x <= -32768.0) | (x >= 32767.0))),
            "absolute_ge_32760_ratio": float(np.mean(np.abs(x) >= 32760.0)),
            "dominant_frequency_hz_100_to_5000": float(spectrum_frequency[peak_index]),
            "dominant_rms": float(np.sqrt(psd[peak_index])),
            "tone_frequency_bin_hz": float(spectrum_frequency[tone_index]),
            "tone_rms": tone_rms,
            "tone_to_local_noise_db": db_ratio(tone_rms, local_noise_rms),
            "tone_frame_snr_db_median": float(np.median(tone_snrs[:, channel])),
            "tone_frame_snr_db_max": float(np.max(tone_snrs[:, channel])),
            "tone_active_frame_ratio": float(np.mean(active)),
            "tone_longest_active_seconds": float(longest_run(active) * hop_samples / fs),
        })

    real = metrics[:min(7, len(metrics))]
    responsive = [m for m in real if m["tone_active_frame_ratio"] >= 0.50]
    result = {
        "mat": str(args.mat),
        "channels": int(pcm.shape[0]),
        "samples_per_channel": int(pcm.shape[1]),
        "sample_rate_hz": fs,
        "duration_seconds": float(pcm.shape[1] / fs),
        "target_frequency_hz": args.frequency,
        "analysis_frame_seconds": float(frame_samples / fs),
        "analysis_hop_seconds": float(hop_samples / fs),
        "responsive_real_channels": len(responsive),
        "controlled_tone_pass": len(responsive) >= 5,
        "metrics": metrics,
    }
    json_path = args.output / "tone_response.json"
    json_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 1, figsize=(14, 9), sharex=True)
    for channel in range(pcm.shape[0]):
        label = f"CH{channel + 1}" if channel < 7 else "CH8 UNUSED"
        axes[0].plot(times, tone_amplitudes[:, channel], linewidth=0.9, label=label)
        axes[1].plot(times, tone_snrs[:, channel], linewidth=0.9, label=label)
    axes[0].set_ylabel("1 kHz amplitude (PCM peak)")
    axes[0].grid(True)
    axes[1].axhline(10.0, color="black", linestyle="--", linewidth=0.8)
    axes[1].set_ylabel("1 kHz / local noise (dB)")
    axes[1].set_xlabel("Capture time (s)")
    axes[1].grid(True)
    axes[0].legend(ncol=4)
    fig.suptitle("Controlled 1 kHz response over time")
    fig.tight_layout()
    fig.savefig(args.output / "tone_response.png", dpi=150)
    plt.close(fig)

    spectra_array = np.asarray(spectra)
    fig, ax = plt.subplots(figsize=(14, 6))
    band = (spectrum_frequency >= 100.0) & (spectrum_frequency <= 5000.0)
    for channel in range(pcm.shape[0]):
        label = f"CH{channel + 1}" if channel < 7 else "CH8 UNUSED"
        ax.semilogy(spectrum_frequency[band], np.sqrt(spectra_array[channel, band]), label=label)
    ax.axvline(args.frequency, color="black", linestyle="--", linewidth=0.8)
    ax.set_xlabel("Frequency (Hz)")
    ax.set_ylabel("RMS amplitude")
    ax.grid(True, which="both")
    ax.legend(ncol=4)
    ax.set_title("Controlled-tone spectrum")
    fig.tight_layout()
    fig.savefig(args.output / "tone_spectrum.png", dpi=150)
    plt.close(fig)

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
