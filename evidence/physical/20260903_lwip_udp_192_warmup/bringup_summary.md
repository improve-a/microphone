# lwIP GEM0 physical bring-up attempt (192.168.1.x)

Date: 2026-09-03

## Configuration

- Board: `192.168.1.10/24`
- Host: `192.168.1.2/24`, Windows interface `以太网 3` (ifIndex 17)
- UDP: port `45123`
- Bitstream: existing `mic_dma_system_wrapper.bit` from `mic_dma_runtime_probe_resetfix_20260903`
- ELF: `sw/build/lwip_mic_20260903l/mic_dma_app/Debug/mic_dma_app.elf`

## Software and JTAG result

SDK build and JTAG download passed. UART confirms lwIP GEM0 initialization, heartbeat enqueue, DMA physical pass, 4096 frames, and non-zero eight-channel PCM statistics. The ELF includes a bounded 2 s lwIP service warm-up before PCM to allow ARP resolution.

## Host capture result

`udp_capture.py` listened on `0.0.0.0:45123` for 120 s. `udp_stats.json` records zero datagrams, zero heartbeats, and zero PCM packets. `arp -a` contains no dynamic entry for `192.168.1.10`. Windows adapter statistics recorded zero received bytes/packets on `以太网 3`.

## Interpretation

No UDP or MATLAB live test was started, and neither physical PASS token is recorded. The host-side self-test proves the Python listener works. GEM0 emitted only link-layer ARP traffic while the host received no frames, so the remaining blocker is the Ethernet layer between the board and `以太网 3` (cable, switch/port, or board Ethernet connector/path). Re-run the same listener/JTAG command after the board is connected to this interface; no Vivado/PL rebuild or UDP protocol change is required.

Evidence: `uart.log`, `xsct.log`, `gem_regs.xsct.log`, `ethernet3_stats.txt`, `arp_a.txt`, and `udp_capture/udp_stats.json`.
