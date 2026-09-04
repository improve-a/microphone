"""Compare candidate I2S 24-bit to PCM16 shifts using a live MAT capture.

The previous firmware exported slot[31:16]. With the observed I2S one-bit
delay, slot[30:16] is available in that capture; the missing low bit is
irrelevant for comparing the requested coarse shifts.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat
from scipy.signal import welch


def saturate(values: np.ndarray) -> np.ndarray:
    return np.clip(values, -32768, 32767).astype(np.int16)


def stats(values: np.ndarray, fs: float, target_hz: float) -> dict:
    centered = values.astype(np.float64) - float(np.mean(values))
    nperseg = min(int(round(fs)), values.size)
    freq, psd = welch(centered, fs=fs, nperseg=nperseg, noverlap=nperseg // 2,
                      scaling="spectrum")
    band = (freq >= target_hz - 15) & (freq <= target_hz + 15)
    tone_rms = float(np.sqrt(np.max(psd[band]))) if np.any(band) else 0.0
    local = (freq >= target_hz - 200) & (freq <= target_hz + 200)
    local[band] = False
    noise_rms = float(np.sqrt(np.median(psd[local]))) if np.any(local) else 0.0
    return {
        "min": int(values.min()),
        "max": int(values.max()),
        "mean": float(values.mean()),
        "rms": float(np.sqrt(np.mean(centered * centered))),
        "peak": float(np.max(np.abs(centered))),
        "clip_ratio": float(np.mean((values <= -32768) | (values >= 32767))),
        "nonzero_ratio": float(np.mean(values != 0)),
        "tone_rms": tone_rms,
        "tone_to_local_noise_db": float(20 * np.log10(max(tone_rms, 1e-12) /
                                            max(noise_rms, 1e-12))),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mat", type=Path)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--sample-rate", type=float, default=48828.0)
    ap.add_argument("--tone-hz", type=float, default=1000.0)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    raw_pcm = np.asarray(loadmat(args.mat, squeeze_me=True, struct_as_record=False)["pcm"],
                         dtype=np.int16)
    if raw_pcm.ndim != 2:
        raise ValueError(f"expected 2-D pcm, got {raw_pcm.shape}")
    if raw_pcm.shape[0] > raw_pcm.shape[1]:
        raw_pcm = raw_pcm.T

    # The old value was slot[31:16]. Removing the stale slot[31] and shifting
    # left reconstructs slot[30:15], i.e. a signed 24-bit sample >> 8.
    corrected_raw24 = (((raw_pcm.view(np.uint16).astype(np.int32) & 0x7fff) << 9)
                       .astype(np.int32))
    corrected_raw24[corrected_raw24 & (1 << 23) != 0] -= 1 << 24
    fs = args.sample_rate
    frame = int(round(fs))
    starts = np.arange(0, raw_pcm.shape[1] - frame + 1, frame // 2)
    times = (starts + frame / 2) / fs
    shifted_by_amount = {
        shift: saturate(corrected_raw24 >> shift) for shift in (0, 2, 4, 6, 8)
    }

    # Detect tone-on windows from the correctly aligned >>8 candidate. Using
    # the largest log-energy gap handles the deliberately intermittent test
    # playback without assuming fixed wall-clock start/stop times.
    reference_windows = []
    for channel in range(min(7, raw_pcm.shape[0])):
        x = shifted_by_amount[8][channel]
        reference_windows.append([stats(x[s:s + frame], fs, args.tone_hz) for s in starts])
    aggregate_tone = np.median(
        [[row["tone_rms"] for row in channel] for channel in reference_windows], axis=0)
    log_energy = np.log10(np.maximum(aggregate_tone, 1e-12))
    sorted_energy = np.sort(log_energy)
    gaps = np.diff(sorted_energy)
    split = int(np.argmax(gaps))
    threshold = float(10 ** ((sorted_energy[split] + sorted_energy[split + 1]) / 2))
    tone_mask = aggregate_tone >= threshold
    if not np.any(tone_mask) or np.all(tone_mask):
        raise RuntimeError("could not separate quiet and tone windows")

    shifts = {}
    for shift in (0, 2, 4, 6, 8):
        shifted = shifted_by_amount[shift]
        channel_rows = []
        for channel in range(shifted.shape[0]):
            x = shifted[channel]
            windows = [stats(x[s:s + frame], fs, args.tone_hz) for s in starts]
            quiet = [window for window, active in zip(windows, tone_mask) if not active]
            tone = [window for window, active in zip(windows, tone_mask) if active]
            channel_rows.append({
                "channel": channel + 1,
                "quiet": {k: float(np.median([w[k] for w in quiet]))
                          for k in ("rms", "peak", "clip_ratio", "tone_rms")},
                "tone": {k: float(np.median([w[k] for w in tone]))
                         for k in ("rms", "peak", "clip_ratio", "tone_rms")},
                "full_capture": stats(x, fs, args.tone_hz),
            })
        shifts[str(shift)] = {"channels": channel_rows}

    result = {
        "mat": str(args.mat),
        "sample_rate_hz": fs,
        "duration_seconds": float(raw_pcm.shape[1] / fs),
        "assumption": "old slot[31:16], corrected I2S valid bits slot[30:7]",
        "candidate_right_shifts": [0, 2, 4, 6, 8],
        "segmentation": {
            "window_seconds": float(frame / fs),
            "hop_seconds": float((frame // 2) / fs),
            "tone_threshold_rms": threshold,
            "quiet_window_count": int(np.sum(~tone_mask)),
            "tone_window_count": int(np.sum(tone_mask)),
            "windows": [
                {"time_seconds": float(time), "aggregate_tone_rms": float(level),
                 "tone": bool(active)}
                for time, level, active in zip(times, aggregate_tone, tone_mask)
            ],
        },
        "shifts": shifts,
    }
    (args.output / "i2s_scaling_comparison.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(14, 6))
    for shift in (0, 2, 4, 6, 8):
        values = [shifts[str(shift)]["channels"][c]["full_capture"]["rms"]
                  for c in range(min(7, raw_pcm.shape[0]))]
        ax.plot(range(1, len(values) + 1), values, marker="o", label=f">>{shift}")
    ax.set_xlabel("Real microphone channel")
    ax.set_ylabel("Full-capture RMS (PCM16)")
    ax.set_title("I2S scaling candidates after one-bit-delay correction")
    ax.grid(True)
    ax.legend()
    fig.tight_layout()
    fig.savefig(args.output / "i2s_scaling_comparison.png", dpi=150)
    plt.close(fig)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
