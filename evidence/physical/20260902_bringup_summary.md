# Physical Bring-up Evidence

- Date: 2026-09-02 (Asia/Shanghai)
- Git branch: `feat/physical-microphone-bringup`
- Hardware: ALINX AX7Z020, XC7Z020-2CLG400
- JTAG: XSCT detected APU, Cortex-A9 #0/#1, xc7z020
- Bitstream: volatile-only download completed
- PS7: `MIC_PS7_INIT_PASS` completed
- Bitstream SHA256: `49159B977DC56A4E4CB87386A29E73B5B9C21708910A0DE5FFEDB4CB2778C33F`
- UART: CP210x `COM4`, 115200 8N1; captures contained zero bytes
- Failure: ELF download ended with `APB AP transaction error, DAP status f0000021`
- Follow-up: XSCT then reported `DAP (JTAG port open error)` and no A9 targets

No physical ILA, DMA/DDR, UDP or MATLAB-live PASS is claimed. No QSPI write was
performed. The next required operation is to power-cycle the board and, if the
DAP error repeats, connect JTAG directly to the computer instead of the dock.
