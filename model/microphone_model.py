"""Deterministic multichannel PCM source and AXI packing reference model."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterator, Literal

import numpy as np


PCM_BITS = 16
PCM_MIN = -(1 << (PCM_BITS - 1))
PCM_MAX = (1 << (PCM_BITS - 1)) - 1
DEFAULT_SEED = 0x13579BDF

# One period of a Q1.15 sine. The same integer values are used by the RTL.
SINE_Q15 = np.asarray(
    [
        0,
        6393,
        12539,
        18204,
        23170,
        27245,
        30273,
        32137,
        32767,
        32137,
        30273,
        27245,
        23170,
        18204,
        12539,
        6393,
        0,
        -6393,
        -12539,
        -18204,
        -23170,
        -27245,
        -30273,
        -32137,
        -32768,
        -32137,
        -30273,
        -27245,
        -23170,
        -18204,
        -12539,
        -6393,
    ],
    dtype=np.int32,
)


@dataclass(frozen=True)
class PcmBeat:
    sample: int
    channel_index: int
    sample_index: int
    frame_index: int
    last: bool


@dataclass(frozen=True)
class AxisWord:
    data: int
    keep: int
    last: bool
    byte_count: int


def _xorshift32(value: int) -> int:
    value &= 0xFFFFFFFF
    value ^= (value << 13) & 0xFFFFFFFF
    value ^= value >> 17
    value ^= (value << 5) & 0xFFFFFFFF
    return value & 0xFFFFFFFF


def pseudo_q15(index: int, seed: int = DEFAULT_SEED) -> int:
    """Return a deterministic signed 16-bit pseudo-sample for an index."""

    value = _xorshift32((index & 0xFFFFFFFF) ^ (seed & 0xFFFFFFFF))
    raw = value & 0xFFFF
    return raw - 0x10000 if raw & 0x8000 else raw


def base_sample(index: int, mode: Literal["sine", "pseudo"], seed: int) -> int:
    if mode == "sine":
        return int(SINE_Q15[index & 0x1F])
    if mode == "pseudo":
        return pseudo_q15(index, seed)
    raise ValueError(f"unsupported mode: {mode}")


def channel_sample(
    frame_index: int,
    sample_index: int,
    channel_index: int,
    samples_per_frame: int,
    mode: Literal["sine", "pseudo"] = "sine",
    seed: int = DEFAULT_SEED,
) -> int:
    """Generate one PCM16 sample.

    Channel c is delayed by c samples and attenuated by an arithmetic right
    shift of min(c, 15). Samples before the delayed signal begins are zero.
    """

    if min(frame_index, sample_index, channel_index) < 0:
        raise ValueError("indices must be non-negative")
    if samples_per_frame <= 0:
        raise ValueError("samples_per_frame must be positive")
    if sample_index < channel_index:
        return 0
    absolute_index = frame_index * samples_per_frame + sample_index - channel_index
    raw = base_sample(absolute_index, mode, seed)
    return int(raw >> min(channel_index, 15))


def generate_frame(
    channels: int = 8,
    samples_per_frame: int = 128,
    frame_index: int = 0,
    mode: Literal["sine", "pseudo"] = "sine",
    seed: int = DEFAULT_SEED,
) -> np.ndarray:
    """Return a channel x sample signed PCM16 matrix."""

    if channels <= 0 or samples_per_frame <= 0:
        raise ValueError("channels and samples_per_frame must be positive")
    matrix = np.empty((channels, samples_per_frame), dtype=np.int16)
    for sample in range(samples_per_frame):
        for channel in range(channels):
            matrix[channel, sample] = channel_sample(
                frame_index, sample, channel, samples_per_frame, mode, seed
            )
    return matrix


def iter_pcm_beats(matrix: np.ndarray, frame_index: int = 0) -> Iterator[PcmBeat]:
    """Serialize a channel x sample matrix in sample-major channel order."""

    if matrix.ndim != 2:
        raise ValueError("matrix must have shape channel x sample")
    channels, samples = matrix.shape
    for sample in range(samples):
        for channel in range(channels):
            yield PcmBeat(
                sample=int(matrix[channel, sample]),
                channel_index=channel,
                sample_index=sample,
                frame_index=frame_index,
                last=(sample == samples - 1 and channel == channels - 1),
            )


def pack_pcm16(beats: Iterator[PcmBeat]) -> list[AxisWord]:
    """Pack two little-endian PCM16 values into each 32-bit DMA word."""

    words: list[AxisWord] = []
    low: PcmBeat | None = None
    for beat in beats:
        encoded = beat.sample & 0xFFFF
        if low is None:
            if beat.last:
                words.append(AxisWord(encoded, 0x3, True, 2))
            else:
                low = beat
            continue
        data = (encoded << 16) | (low.sample & 0xFFFF)
        words.append(AxisWord(data, 0xF, beat.last, 4))
        low = None
    if low is not None:
        raise ValueError("unterminated PCM frame: final beat did not assert last")
    return words


def unpack_pcm16(words: list[AxisWord]) -> list[int]:
    samples: list[int] = []
    for word in words:
        if word.keep not in (0x3, 0xF):
            raise ValueError(f"illegal TKEEP 0x{word.keep:x}")
        values = [word.data & 0xFFFF]
        if word.keep == 0xF:
            values.append((word.data >> 16) & 0xFFFF)
        samples.extend(value - 0x10000 if value & 0x8000 else value for value in values)
    return samples

