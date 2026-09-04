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

## M2-reset rebuild (2026-09-02 17:41 Asia/Shanghai)

- Vivado leaf: `vivado/build/mic_dma_m2reset_clean_20260902`
- SDK workspace: `sw/build/physical_mic_clean_20260902`
- New bitstream, HDF, BSP, `xparameters.h`, `ps7_init.tcl`, and ELF were generated together.
- `MIC_M2_CLOCK_RESET_ASSERT_PASS`, `MIC_M2_DMA_CONFIG_ASSERT_PASS`, `MIC_M2_ADDRESS_ASSERT_PASS`.
- `MIC_DMA_IMPLEMENTATION_PASS WNS=10.232`; `MIC_DMA_VIVADO_PASS`.
- `xparameters.h`: DMA `0x40400000-0x4040FFFF`, SG=0, MM2S=0, S2MM=1, 32-bit S2MM.
- Volatile XSCT sequence completed: `MIC_BITSTREAM_VOLATILE_PROGRAM_PASS`, `MIC_PS7_INIT_PASS`, `MIC_ELF_DOWNLOAD_PASS`.
- CPU still stops at `0x00101384` (`XAxiDma_Reset`) after run; COM4 capture contained zero bytes.
- Netlist evidence confirms DMA clocks on `FCLK_CLK0`, DMA reset on `peripheral_aresetn`, and GP0 AXI handshake nets with one driver/one load.
- No `MIC_AFTER_DMA_CFG`, DMA/DDR, UDP, MATLAB-live, or ILA capture PASS is claimed.
- Logs: `xsct_m2reset_clean_20260902.log`, `uart_m2reset_clean_20260902.log`, `dma_netlist_m2reset_clean_20260902.log`.
- SHA256 bitstream: `EDF5D821B4C36BF3DE93DDF8D2D103EEE54A8EBEFC13F17B74E07966CC0E13F3`.
- SHA256 HDF: `B0304F53FD9C7D8B10B9E74947DA436C32E7DB853758D0863400B8F9A41584FC`.
- SHA256 ELF: `D6C884EEE089660F894AE7B4DD469BAC32C7052CA5F4A3B3222D2B0F4D1AD4B5`.
