# Runtime LED probe evidence

Build: `mic_dma_runtime_probe_20260903`

Expected active-low mapping from the AX7Z020 user manual (p.37):

- LED1 / J14: `heartbeat_counter[24]`, should blink from FCLK0.
- LED2 / K14: `~interconnect_aresetn`, should be on when reset is released.
- LED3 / J18: `~peripheral_aresetn`, should be on when reset is released.
- LED4 / H18: `~fclk_reset0_n`, should be on when FCLK reset is released.

Hardware download status: complete in the post-reboot retry. The new
bitstream was downloaded through the volatile JTAG path, `ps7_init` and
`ps7_post_config` completed, and XSCT exited before any GPIO/DMA access or ELF
download. The earlier APU/DAP failure logs remain in the same evidence tree.

Hardware LED observation status: awaiting operator report.

Required observation fields after APU/DAP recovery:

```text
LED1: blinking / steady on / off
LED2: on / off
LED3: on / off
LED4: on / off
```
