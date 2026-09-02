from pathlib import Path
import tempfile
import unittest

import numpy as np

from model.microphone_model import generate_frame
from model.udp_protocol import (
    FLAG_FRAME_END,
    FLAG_FRAME_START,
    HEADER_BYTES,
    ProtocolError,
    max_samples_per_packet,
    packetize_frame,
    parse_packet,
    read_packet_file,
    reconstruct_packets,
    write_packet_file,
)


class UdpProtocolTests(unittest.TestCase):
    def setUp(self):
        self.frame = generate_frame(8, 256, mode="pseudo")
        self.packets = packetize_frame(self.frame, frame_index=11, starting_sequence=100)

    def test_mtu_header_and_signed_recovery(self):
        self.assertEqual(HEADER_BYTES, 32)
        self.assertEqual(max_samples_per_packet(8), 90)
        for packet in self.packets:
            self.assertLessEqual(len(packet), 1472)
        first_header, first = parse_packet(self.packets[0])
        last_header, _ = parse_packet(self.packets[-1])
        self.assertTrue(first_header.flags & FLAG_FRAME_START)
        self.assertTrue(last_header.flags & FLAG_FRAME_END)
        np.testing.assert_array_equal(first, self.frame[:, : first.shape[1]])

    def test_sequence_and_exact_matrix_reconstruction(self):
        result = reconstruct_packets(self.packets, 8, 256)
        self.assertEqual(result.missing_sequences, [])
        self.assertEqual(result.duplicate_sequences, [])
        self.assertEqual(result.malformed_packets, 0)
        self.assertTrue(np.all(result.validity[11]))
        np.testing.assert_array_equal(result.frames[11], self.frame)

    def test_loss_duplicate_and_malformed_policy(self):
        stream = [self.packets[0], self.packets[0], self.packets[2]]
        corrupted = bytearray(self.packets[-1])
        corrupted[0] ^= 0xFF
        stream.append(bytes(corrupted))
        result = reconstruct_packets(stream, 8, 256)
        self.assertEqual(result.duplicate_sequences, [100])
        self.assertEqual(result.missing_sequences, [101])
        self.assertEqual(result.malformed_packets, 1)
        self.assertFalse(np.all(result.validity[11]))

    def test_malformed_crc_and_lengths_rejected(self):
        for mutation in ("crc", "truncated"):
            packet = bytearray(self.packets[0])
            if mutation == "crc":
                packet[31] ^= 1
            else:
                packet = packet[:-1]
            with self.assertRaises(ProtocolError):
                parse_packet(bytes(packet))

    def test_packet_file_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "packets.bin"
            write_packet_file(path, self.packets)
            self.assertEqual(read_packet_file(path), self.packets)

    def test_known_channel_delay_recovery(self):
        frame = generate_frame(8, 128, mode="sine")
        result = reconstruct_packets(packetize_frame(frame), 8, 128)
        recovered = result.frames[0].astype(np.int32)
        for channel in range(1, 8):
            np.testing.assert_array_equal(
                recovered[channel, channel:], recovered[0, :-channel] >> channel
            )


if __name__ == "__main__":
    unittest.main()

