# Data Format

## PCM and DDR

- Sample format: signed two's-complement 16-bit integer.
- Byte order: little-endian.
- Matrix convention: `matrix[channel, sample]`.
- Serialized order: `s0c0, s0c1, ..., s0cN, s1c0, ...`.
- Default frame: 8 channels x 128 samples = 1024 samples = 2048 bytes.
- AXIS word: earlier sample in bits 15:0, later sample in bits 31:16.

## UDP protocol v1

All multibyte fields and PCM values are little-endian. Header length is 32
bytes.

| Offset | Bytes | Field |
|---:|---:|---|
| 0 | 4 | magic `MIC0` |
| 4 | 1 | version `1` |
| 5 | 1 | header length `32` |
| 6 | 1 | sample format `1` = PCM16LE |
| 7 | 1 | flags: bit0 frame-start, bit1 frame-end |
| 8 | 4 | packet sequence |
| 12 | 4 | frame index |
| 16 | 4 | first sample index within frame |
| 20 | 2 | channel count |
| 22 | 2 | samples per channel in packet |
| 24 | 2 | payload byte length |
| 26 | 2 | reserved, must be zero |
| 28 | 4 | IEEE CRC32 of header bytes 0..27 |

For Ethernet MTU 1500, the maximum UDP datagram is 1472 bytes. After the
32-byte application header an 8-channel packet holds at most 90 samples per
channel. Payload length must equal `channels * samples_per_channel * 2`.

Bad magic, version, format, dimensions, CRC, reserved field, length or MTU is
malformed and ignored. Duplicate/late sequences are ignored. A forward
sequence gap is recorded; affected matrix cells remain zero with validity
false. A receiver cannot infer a missing terminal packet unless it knows the
expected sequence/frame length or observes a later sequence.

Offline packet files concatenate records as `uint32_le length` followed by the
exact UDP datagram bytes.

