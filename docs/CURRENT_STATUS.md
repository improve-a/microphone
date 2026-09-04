# Current Status

Last offline validation: `mic_offline_20260901_164521_utc_2628c1294c8b`

## Milestones

### M1 - MIC_FRONTEND_PASS

Offline PASS. Python golden-model tests and Vivado 2019.1 XSim verify PCM16
signedness, channel/sample/frame order, deterministic sine and pseudo sources,
known per-channel amplitude/delay, reset, valid/ready stalls and TLAST.

### M2 - MIC_DMA_PASS

Offline PASS only. Vivado 2019.1 validated the BD, synthesized the RTL pipeline,
and fully routed the XC7Z020 design. OOC WNS was +5.680 ns; full implementation
WNS was +3.749 ns and WHS +0.042 ns. Final utilization was 1,759 LUTs (3.31%),
2,261 registers (2.13%), one BRAM tile (0.71%) and zero DSPs. Final DRC had no
Error/Critical Warning; retained tool-generated items were RTSTAT-10 Warning
and REQP-181 Advisory inside Xilinx interconnect/DMA structures.

The host C contract test compiled with `-Werror`. SDK 2019.1 built the BSP and
`mic_dma_app.elf` (text 45,032; data 2,648; bss 25,192 bytes). This does not
prove DMA or DDR on hardware.

The final bounded regression runner passed Python, host C, OOC, SDK and MATLAB
as `mic_offline_20260901_164521_utc_2628c1294c8b`. The separately executed
XSim and full Vivado logs are retained under the project build/report paths;
Vivado 2019.1's second-simulation cleanup is not included in the bounded runner
because it can hang after the simulation PASS token is emitted.

### M3 - MIC_ETHERNET_MATLAB_PASS

Offline synthetic PASS. Python verifies protocol v1, CRC, MTU, sequence gaps,
duplicates, malformed packets, signed PCM and exact reconstruction. MATLAB
R2024a independently reads the packet file and passes the same reconstruction,
loss/duplicate/malformed and known-delay checks. No lwIP stack or physical GEM/
PHY path was run.

### Bonus

Offline PASS. MATLAB GCC-PHAT recovers known 0..7 sample TDOAs and the expected
linear-array angle within the asserted tolerances. No FPGA offload exists.

### Physical bring-up status

Environment and JTAG identification passed on 2026-09-02: Vivado/XSCT 2019.1,
XC7Z020 and both Cortex-A9 targets were detected. The bitstream and ELF were
downloaded volatile-only and PS7 initialization completed. This is recorded as
`MIC_ENVIRONMENT_PHYSICAL_PASS`; it does not imply microphone, DMA, DDR,
Ethernet or MATLAB physical PASS.

The recovery run after a full power cycle and direct-PC JTAG reached
`MIC_PS7_ELF_PHYSICAL_PASS`: the physical-mode bitstream and latest ELF were
downloaded and the A9 was running. UART `COM4` emitted the boot and source
metadata lines. The CPU then remained in `XAxiDma_Reset`, and the DMA status
could not be read because the debug halt timed out. Hardware Manager batch,
Tcl and GUI probes did not expose a usable ILA command path on this Vivado
installation, so no ILA waveform was obtained.

The next physical gate is an ILA capture of BCK/WS/D0-D3. Do not infer DMA,
microphone or UDP success from the ELF/CPU token.

## Explicitly not tested

- no real ILA waveform or measured BCK/WS frequency;
- no confirmed I2S edge/bit alignment;
- no physical microphone PCM acceptance;
- no physical DDR/DMA acceptance;
- no lwIP UDP transmission or MATLAB live packet;
- no QSPI/Flash write (intentionally).

## 2026-09-03 acoustic gate

The 100M Ethernet/UDP path is physically passing (see
`evidence/physical/20260903_final_acceptance`). An automated MATLAB `udpport`
run then exposed that the earlier bitstream still selected the deterministic
synthetic source (`SOURCE_MODE=0`). A single Vivado rebuild with
`MIC_SOURCE_MODE=1` selected the real I2S frontend; the existing AXI/DMA/DDR
and Ethernet design was not otherwise changed. Vivado implementation passed
(WNS +10.624 ns), and the matching lwIP BSP/ELF was rebuilt.

The real-I2S acoustic run received 21,310 valid PCM datagrams with zero CRC,
malformed, loss, duplicate or ordering errors. CH1-7 were saturated near
full-scale and showed no three-peak acoustic response; CH8 was effectively
zero. This is an I2S extraction/input-level blocker (edge/valid-bit or pin
electrical state), not a MATLAB scaling issue. The automated evidence is under
`evidence/physical/20260903_acoustic_i2s_auto/`. The markers
`MIC_ACOUSTIC_RESPONSE_PHYSICAL_PASS` and `MIC_MATLAB_LIVE_PHYSICAL_PASS`
remain intentionally unrecorded.

## Next physical steps

1. Obtain the microphone part number, datasheet and board/adapter schematic.
2. Confirm PDM/I2S/TDM, GPIO topology, I/O voltage, clock and active edge.
3. Confirm the AX7Z020 PS7/DDR/Ethernet preset against the matching vendor project.
4. Implement CDC/overflow handling and XDC for the confirmed real frontend.
5. Perform staged board bring-up: clock/reset, GPIO, DMA/DDR, then Ethernet.

## 2026-09-04 overnight final status

The current branch now has a matching `MIC_SOURCE_MODE=1` physical-I2S
bitstream, HDF, and 100 Mbps lwIP ELF. The I2S conversion is based on the
standard one-bit I2S delay (`signed(slot[30:7]) >>> 8`) before int16
saturation. The prior apparent 36.88-second stop was a host capture-window
artifact compounded by per-datagram sleeps; bounded frame limits and UART
completion reporting are now explicit.

The physical 100 Mbps path passed the 5-minute smoke and authoritative 1-hour
retry with exact PCM packet counts, zero CRC/malformed/loss/duplicate/
out-of-order errors, and complete DMA/UDP counters. Details and artifact hashes
are in `docs/overnight_bringup_summary.md` and
`docs/physical_evidence_20260903.md`.

## 2026-09-04 controlled acoustic acceptance

The two-turn MATLAB/JTAG capture under
`evidence/physical/acoustic_handshake_20260904_204104_671` received 95,068
contiguous PCM packets with zero CRC, malformed, missing, duplicate,
out-of-order, or frame-layout errors. It automatically found the requested
left and right controlled-tone intervals at 46.5-53.5 s and 57.0-62.5 s.
CH1-CH7 measured exactly 1000.0 Hz in both intervals, with RMS 21.30-36.63 dB
above quiet and zero clipping. CH8 was identically zero in both clean tone
plateaus. UART confirmed `MIC_SOURCE=PHYSICAL_I2S` and `PCM_RIGHT_SHIFT=8`.

The final physical markers are now recorded:

```
MIC_ACOUSTIC_1KHZ_PHYSICAL_PASS
MIC_ACOUSTIC_RESPONSE_PHYSICAL_PASS
MIC_MATLAB_LIVE_PHYSICAL_PASS
```
