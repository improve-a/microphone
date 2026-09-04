# Controlled 1 kHz Physical Acceptance

Date: 2026-09-04
Branch: `feat/physical-microphone-bringup`
Evidence directory: `evidence/physical/acoustic_handshake_20260904_204104_671`

The capture used the validated physical-I2S bitstream and 100 Mbps smoke ELF.
XSCT recorded volatile bitstream programming, PS7 initialization, ELF download,
and CPU run. UART reported `MIC_SOURCE=PHYSICAL_I2S` and
`PCM_RIGHT_SHIFT=8`. MATLAB R2024a owned UDP port 45123 before programming and
wrote the ready marker after 100 valid PCM packets.

## Capture and protocol

- MATLAB duration: 124.608 seconds, 6,084,352 samples per channel.
- Received: 95,098 datagrams, including 95,068 PCM packets, 20 heartbeats, and
  10 raw diagnostics.
- PCM packet sequence: 20 through 95,087, contiguous.
- Missing, duplicate, out-of-order, malformed, CRC, and frame-layout errors: 0.
- Quiet RMS CH1-CH7: 9.39, 10.39, 9.96, 10.30, 10.37, 9.67, 10.87.

## Controlled stimulus

The analyzer found the two requested intervals without using chat timestamps:

- Left: detected 46.5-53.5 s; clean 5.0 s analysis plateau.
- Right: detected 57.0-62.5 s; clean 3.5 s analysis plateau.
- CH1-CH7 dominant frequency in both intervals: exactly 1000.0 Hz.
- CH1-CH7 RMS above quiet: +21.30 to +36.63 dB.
- CH1-CH7 clipping ratio: 0% in both intervals.
- CH8: zero RMS, zero peak, zero nonzero samples, and no 1 kHz component in
  both intervals.
- Right-versus-left 1 kHz amplitude change across CH1-CH7: +3.68 to +15.23 dB.

The detailed per-channel values and the complete acceptance decision are in
`tone_analysis/tone_response.json`; packet counters are also isolated in
`tone_analysis/udp_stats.json`. The raw MAT, UART, XSCT, waveform, spectrum,
RMS-envelope, interval, and left/right plots are retained in this directory.
`artifact_hashes.json` records their sizes and SHA256 values.
The full 85.5 MB `live_capture.mat` remains in the local evidence directory;
`tone_analysis/controlled_tone_excerpt.mat` is the compressed, reviewable MAT
containing both tone intervals plus surrounding quiet baselines.

## Final offline regression

- Python unit tests: 12/12 passed.
- Host C contracts: compiled with `-Werror`; `MIC_SW_HOST_BUILD_PASS`.
- MATLAB R2024a: `MIC_MATLAB_E2E_PASS` and `MIC_GCC_PHAT_DOA_PASS`.

## Accepted markers

```
MIC_ACOUSTIC_1KHZ_PHYSICAL_PASS
MIC_ACOUSTIC_RESPONSE_PHYSICAL_PASS
MIC_MATLAB_LIVE_PHYSICAL_PASS
```
