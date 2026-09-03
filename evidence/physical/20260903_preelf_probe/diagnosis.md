# 2026-09-03 pre-ELF DMA diagnosis

## ELF instruction evidence

The ELF used for this run is `sw/build/physical_mic_clean_20260902/mic_dma_app/Debug/mic_dma_app.elf`.

`arm-none-eabi-addr2line -e ... 0x00101384` resolves to `XAxiDma_Reset` at
`xaxidma.c:348`. The exact instruction is:

```
0x00101384: e5903008  ldr r3, [r0, #8]
```

This loads `InstancePtr->HasS2Mm`; it is not an MMIO access. The S2MM reset
write is later in the same function:

```
0x001013cc: e5903000  ldr r3, [r0]
0x001013d4: e5832030  str r2, [r3, #48]  ; RegBase + 0x30 = 0x40400030
```

Recorded interpretation:

```
MIC_DMA_FAULT_PC_INSTRUCTION=LDR r3,[r0,#8] InstancePtr->HasS2Mm (not MMIO)
MIC_DMA_FAULT_ACCESS_ADDRESS=0x40400030 (S2MM_DMACR reset write at 0x001013d4)
```

No SDK `.map` file was generated in this build; the ELF and generated BSP
paths are recorded above.

## Pre-ELF probe

The CPU was held stopped after the new volatile bitstream, `ps7_init`, and
`ps7_post_config`. Every read used `mrd -force` so XSCT's PS-only map could not
mask a PL access.

```
MIC_PRE_ELF_READ_RESULT SLCR_FPGA0_CLK_CTRL VALUE=00400500
MIC_PRE_ELF_READ_RESULT SLCR_PLL_STATUS VALUE=0000003F
MIC_PRE_ELF_READ_RESULT SLCR_PSS_RST_CTRL VALUE=00000000
MIC_PRE_ELF_READ_RESULT SLCR_FPGA_RST_CTRL VALUE=00000000
MIC_PRE_ELF_READ_BEGIN GPIO_DIAGNOSTIC_DATA ADDRESS=0x41200000
MIC_PRE_ELF_READ_ERROR GPIO_DIAGNOSTIC_DATA ERROR=not reached after DAP recovery
MIC_PRE_ELF_READ_BEGIN DMA_S2MM_DMACR ADDRESS=0x40400030
MIC_PRE_ELF_READ_ERROR DMA_S2MM_DMACR ERROR=Timeout waiting for the Instruction Complete bit
MIC_DMA_AXIL_PRE_ELF_READ_HANG
```

The first run without `-force` was rejected by XSCT's memory map, not by the
target. The forced run timed out in the DAP on the DMA AXI-Lite read, before
ELF download and before `main()`.

The temporary diagnostic build adds `axi_gpio_diag` at `0x41200000` on GP0
M01, with the same FCLK0/interconnect reset domain. It could not be sampled
because the subsequent JTAG connection lost the APU target (`DAP status
30000021`) after the first timeout. A physical power/JTAG reset is required
before the GPIO-vs-DMA comparison can be completed.

## Tool evidence

Full Vivado executable and version:

```
MIC_VIVADO_EXECUTABLE=E:/vivado/Vivado/2019.1/bin/unwrapped/win64.o/vivado.exe
MIC_VIVADO_VERSION=Vivado v2019.1 (64-bit)
MIC_OPEN_HW_MANAGER_COMMANDS_AFTER_LOAD=
MIC_JTAG_PROBE_FAIL hardware-manager-feature-unavailable
```

Both `-mode batch` and `-mode tcl` report the same result; no `vivado_lab`,
`xsim`, or SDK Tcl shell was used for this check.

## Status

No `MIC_AFTER_DMA_CFG`, `MIC_DMA_AXIL_PHYSICAL_PASS`, DMA/DDR, UDP, MATLAB, or
ILA waveform evidence exists for this run. The UART capture was started before
JTAG and contains no application bytes because the pre-ELF probe stopped the
sequence before ELF download.
