# Current Status

Last offline validation: `PENDING_FINAL_RUN`

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

### M3 - MIC_ETHERNET_MATLAB_PASS

Offline synthetic PASS. Python verifies protocol v1, CRC, MTU, sequence gaps,
duplicates, malformed packets, signed PCM and exact reconstruction. MATLAB
R2024a independently reads the packet file and passes the same reconstruction,
loss/duplicate/malformed and known-delay checks. No lwIP stack or physical GEM/
PHY path was run.

### Bonus

Offline PASS. MATLAB GCC-PHAT recovers known 0..7 sample TDOAs and the expected
linear-array angle within the asserted tolerances. No FPGA offload exists.

## Explicitly not tested

- no JTAG;
- no board programming;
- no physical DDR test;
- no physical Ethernet test;
- no real microphone;
- no GPIO/XDC hardware verification;
- no ILA or Hardware Manager.

## Next physical steps

1. Obtain the microphone part number, datasheet and board/adapter schematic.
2. Confirm PDM/I2S/TDM, GPIO topology, I/O voltage, clock and active edge.
3. Confirm the AX7Z020 PS7/DDR/Ethernet preset against the matching vendor project.
4. Implement CDC/overflow handling and XDC for the confirmed real frontend.
5. Perform staged board bring-up: clock/reset, GPIO, DMA/DDR, then Ethernet.

