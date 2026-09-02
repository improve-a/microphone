# Architecture

## Scope

The current baseline is an offline-verifiable microphone data path for the
AX7Z020 (`xc7z020clg400-2`). Physical microphone facts are UNKNOWN, so the
board-facing frontend is deliberately marked `REAL_MIC_PROTOCOL_PENDING`.

```text
synthetic PCM16 source
  -> PCM16-to-AXIS32 packer
  -> AXI DMA Simple S2MM
  -> PS7 S_AXI_HP0
  -> DDR buffer contract
  -> versioned UDP packet format
  -> Python/MATLAB channel x sample reconstruction
```

The PS7 M_AXI_GP0 port controls AXI DMA at `0x40400000`. DMA payload traffic
uses HP0. FCLK0 clocks all PL logic and AXI ports at the PS configuration's
100 MHz setting. One `proc_sys_reset` instance provides synchronous peripheral
reset release. DMA S2MM interrupt is connected to `IRQ_F2P`; tonight's
software build uses bounded polling and retains a reset-based error recovery
path.

## M1 frontend abstraction

`pcm_synthetic_source` generates either a 32-entry Q1.15 sine or a seeded
xorshift pseudo-signal. Channel `c` is delayed by `c` samples and attenuated by
an arithmetic right shift of `min(c, 15)`. It emits one PCM sample per
valid/ready transfer and carries channel, sample, frame and final-beat metadata.

`real_mic_frontend_pending` is intentionally inert. It has no GPIO, clock or
protocol assumptions.

## M2 DMA path

`pcm_axis_packer` packs two sample-major PCM16 values into one little-endian
AXIS32 word. An odd final sample uses `TKEEP=0011`. `TLAST` marks exactly the
last byte-bearing word of a frame. Default BTT is `8 * 128 * 2 = 2048` bytes.

Software uses three 64-byte-aligned slots. Each has a 64-byte front guard,
2048-byte payload and 64-byte rear guard. Cache flush occurs before DMA
ownership; whole-slot invalidate occurs before CPU verification. Timeout or
DMA error requires bounded DMA reset before reuse.

## M3 UDP path

The protocol carries versioned metadata and PCM16LE payloads in Ethernet-MTU
sized datagrams. Packet files use a little-endian uint32 length prefix for
offline replay. Missing samples remain zero and have a separate validity mask;
duplicates and malformed packets are counted and ignored.

## Bonus

MATLAB contains an offline GCC-PHAT/TDOA and linear-array broadside-angle
golden model. No GCC-PHAT, MUSIC, EVD, matrix decomposition or beamforming is
implemented in FPGA logic.

