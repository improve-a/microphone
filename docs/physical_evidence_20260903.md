# Physical Ethernet and microphone evidence (2026-09-03)

The stable branch configuration is 100 Mbps full duplex with the board at
`192.168.1.10` and the Windows adapter `以太网 3` at `192.168.1.2` (ifIndex 17).
The board MAC is `00:0A:35:00:01:02`; the observed Realtek MAC is
`00:E0:4C:17:46:98`. The KSZ9031 skew remains the strapped values `0077`,
`7777`, `7777`, `3DEF`.

## Evidence

- `MIC_ETHERNET_L2_100M_PHYSICAL_PASS`: [20260903_external_l2_arp](../evidence/physical/20260903_external_l2_arp/)
- Dynamic ARP RX and static ARP bypass: [20260903_full_100m_rerun](../evidence/physical/20260903_full_100m_rerun/)
- MATLAB `udpport` live parser and plotting path: [20260903_matlab_live_plot_batch2](../evidence/physical/20260903_matlab_live_plot_batch2/)

The bounded run received 20 heartbeats, 10 raw IPv4/UDP diagnostic frames, and
all 8192 PCM datagrams (4096 frames x 2 packets). Python reported zero CRC,
malformed, missing, duplicate, or out-of-order packets and 4,194,304 valid
PCM samples, of which 3,817,480 were non-zero. MATLAB received the same 8222
datagrams with zero malformed or CRC errors after classifying the raw diagnostic
frames separately.

The Windows adapter counter delta for the bounded run was `ReceivedBytes`
`+9,177,040`, `ReceivedUnicastPackets` `+12,318`, and zero discarded packets
or packet errors. `arp -a` learned `192.168.1.10 -> 00-0a-35-00-01-02`.

Physical acceptance markers, recorded only after the real captures above:

```
MIC_ETHERNET_L2_100M_PHYSICAL_PASS
MIC_ARP_PHYSICAL_PASS
MIC_UDP_HEARTBEAT_PHYSICAL_PASS
MIC_UDP_PCM_PHYSICAL_PASS
```

MATLAB `udpport` live receive/plot parsing passed with the same 8222 datagrams;
`MIC_MATLAB_LIVE_PHYSICAL_PASS` is intentionally left pending until a user
performs the requested拍手 or per-channel voice-response check in the live plot.

The temporary firewall rule could not be created without elevation; the exact
administrator command is recorded in the task log. No Vivado rebuild, Flash
write, or DMA/PL modification was used.
