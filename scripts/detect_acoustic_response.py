"""Detect acoustic action in a MATLAB live_capture.mat file."""
from __future__ import annotations
import argparse, json
from pathlib import Path
import numpy as np
from scipy.io import loadmat
from scipy.signal import find_peaks

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mat", type=Path)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    data = loadmat(args.mat, squeeze_me=True, struct_as_record=False)
    if "pcm" not in data:
        raise RuntimeError("MAT file has no pcm variable")
    pcm = np.asarray(data["pcm"], dtype=np.float64)
    if pcm.ndim == 1: pcm = pcm.reshape(1, -1)
    fs = 48828.0
    channels, samples = pcm.shape
    centered = pcm - np.mean(pcm, axis=1, keepdims=True)
    window = 1024
    hop = 256
    starts = np.arange(0, max(0, samples-window+1), hop, dtype=int)
    short = np.vstack([np.sqrt(np.mean(centered[:, i:i+window]**2, axis=1)) for i in starts]) if len(starts) else np.zeros((0, channels))
    times = (starts + window/2) / fs
    edge = max(1, int(3*fs/hop))
    base_rows = np.r_[short[:edge], short[-edge:]] if len(short) else short
    baseline = np.median(base_rows, axis=0) if len(base_rows) else np.zeros(channels)
    aggregate = np.median(short / np.maximum(baseline, 1.0), axis=1) if len(short) else np.zeros(0)
    peaks, props = find_peaks(aggregate, height=1.5, prominence=0.25, distance=max(1, int(0.5*fs/hop))) if len(aggregate) else (np.array([], dtype=int), {})
    peak_times = times[peaks].tolist() if len(peaks) else []
    channel_peaks = []
    for c in range(channels):
        norm = short[:, c] / max(baseline[c], 1.0) if len(short) else np.zeros(0)
        cp, _ = find_peaks(norm, height=1.5, prominence=0.25, distance=max(1, int(0.5*fs/hop))) if len(norm) else (np.array([], dtype=int), {})
        channel_peaks.append({"channel": c+1, "peak_count": int(len(cp)), "peak_times_s": times[cp].tolist() if len(cp) else []})
    rms = np.sqrt(np.mean(centered**2, axis=1))
    peak = np.max(np.abs(centered), axis=1)
    metrics = [{"channel": c+1, "min": float(pcm[c].min()), "max": float(pcm[c].max()), "mean": float(pcm[c].mean()), "rms": float(rms[c]), "std": float(centered[c].std()), "peak_to_peak": float(pcm[c].max()-pcm[c].min()), "nonzero_ratio": float(np.count_nonzero(pcm[c])/max(1,samples)), "baseline_short_rms": float(baseline[c]), "peak_short_rms": float(short[:,c].max() if len(short) else 0), "peak_to_baseline": float((short[:,c].max()/max(baseline[c],1.0)) if len(short) else 0), "peak_db": float(20*np.log10(max(short[:,c].max(),1.0)/max(baseline[c],1.0)) if len(short) else 0)} for c in range(channels)]
    real_rms = float(np.median(rms[:min(7,channels)])) if channels else 0.0
    ch8_ratio = float(rms[7]/real_rms) if channels >= 8 and real_rms > 0 else None
    result = {"mat": str(args.mat), "channels": int(channels), "samples_per_channel": int(samples), "sample_rate_hz": fs, "duration_seconds": float(samples/fs), "baseline_rms": baseline.tolist(), "aggregate_peak_count": int(len(peaks)), "aggregate_peak_times_s": peak_times, "aggregate_peak_ratios": [float(aggregate[p]) for p in peaks], "channel_peaks": channel_peaks, "metrics": metrics, "ch8_to_real_rms_ratio": ch8_ratio, "clipping": [bool(np.any((pcm[c] <= -32768) | (pcm[c] >= 32767))) for c in range(channels)], "acoustic_pass": bool(len(peaks) >= 3 and all(x["peak_count"] >= 2 for x in channel_peaks[:min(7,channels)]))}
    (args.output/"acoustic_response.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2,1,figsize=(14,8),sharex=True)
    if len(short): axes[0].plot(times, short); axes[0].axhline(float(np.median(baseline)), color="k", linestyle="--"); axes[0].plot(times[peaks], np.median(short[peaks],axis=1), "rx", ms=10)
    axes[0].set_ylabel("short-time RMS"); axes[0].grid(True); axes[0].set_title("Acoustic response RMS envelope")
    axes[1].plot(np.arange(samples)/fs, centered.T, linewidth=.25); axes[1].set_xlabel("seconds"); axes[1].set_ylabel("centered PCM"); axes[1].grid(True)
    fig.tight_layout(); fig.savefig(args.output/"acoustic_response.png", dpi=150); plt.close(fig)
    print(json.dumps(result, indent=2))
    return 0 if result["acoustic_pass"] else 3
if __name__ == "__main__": raise SystemExit(main())

