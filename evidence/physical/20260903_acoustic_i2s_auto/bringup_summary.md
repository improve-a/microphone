# Acoustic bring-up result (2026-09-03)

The previous 100M ELF was intentionally not used for the acoustic gate after
analysis proved its bitstream had `SOURCE_MODE=0` (the deterministic synthetic
source). Vivado was rebuilt once with `MIC_SOURCE_MODE=1`; the existing AXI,
DMA, clock/reset and Ethernet interfaces were unchanged. Implementation passed
with WNS `10.624 ns`. The matching lwIP BSP and ELF were regenerated from the
new HDF.

The automated run used MATLAB R2024a `udpport` as the exclusive listener on
UDP/45123, downloaded the new bitstream and ELF through XSCT, and retained the
raw MATLAB MAT plus generated waveform, RMS-envelope, spectrum and Python
analysis artifacts. MATLAB received `21,310` valid PCM datagrams with zero
malformed, CRC, missing, duplicate or out-of-order packets.

`detect_acoustic_response.py` found zero time-separated aggregate peaks. CH1-7
were saturated near full scale (`~23.1k RMS`, both +/-32768 present), while CH8
had RMS ratio `0.000316` relative to the real channels and was effectively the
documented unused slot. The data therefore demonstrates a real-I2S extraction
or input-level problem, not a plotting-scale problem; no acoustic or MATLAB
physical PASS marker is recorded.

Evidence: `live_capture.mat`, `matlab_console.log`, `uart.log`, `xsct.log`,
`analysis/`, and `acoustic_response/` in this directory.
