# Runtime LED probe evidence

Build: `mic_dma_runtime_probe_20260903`

Expected active-low mapping from the AX7Z020 user manual (p.37):

- LED1 / J14: `heartbeat_counter[24]`, should blink from FCLK0.
- LED2 / K14: `~interconnect_aresetn`, should be on when reset is released.
- LED3 / J18: `~peripheral_aresetn`, should be on when reset is released.
- LED4 / H18: `~fclk_reset0_n`, should be on when FCLK reset is released.

Hardware observation status: pending. The 2026-09-03 volatile XSCT attempts
could enumerate `xc7z020` but failed to enumerate the APU/DAP (`AP transaction
error`, DAP status `30000021`). They therefore stopped before `rst -system` and
before bitstream download; no LED state was observed in this session.

Required observation fields after APU/DAP recovery:

```text
LED1: blinking / steady on / off
LED2: on / off
LED3: on / off
LED4: on / off
```
