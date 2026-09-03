# Ordered PS-PL level-shifter probe

The XSCT script now follows the required order exactly:

```
connect -> targets APU -> rst -system -> after 1000
-> targets xc7z020 -> fpga -file (diagnostic bitstream) -> after 500
-> targets Cortex-A9 #0 -> stop -> source ps7_init -> ps7_init
-> ps7_post_config -> SLCR/GP0 probes -> dow ELF -> con
```

There is no reset command after `ps7_post_config`.

Static inspection of the same-round generated `ps7_init.tcl` confirms all
silicon branches of `ps7_post_config` contain:

```
mask_write 0XF8000900 0x0000000F 0x0000000F
mask_write 0XF8000240 0xFFFFFFFF 0x00000000
```

The first ordered hardware retry after the previous GP0 timeout could not
reach step 2 because the JTAG DAP remained in `30000021`; no bitstream was
run and no PL MMIO was attempted in that retry. The prior post-power-cycle
run with the older ordering is preserved in
`evidence/physical/20260903_gpio_diag_powercycle/xsct.log` and showed both
GPIO `0x41200000` and DMA `0x40400030` timing out.
