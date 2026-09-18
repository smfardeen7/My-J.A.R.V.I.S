"""Boundary tests; run with the installed voice-runtime Python after setup."""
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import wave

WORKER = Path(__file__).resolve().parents[2] / "scripts" / "speaker-worker.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("speaker_worker", WORKER)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class SpeakerInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "capture.wav"

    def tearDown(self):
        self.temp.cleanup()

    def audio(self, seconds=4, channels=1, rate=16000, sample=1000):
        with wave.open(str(self.path), "wb") as wav:
            wav.setnchannels(channels)
            wav.setsampwidth(2)
            wav.setframerate(rate)
            wav.writeframes(struct.pack("<h", sample) * int(seconds * rate * channels))

    def test_rejects_short_audio(self):
        self.audio(seconds=2)
        with self.assertRaisesRegex(ValueError, "three seconds"):
            worker.load_audio(self.path)

    def test_rejects_silence(self):
        self.audio(sample=0)
        with self.assertRaisesRegex(ValueError, "quiet"):
            worker.load_audio(self.path)

    def test_rejects_stereo_instead_of_guessing_a_speaker(self):
        self.audio(channels=2)
        with self.assertRaisesRegex(ValueError, "mono"):
            worker.load_audio(self.path)

    def test_rejects_wrong_sample_rate(self):
        self.audio(rate=48000)
        with self.assertRaisesRegex(ValueError, "16 kHz"):
            worker.load_audio(self.path)

    def test_rejects_clipped_recording(self):
        self.audio(sample=32767)
        with self.assertRaisesRegex(ValueError, "clipped"):
            worker.load_audio(self.path)

    def test_rejects_excessive_capture(self):
        self.audio(seconds=46)
        with self.assertRaisesRegex(ValueError, "45 seconds"):
            worker.load_audio(self.path)

    def test_returns_bounded_normalized_samples(self):
        self.audio()
        samples, duration, rms = worker.load_audio(self.path)
        self.assertEqual(len(samples), 64000)
        self.assertEqual(duration, 4)
        self.assertAlmostEqual(rms, 1000 / 32768, places=5)

    def test_rejects_model_substitution(self):
        self.path.write_bytes(b"wrong model")
        with self.assertRaisesRegex(ValueError, "checksum"):
            worker.check_model(self.path, "00" * 32)


if __name__ == "__main__":
    unittest.main()
