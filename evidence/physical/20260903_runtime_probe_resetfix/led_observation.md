# Runtime LED probe after reset polarity fix

Build: `mic_dma_runtime_probe_resetfix_20260903`

The reset adapter now carries the reference M2/M0 interface metadata, so
Vivado asserted `C_EXT_RESET_HIGH=1` for `proc_sys_reset_0`.

The new bitstream was downloaded through volatile JTAG after APU system reset;
`ps7_init`, `ps7_post_config`, and SLCR readback completed. XSCT stopped at
`MIC_RUNTIME_LED_OBSERVE_READY` before all GPIO/DMA reads and before ELF
download.

Operator observation:

```text
LED1: blinking
LED2: on
LED3: on
LED4: on
```

The operator reported this state after a full PC and board power cycle while
the `mic_dma_runtime_probe_resetfix_20260903` bitstream was loaded. This is
physical evidence that FCLK0 is running and `FCLK_RESET0_N`,
`interconnect_aresetn`, and `peripheral_aresetn` are all deasserted.

```text
MIC_PS_RESET_PHYSICAL_PASS
```

Mapping: LED1/J14 is the FCLK heartbeat; LED2/K14 is
`~interconnect_aresetn`; LED3/J18 is `~peripheral_aresetn`; LED4/H18 is
`~FCLK_RESET0_N`. All LEDs are active low.
