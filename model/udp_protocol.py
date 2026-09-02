"""Versioned UDP wire protocol for interleaved microphone PCM16."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import struct
import zlib

import numpy as np


MAGIC = b"MIC0"
PROTOCOL_VERSION = 1
SAMPLE_FORMAT_PCM16_LE = 1
HEADER_STRUCT = struct.Struct("<4sBBBBIIIHHHHI")
HEADER_BYTES = HEADER_STRUCT.size
ETHERNET_MTU = 1500
MAX_UDP_DATAGRAM = ETHERNET_MTU - 20 - 8
FLAG_FRAME_START = 0x01
FLAG_FRAME_END = 0x02


class ProtocolError(ValueError):
    pass


@dataclass(frozen=True)
class PacketHeader:
    flags: int
    packet_sequence: int
    frame_index: int
    sample_start: int
    channel_count: int
    samples_per_channel: int
    payload_length: int


@dataclass
class Reconstruction:
    frames: dict[int, np.ndarray] = field(default_factory=dict)
    validity: dict[int, np.ndarray] = field(default_factory=dict)
    missing_sequences: list[int] = field(default_factory=list)
    duplicate_sequences: list[int] = field(default_factory=list)
    malformed_packets: int = 0
    late_sequences: list[int] = field(default_factory=list)


def max_samples_per_packet(channel_count: int, mtu: int = ETHERNET_MTU) -> int:
    if channel_count <= 0:
        raise ValueError("channel_count must be positive")
    available = mtu - 20 - 8 - HEADER_BYTES
    result = available // (2 * channel_count)
    if result < 1:
        raise ValueError("channel_count does not fit one PCM sample in the MTU")
    return result


def encode_packet(
    matrix: np.ndarray,
    packet_sequence: int,
    frame_index: int,
    sample_start: int,
    flags: int = 0,
) -> bytes:
    if matrix.ndim != 2 or matrix.shape[0] == 0 or matrix.shape[1] == 0:
        raise ValueError("matrix must be non-empty channel x sample data")
    if matrix.shape[0] > 0xFFFF or matrix.shape[1] > 0xFFFF:
        raise ValueError("matrix dimensions exceed protocol fields")
    pcm = np.asarray(matrix, dtype="<i2", order="F")
    # transpose+ravel(C) emits sample-major, channel-interleaved values.
    payload = pcm.T.ravel(order="C").tobytes()
    if HEADER_BYTES + len(payload) > MAX_UDP_DATAGRAM:
        raise ValueError("packet exceeds Ethernet MTU 1500")
    prefix = HEADER_STRUCT.pack(
        MAGIC,
        PROTOCOL_VERSION,
        HEADER_BYTES,
        SAMPLE_FORMAT_PCM16_LE,
        flags & 0xFF,
        packet_sequence & 0xFFFFFFFF,
        frame_index & 0xFFFFFFFF,
        sample_start & 0xFFFFFFFF,
        matrix.shape[0],
        matrix.shape[1],
        len(payload),
        0,
        0,
    )
    crc = zlib.crc32(prefix[:28]) & 0xFFFFFFFF
    header = prefix[:28] + struct.pack("<I", crc)
    return header + payload


def parse_packet(datagram: bytes) -> tuple[PacketHeader, np.ndarray]:
    if len(datagram) < HEADER_BYTES:
        raise ProtocolError("truncated header")
    fields = HEADER_STRUCT.unpack_from(datagram)
    (
        magic,
        version,
        header_length,
        sample_format,
        flags,
        packet_sequence,
        frame_index,
        sample_start,
        channel_count,
        samples_per_channel,
        payload_length,
        reserved,
        header_crc,
    ) = fields
    if magic != MAGIC:
        raise ProtocolError("bad magic")
    if version != PROTOCOL_VERSION or header_length != HEADER_BYTES:
        raise ProtocolError("unsupported version or header length")
    if sample_format != SAMPLE_FORMAT_PCM16_LE:
        raise ProtocolError("unsupported sample format")
    if reserved != 0:
        raise ProtocolError("reserved field must be zero")
    if not channel_count or not samples_per_channel:
        raise ProtocolError("zero channel or sample count")
    expected_payload = channel_count * samples_per_channel * 2
    if payload_length != expected_payload:
        raise ProtocolError("payload length does not match dimensions")
    if len(datagram) != HEADER_BYTES + payload_length:
        raise ProtocolError("datagram length does not match payload length")
    if HEADER_BYTES + payload_length > MAX_UDP_DATAGRAM:
        raise ProtocolError("datagram exceeds Ethernet MTU 1500")
    if zlib.crc32(datagram[:28]) & 0xFFFFFFFF != header_crc:
        raise ProtocolError("header CRC32 mismatch")
    values = np.frombuffer(datagram, dtype="<i2", offset=HEADER_BYTES).copy()
    matrix = values.reshape(samples_per_channel, channel_count).T
    return (
        PacketHeader(
            flags,
            packet_sequence,
            frame_index,
            sample_start,
            channel_count,
            samples_per_channel,
            payload_length,
        ),
        matrix,
    )


def packetize_frame(
    matrix: np.ndarray,
    frame_index: int = 0,
    starting_sequence: int = 0,
) -> list[bytes]:
    channels, samples = matrix.shape
    chunk_samples = max_samples_per_packet(channels)
    packets = []
    for offset in range(0, samples, chunk_samples):
        count = min(chunk_samples, samples - offset)
        flags = (FLAG_FRAME_START if offset == 0 else 0) | (
            FLAG_FRAME_END if offset + count == samples else 0
        )
        packets.append(
            encode_packet(
                matrix[:, offset : offset + count],
                starting_sequence + len(packets),
                frame_index,
                offset,
                flags,
            )
        )
    return packets


def reconstruct_packets(
    datagrams: list[bytes],
    expected_channels: int,
    samples_per_frame: int,
) -> Reconstruction:
    result = Reconstruction()
    seen: set[int] = set()
    expected_sequence: int | None = None
    for datagram in datagrams:
        try:
            header, payload = parse_packet(datagram)
        except ProtocolError:
            result.malformed_packets += 1
            continue
        sequence = header.packet_sequence
        if sequence in seen:
            result.duplicate_sequences.append(sequence)
            continue
        if expected_sequence is None:
            expected_sequence = sequence
        if sequence < expected_sequence:
            result.late_sequences.append(sequence)
            continue
        if sequence > expected_sequence:
            result.missing_sequences.extend(range(expected_sequence, sequence))
        expected_sequence = sequence + 1
        seen.add(sequence)
        if header.channel_count != expected_channels:
            result.malformed_packets += 1
            continue
        end = header.sample_start + header.samples_per_channel
        if end > samples_per_frame:
            result.malformed_packets += 1
            continue
        frame = result.frames.setdefault(
            header.frame_index,
            np.zeros((expected_channels, samples_per_frame), dtype=np.int16),
        )
        valid = result.validity.setdefault(
            header.frame_index,
            np.zeros((expected_channels, samples_per_frame), dtype=bool),
        )
        region = valid[:, header.sample_start:end]
        if np.any(region):
            result.duplicate_sequences.append(sequence)
            continue
        frame[:, header.sample_start:end] = payload
        region[:] = True
    return result


def write_packet_file(path: Path, datagrams: list[bytes]) -> None:
    with path.open("wb") as handle:
        for datagram in datagrams:
            handle.write(struct.pack("<I", len(datagram)))
            handle.write(datagram)


def read_packet_file(path: Path) -> list[bytes]:
    contents = path.read_bytes()
    datagrams: list[bytes] = []
    offset = 0
    while offset < len(contents):
        if len(contents) - offset < 4:
            raise ProtocolError("truncated packet-file length")
        length = struct.unpack_from("<I", contents, offset)[0]
        offset += 4
        if length == 0 or offset + length > len(contents):
            raise ProtocolError("invalid packet-file record length")
        datagrams.append(contents[offset : offset + length])
        offset += length
    return datagrams

