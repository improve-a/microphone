# Overnight Bring-Up Summary

Date: 2026-09-04
Branch: `feat/physical-microphone-bringup`
Source mode: `MIC_SOURCE_MODE=1` (physical I2S only)
Link: 100 Mbps full duplex, board `192.168.1.10/24`, host `192.168.1.2/24`, UDP `45123`

## Changes

- Corrected the I2S one-bit-delay interpretation: the signed 24-bit value is
  `slot[30:7]`, converted with an arithmetic right shift of 8 before int16
  saturation. `slot[31]` is stale/padding and is ignored.
- Removed the two application-level 1 ms sleeps between PCM datagrams. DMA/I2S
  pacing now determines the stream rate, and the frame budget is injectable at
  SDK build time for bounded smoke and soak ELFs.
- Corrected the XDC clock reference to the implemented `clk_fpga_0` object so
  external I2S inputs/outputs are constrained.
- Added the rolling `udp_soak_receiver.py`, explicit expected packet-count
  checking, artifact manifests, adapter counter deltas, and the
  `run_morning_acoustic_test.ps1` one-command entry point.

## Root Causes

The previous near-full-scale PCM was caused by exporting `slot[31:16]` instead
of the delayed-I2S valid bits. The apparent 36.88-second stop was a MATLAB
capture timer expiring during JTAG startup, compounded by per-datagram sleeps;
the board UART had continued progressing.

## Offline Gates

- Python unit tests: 12 passed.
- Host C contracts: `MIC_SW_HOST_BUILD_PASS`.
- RTL suite: `MIC_RTL_SUITE_PASS` (frontend, packer, and I2S scaling tests).
- MATLAB offline protocol/DOA: `MIC_MATLAB_E2E_PASS`,
  `MIC_GCC_PHAT_DOA_PASS`.
- Vivado implementation: `MIC_DMA_VIVADO_PASS`, WNS `+8.689 ns`, DRC 0
  errors, no unconstrained I/O after the XDC correction.
- SDK 2019.1: separate 120,000-frame smoke and 1,374,000-frame soak ELFs,
  both with lwIP and 100M PHY configuration.

## Physical Evidence

Final bitstream:

`D:\microphone\vivado\build\mic_dma_i2s_pcmfix_20260904c\mic_dma.runs\impl_1\mic_dma_system_wrapper.bit`
SHA256: `C1A64D91CD49229CF8D8508200F7DBC16510428E160F8A3FEB0650D225D9D8B8`

Final HDF:

`D:\microphone\reports\generated\mic_dma_i2s_pcmfix_20260904c\mic_dma.hdf`
SHA256: `D8735BF5955C6BC70EB3CFAD7B92F893B4B8AFC66B811C79A645AAEB52CA41B5`

Smoke evidence: `evidence\physical\overnight_final_20260904\smoke_5min_retry`.
It ran 340.047 s, received 240,000/240,000 PCM datagrams (120,000 frames),
20 heartbeats, zero CRC/malformed/loss/duplicate/out-of-order packets, and
UART reported 120,000 DMA submissions/completions with zero timeout/error.
The Windows adapter `ReceivedBytes` delta was 268,802,000 with zero packet
errors.

Authoritative one-hour evidence: `evidence\physical\overnight_final_20260904\soak_1h_retry`.
The receiver ran 3,680.062 s, received exactly 2,748,000/2,748,000 PCM
datagrams (1,374,000 frames), 20 heartbeats, and 10 non-protocol diagnostic
datagrams. Sequence 20..2,748,019 was contiguous; CRC, malformed, missing,
duplicate, out-of-order, bad-header, and bad-length counts were all zero.
UART reported `MIC_UDP_BOUNDED_COMPLETE frames=1374000`, DMA
submissions/completions `1374000/1374000`, zero DMA timeout/error, and
`UDP_OK/UDP_FAIL=2748020/0`. The Windows adapter deltas were
`ReceivedBytes=3,077,762,120`, `ReceivedUnicastPackets=4,122,030`, and zero
packet errors. The JSON validator reports `pass=true`.

The one-hour receiver retained a middle rolling window. The first/last files
in this historical run are empty because board startup and shutdown fell
outside the receiver's rolling-capture boundaries; this does not affect the
complete packet-count, sequence, CRC, or bounded-completion result above.

Recorded physical markers for this branch are:

```
MIC_ETHERNET_L2_100M_PHYSICAL_PASS
MIC_ARP_PHYSICAL_PASS
MIC_UDP_HEARTBEAT_PHYSICAL_PASS
MIC_UDP_PCM_PHYSICAL_PASS
MIC_DMA_CONTINUOUS_1H_PASS
MIC_UDP_CONTINUOUS_1H_PASS
```

## Acoustic Status

No audible stimulus was generated during the overnight run. Therefore
`MIC_ACOUSTIC_1KHZ_PHYSICAL_PASS`, `MIC_ACOUSTIC_RESPONSE_PHYSICAL_PASS`, and
`MIC_MATLAB_LIVE_PHYSICAL_PASS` remain deliberately unrecorded. The morning
entry point is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\microphone\scripts\run_morning_acoustic_test.ps1
```
