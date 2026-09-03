# Physical microphone bring-up results

Build: `mic_dma_runtime_probe_resetfix_20260903`

## Hardware evidence

- `MIC_PS_RESET_PHYSICAL_PASS`: LED1 heartbeat blinking; LED2, LED3, and LED4 on.
- `MIC_GP0_GPIO_PHYSICAL_PASS`: pre-ELF read at `0x41200000` returned `0x00000000`.
- `MIC_DMA_AXIL_PRE_ELF_PHYSICAL_PASS`: `0x40400030` read `0x00010002`; `0x40400034` read `0x00000001`.
- `MIC_ELF_DOWNLOAD_PASS` and `MIC_PS7_ELF_PHYSICAL_PASS` completed from the matching diagnostic SDK build.
- `MIC_AFTER_DMA_TRANSFER` completed with `MIC_DMA_STATUS=0x00001002 TIMEOUT=0`.
- DMA guard checks passed and all eight physical-I2S channel statistics were nonzero.

UART capture: `uart.log`  
XSCT capture: `xsct.log`  
LED observation: `led_observation.md`

## MATLAB and UDP status

`matlab_tests.log` contains `MIC_MATLAB_E2E_PASS` and `MIC_GCC_PHAT_DOA_PASS`;
`python_udp_tests.log` reports all six UDP protocol tests passing.
The repository application was built against the standalone BSP, which does
not include the lwIP service; consequently no board-originated UDP datagram or
MATLAB `udpport` live packet was claimed in this run. The UDP packet builder,
parser, and offline MATLAB test vectors remain covered by the repository tests.
