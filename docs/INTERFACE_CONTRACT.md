# Interface Contract

## PCM stream

| Signal | Meaning |
|---|---|
| `pcm_data` | signed two's-complement PCM16 |
| `pcm_valid` | producer presents all output fields |
| `pcm_ready` | consumer can accept one sample |
| `pcm_last` | final channel of final sample in the frame |
| `channel_index` | zero-based channel number |
| `sample_index` | zero-based time sample within frame |
| `frame_index` | zero-based frame counter |

A transfer occurs only on `valid && ready`. While `valid && !ready`, data,
metadata and `last` remain stable. Order is sample-major: all channels for
sample 0, then all channels for sample 1. Active-low reset clears all indices
and deasserts valid; the first post-reset frame begins at `(frame,sample,ch) =
(0,0,0)`. `mode_i` and `seed_i` must remain stable outside reset.

## DMA AXI stream

| Signal | Contract |
|---|---|
| `TDATA[15:0]` | earlier PCM16 sample |
| `TDATA[31:16]` | later PCM16 sample, if present |
| `TKEEP` | `1111`, or `0011` for one odd final sample |
| `TLAST` | final packed word of one PCM frame |

The packer never accepts input when a pending output is stalled. BTT is the
exact sum of asserted TKEEP bytes, normally `channels * samples * 2`. The DMA
must be armed before source reset is released or the source must be safely
stalled by `TREADY=0`; this baseline uses the latter behavior.

## Buffer ownership

States are `FREE`, `DMA_OWNED`, and `CPU_OWNED`. The legal sequence is:

```text
FREE --prepare+flush+submit--> DMA_OWNED
DMA_OWNED --IOC/poll completion--> CPU_OWNED
CPU_OWNED --invalidate+verify+repoison--> FREE
```

Timeout/error never transitions directly to FREE. Reset DMA, invalidate and
inspect guards, reinitialize the complete slot, then return ownership.

## Real frontend boundary

The eventual physical frontend must produce this PCM contract. Its protocol,
clock-domain crossing, overflow behavior and XDC are not defined until the
hardware facts are confirmed.

