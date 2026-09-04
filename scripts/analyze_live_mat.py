"""Analyze MATLAB live_mic_receiver MAT evidence and render readable plots."""
from __future__ import annotations
import argparse, json
from pathlib import Path
import sys
import numpy as np
from scipy.io import loadmat
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model.udp_protocol import parse_packet, ProtocolError

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mat", type=Path)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    datagrams = loadmat(args.mat, squeeze_me=True, struct_as_record=False)["datagrams"]
    packets = []
    for item in datagrams:
        data = bytes(np.asarray(item, dtype=np.uint8).ravel())
        try: packets.append(parse_packet(data))
        except ProtocolError: continue
    packets.sort(key=lambda x: x[0].packet_sequence)
    pcm = np.concatenate([m.astype(np.float64) for _, m in packets], axis=1)
    fs = 48828.0; window = 512; hop = 128
    short = np.array([np.sqrt(np.mean((pcm[:, i:i+window]-pcm[:, i:i+window].mean(1,keepdims=True))**2, axis=1)) for i in range(0, pcm.shape[1]-window+1, hop)])
    metrics = []
    for c in range(pcm.shape[0]):
        x = pcm[c]; centered = x - x.mean()
        metrics.append({"channel": c+1, "min": float(x.min()), "max": float(x.max()), "mean": float(x.mean()), "rms": float(np.sqrt(np.mean(centered**2))), "std": float(x.std()), "peak_to_peak": float(x.max()-x.min()), "nonzero_ratio": float(np.count_nonzero(x)/x.size), "short_rms_min": float(short[:,c].min()), "short_rms_max": float(short[:,c].max()), "short_rms_p95": float(np.percentile(short[:,c],95))})
    result = {"mat": str(args.mat), "datagrams": int(len(datagrams)), "pcm_packets": len(packets), "pcm_samples_per_channel": int(pcm.shape[1]), "sample_rate_hz": fs, "metrics": metrics}
    (args.output/"acoustic_metrics.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    t=np.arange(pcm.shape[1])/fs
    fig, axes=plt.subplots(4,2,figsize=(14,11),sharex=True); axes=axes.ravel()
    for c,ax in enumerate(axes):
        ax.plot(t, pcm[c]-pcm[c].mean(), linewidth=.35); ax.set_title(f"CH{c+1}"); ax.grid(True); ax.set_ylabel("centered PCM")
    axes[-1].set_xlabel("seconds"); fig.suptitle("MATLAB acoustic evidence waveform"); fig.tight_layout(); fig.savefig(args.output/"waveform.png",dpi=150); plt.close(fig)
    rt=(np.arange(short.shape[0])*hop+window/2)/fs
    fig,ax=plt.subplots(figsize=(14,6)); ax.plot(rt,short); ax.set_xlabel("seconds"); ax.set_ylabel("short-time RMS"); ax.set_title("5 s-window RMS envelope"); ax.grid(True); ax.legend([f"CH{i+1}" for i in range(8)],ncol=4); fig.tight_layout(); fig.savefig(args.output/"rms_envelope.png",dpi=150); plt.close(fig)
    n=min(pcm.shape[1],fs*5); freqs=np.fft.rfftfreq(int(n),1/fs); spec=np.abs(np.fft.rfft(pcm[:,:int(n)]-pcm[:,:int(n)].mean(1,keepdims=True),axis=1))
    fig,ax=plt.subplots(figsize=(14,6)); ax.plot(freqs,spec.T); ax.set_xlim(0,fs/2); ax.set_xlabel("Hz"); ax.set_ylabel("magnitude"); ax.set_title("5 s spectrum"); ax.grid(True); ax.legend([f"CH{i+1}" for i in range(8)],ncol=4); fig.tight_layout(); fig.savefig(args.output/"spectrum.png",dpi=150); plt.close(fig)
    print(json.dumps(result, indent=2)); return 0
if __name__ == "__main__": raise SystemExit(main())
