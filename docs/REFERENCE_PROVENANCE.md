# Reference Provenance

Read-only reference repository:
`https://github.com/improve-a/nuedc-2026-ax7z020.git`

Reference commit:
`848c9934b05657094b9762c4b7922ef2c0d4ff20`

The new design reuses architecture and verification ideas, not copied project
files:

- `work/02_m2_dma_ddr`: Simple S2MM, GP0 control, HP0 data, IRQ, exact BTT,
  guard slots, bounded timeout, cache flush/invalidate and recovery ordering.
- `work/03_m3_an9238_acquisition`: explicit sample coding, clock/reset and
  capture protocol contracts; no ADC-specific RTL or XDC was reused.
- `work/04_m4_dc_fir`, `work/05_m5_m7_combined`,
  `work/06_g_topic_completion`: deterministic vectors, independent gates,
  machine-readable evidence and separation of model/RTL/build claims.
- `docs/EXAMPLE_INDEX.md`: vendor `10_dma_loopback`, `13_ad9238_dma_hdmi`,
  `25_ad9280_lwip` and `26_ad9238_lwip` were used as topology indexes. The
  Ethernet examples were not present as reusable source files in the reference
  Git tree, so no lwIP implementation was copied.

The reference's board evidence and PASS tokens do not transfer to this project.

