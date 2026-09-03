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

## Automated real-I2S acoustic attempt

The automated capture initially proved that the prior bitstream selected the
deterministic synthetic source (`SOURCE_MODE=0`), so no acoustic conclusion was
drawn from it. Because this was a direct data-analysis finding, Vivado was
rebuilt once with `MIC_SOURCE_MODE=1`; the existing AXI/DMA/Ethernet design was
unchanged. The new implementation passed with WNS `+10.624 ns`, and a matching
100M lwIP BSP/ELF was generated.

In `evidence/physical/20260903_acoustic_i2s_auto/`, MATLAB received 21,310
valid PCM datagrams with zero protocol errors or sequence loss. CH1-7 were
saturated near full scale and had no three time-separated RMS peaks during the
requested three-clap action; CH8 was effectively zero. This isolates the
remaining blocker to real-I2S extraction/input level (edge/valid-bit or pin
electrical state). Neither `MIC_ACOUSTIC_RESPONSE_PHYSICAL_PASS` nor
`MIC_MATLAB_LIVE_PHYSICAL_PASS` is recorded.

The temporary firewall rule could not be created without elevation; the exact
administrator command is recorded in the task log. No Vivado rebuild, Flash
write, or DMA/PL modification was used.

## Overnight stability evidence (2026-09-04)

The corrected physical-I2S build was exercised at 100 Mbps full duplex with
the rolling receiver. The 5-minute smoke run is under
`evidence/physical/overnight_final_20260904/smoke_5min_retry` and completed
120,000 frames (240,000 PCM packets) in 340.047 s with zero CRC, malformed,
loss, duplicate, or ordering errors. DMA submissions/completions were
120000/120000 and the Windows `ReceivedBytes` delta was 268,802,000.

The authoritative one-hour retry is under
`evidence/physical/overnight_final_20260904/soak_1h_retry`. It ran 3,680.062 s
and received exactly 1,374,000 frames (2,748,000 PCM packets), 20 heartbeat
packets, and 10 non-protocol diagnostics. Sequence 20..2,748,019 was
contiguous; CRC, malformed, missing, duplicate, out-of-order, bad-header, and
bad-length counts were all zero. UART reported
`MIC_UDP_BOUNDED_COMPLETE frames=1374000`, DMA submissions/completions
`1374000/1374000`, and `UDP_OK/UDP_FAIL=2748020/0`. The Windows adapter deltas
were `ReceivedBytes=3,077,762,120` and `ReceivedUnicastPackets=4,122,030`,
with zero packet errors; `udp_soak_stats.json` reports `pass=true`.

These runs establish the bounded real-I2S Ethernet/UDP stability gates. They
were intentionally silent and do not record any controlled acoustic or live
MATLAB response PASS marker. The only remaining physical action is the
morning controlled acoustic test using the one-command entry point in the
overnight summary.
