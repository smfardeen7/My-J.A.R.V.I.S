"""Real-model regression using public official fixtures; never records the mic.

First download fangjun-sr-2.wav, fangjun-test-sr-1.wav, leijun-sr-1.wav,
and leijun-test-sr-1.wav from the sherpa-onnx speaker-recongition-models
release into build/speaker-test-audio. Run with voice-runtime/venv/bin/python3.
These smoke tests are NOT a biometric accuracy or anti-spoof certification.
"""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("speaker_worker", ROOT / "scripts/speaker-worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
MODELS = Path.home() / "Library/Application Support/JARVIS/voice-runtime/models"
MODEL = MODELS / (worker.MODEL_ID + ".onnx")


class RealSpeakerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.embeddings = {}
        for name in ["fangjun-sr-2", "fangjun-test-sr-1", "leijun-sr-1", "leijun-test-sr-1"]:
            result = worker.extract(MODEL, ROOT / "build/speaker-test-audio" / (name + ".wav"))
            cls.embeddings[name] = np.asarray(result["embedding"])

    def test_same_speakers_have_high_similarity(self):
        self.assertGreater(float(self.embeddings["fangjun-sr-2"] @ self.embeddings["fangjun-test-sr-1"]), 0.70)
        self.assertGreater(float(self.embeddings["leijun-sr-1"] @ self.embeddings["leijun-test-sr-1"]), 0.70)

    def test_different_speakers_rejected_by_conservative_threshold(self):
        for first in ["fangjun-sr-2", "fangjun-test-sr-1"]:
            for second in ["leijun-sr-1", "leijun-test-sr-1"]:
                self.assertLess(float(self.embeddings[first] @ self.embeddings[second]), 0.40)

    def test_embeddings_are_finite_and_normalized(self):
        for vector in self.embeddings.values():
            self.assertEqual(vector.shape, (192,))
            self.assertTrue(np.all(np.isfinite(vector)))
            self.assertAlmostEqual(float(np.linalg.norm(vector)), 1, places=6)

    def test_vad_rejects_a_loud_tone(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tone.wav"
            samples = (np.sin(2 * np.pi * 440 * np.arange(64000) / 16000) * 16000).astype("<i2")
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16000)
                wav.writeframes(samples.tobytes())
            with self.assertRaisesRegex(ValueError, "speech"):
                worker.extract(MODEL, path)


if __name__ == "__main__":
    unittest.main()
