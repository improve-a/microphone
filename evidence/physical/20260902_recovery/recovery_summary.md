# Recovery Bring-up Summary

- JTAG direct-to-PC recovery: `MIC_JTAG_TARGETS_RECOVERED`
- Targets: APU, Cortex-A9 #0/#1, `xc7z020`, Legacy Debug Hub
- Bitstream: `MIC_BITSTREAM_VOLATILE_PROGRAM_PASS`
- PS7: `MIC_PS7_INIT_PASS`
- ELF: `MIC_ELF_DOWNLOAD_PASS`, CPU state `Running`, PC `0x00101300`
- Software token: `MIC_PS7_ELF_PHYSICAL_PASS`
- UART: `COM4` received `MIC_DMA_SW_BOOT` and physical source metadata
- CPU after capture: PC remained `0x00101300`, symbol resolves to `XAxiDma_Reset`
- DMA probe: XSCT could not halt/read registers (`Cannot halt processor core, timeout`)
- Hardware Manager: Vivado batch and Tcl mode returned
  `hardware-manager-feature-unavailable`; GUI mode produced no probe output.

The physical DMA/DDR gate and ILA gate remain FAIL/NOT RUN. No UDP or MATLAB
live test was attempted. No QSPI write was performed.
