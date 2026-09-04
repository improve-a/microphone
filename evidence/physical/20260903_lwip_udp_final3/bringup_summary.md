# lwIP/GEM0 bounded transmission attempt

- HDF: `reports/generated/mic_dma.hdf` (existing matched PL handoff; no PL rebuild)
- BSP/ELF: `sw/build/lwip_mic_20260903j`
- Bitstream: `vivado/build/mic_dma_runtime_probe_resetfix_20260903`
- Board endpoint: `169.254.248.10`, host target `169.254.248.53:45123`
- UART evidence: `uart.log`
- XSCT evidence: `xsct.log`
- Python evidence: `udp_capture/udp_stats.json`, `udp_capture/udp_raw_capture.bin`

The UART log proves lwIP/GEM0 initialization, heartbeat submission, DMA cache
invalidate and 4096-frame bounded transmission. Each 128-sample frame is sent
as two protocol-v1 datagrams (90 + 38 samples/channel), preserving the existing
little-endian sample-major format.

The Windows capture recorded zero datagrams and the host ARP table had no entry
for `169.254.248.10`; therefore the physical Ethernet/UDP gate is not claimed.
The MATLAB live gate is also not claimed because no real datagram was received.
No QSPI/Flash operation was performed.
