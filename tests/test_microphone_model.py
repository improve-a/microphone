import unittest

import numpy as np

from model.microphone_model import (
    DEFAULT_SEED,
    PCM_MAX,
    PCM_MIN,
    base_sample,
    generate_frame,
    iter_pcm_beats,
    pack_pcm16,
    unpack_pcm16,
)


class MicrophoneModelTests(unittest.TestCase):
    def test_channel_delay_and_amplitude(self):
        frame = generate_frame(channels=8, samples_per_frame=64, mode="sine")
        base = frame[0].astype(np.int32)
        for channel in range(1, 8):
            self.assertTrue(np.all(frame[channel, :channel] == 0))
            expected = base[: 64 - channel] >> channel
            np.testing.assert_array_equal(frame[channel, channel:], expected)

    def test_deterministic_pseudo_signal_and_seed(self):
        first = generate_frame(8, 64, mode="pseudo", seed=DEFAULT_SEED)
        second = generate_frame(8, 64, mode="pseudo", seed=DEFAULT_SEED)
        changed = generate_frame(8, 64, mode="pseudo", seed=DEFAULT_SEED + 1)
        np.testing.assert_array_equal(first, second)
        self.assertFalse(np.array_equal(first, changed))

    def test_interleave_metadata_and_frame_boundary(self):
        frame = generate_frame(3, 5, frame_index=7, mode="sine")
        beats = list(iter_pcm_beats(frame, frame_index=7))
        self.assertEqual(len(beats), 15)
        for index, beat in enumerate(beats):
            self.assertEqual(beat.channel_index, index % 3)
            self.assertEqual(beat.sample_index, index // 3)
            self.assertEqual(beat.frame_index, 7)
            self.assertEqual(beat.sample, int(frame[index % 3, index // 3]))
            self.assertEqual(beat.last, index == 14)

    def test_pcm16_signed_range(self):
        for mode in ("sine", "pseudo"):
            frame = generate_frame(8, 257, mode=mode)
            self.assertGreaterEqual(int(frame.min()), PCM_MIN)
            self.assertLessEqual(int(frame.max()), PCM_MAX)
        self.assertEqual(base_sample(24, "sine", DEFAULT_SEED), PCM_MIN)
        self.assertEqual(base_sample(8, "sine", DEFAULT_SEED), PCM_MAX)

    def test_even_dma_packing_little_endian(self):
        frame = np.asarray([[-32768], [32767]], dtype=np.int16)
        words = pack_pcm16(iter_pcm_beats(frame))
        self.assertEqual(len(words), 1)
        self.assertEqual(words[0].data, 0x7FFF8000)
        self.assertEqual(words[0].keep, 0xF)
        self.assertTrue(words[0].last)
        self.assertEqual(unpack_pcm16(words), [-32768, 32767])

    def test_odd_dma_packing_and_exact_byte_count(self):
        frame = generate_frame(3, 5, mode="pseudo")
        beats = list(iter_pcm_beats(frame))
        words = pack_pcm16(iter(beats))
        self.assertEqual(sum(word.byte_count for word in words), 3 * 5 * 2)
        self.assertEqual(words[-1].keep, 0x3)
        self.assertTrue(words[-1].last)
        self.assertEqual(unpack_pcm16(words), [beat.sample for beat in beats])


if __name__ == "__main__":
    unittest.main()

