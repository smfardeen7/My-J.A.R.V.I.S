#!/usr/bin/env python3
"""Local-only speaker embeddings. No recording, networking, or profile storage.

Use the isolated Python installed by setup-speaker.mjs. A match is a similarity
estimate, not authentication or protection against recordings/voice cloning.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import wave

MODEL_ID = "3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced"
MODEL_SHA256 = "aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2"
VAD_SHA256 = "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6"
SAMPLE_RATE = 16000
MAX_DURATION = 45


def check_model(path, expected_hash):
    path = Path(path)
    if not path.is_file():
        raise ValueError("The local voice model is missing. Run the voice setup again.")
    digest = hashlib.sha256()
    with path.open("rb") as model:
        for chunk in iter(lambda: model.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_hash:
        raise ValueError("The local voice model checksum is invalid. Run the voice setup again.")


def load_audio(path):
    import numpy as np

    path = Path(path)
    if not path.is_file() or path.stat().st_size > SAMPLE_RATE * 2 * MAX_DURATION + 65536:
        raise ValueError("Record a WAV file lasting between three and 45 seconds.")
    try:
        with wave.open(str(path), "rb") as wav:
            if wav.getnchannels() != 1:
                raise ValueError("Voice matching requires a mono recording.")
            if wav.getframerate() != SAMPLE_RATE or wav.getsampwidth() != 2 or wav.getcomptype() != "NONE":
                raise ValueError("Voice matching requires uncompressed 16 kHz, 16-bit PCM audio.")
            duration = wav.getnframes() / SAMPLE_RATE
            if duration < 3:
                raise ValueError("Speak for at least three seconds so I can compare your voice.")
            if duration > MAX_DURATION:
                raise ValueError("Keep voice commands under 45 seconds.")
            raw = wav.readframes(wav.getnframes())
            if len(raw) != wav.getnframes() * 2:
                raise ValueError("The voice recording is incomplete. Please try again.")
    except (wave.Error, EOFError) as error:
        raise ValueError("The voice recording could not be read. Please try again.") from error
    samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    rms = float(np.sqrt(np.mean(samples.astype(np.float64) ** 2)))
    if rms < 0.003:
        raise ValueError("The recording is too quiet. Move closer to the microphone and try again.")
    if float(np.mean(np.abs(samples) >= 0.995)) > 0.02:
        raise ValueError("The recording is clipped. Move a little farther from the microphone.")
    return np.ascontiguousarray(samples), duration, rms


def speech_samples(samples, vad_path):
    import numpy as np
    import sherpa_onnx

    check_model(vad_path, VAD_SHA256)
    config = sherpa_onnx.VadModelConfig()
    config.silero_vad.model = str(vad_path)
    config.silero_vad.threshold = 0.5
    config.silero_vad.min_silence_duration = 0.25
    config.silero_vad.min_speech_duration = 0.25
    config.silero_vad.max_speech_duration = MAX_DURATION
    config.sample_rate = SAMPLE_RATE
    config.num_threads = 1
    config.provider = "cpu"
    if not config.validate():
        raise ValueError("The local speech detector could not be initialized.")
    detector = sherpa_onnx.VoiceActivityDetector(config, buffer_size_in_seconds=MAX_DURATION + 2)
    window = config.silero_vad.window_size
    for offset in range(0, len(samples), window):
        chunk = samples[offset:offset + window]
        if len(chunk) < window:
            chunk = np.pad(chunk, (0, window - len(chunk)))
        detector.accept_waveform(chunk)
    detector.flush()
    segments = []
    while not detector.empty():
        segment = detector.front
        # Read only original audio: do not count any zero padding from VAD.
        start = max(0, int(segment.start))
        end = min(len(samples), start + len(segment.samples))
        if end > start:
            segments.append(samples[start:end])
        detector.pop()
    if not segments:
        raise ValueError("I could not detect clear speech. Please try again in a quiet room.")
    voiced = np.ascontiguousarray(np.concatenate(segments))
    if len(voiced) / SAMPLE_RATE < 3:
        raise ValueError("Speak continuously for at least three seconds so I can compare your voice.")
    return voiced


def extract(model_path, audio_path, vad_path=None):
    import numpy as np
    import sherpa_onnx

    model_path = Path(model_path)
    check_model(model_path, MODEL_SHA256)
    samples, duration, rms = load_audio(audio_path)
    voiced = speech_samples(samples, Path(vad_path) if vad_path else model_path.parent / "silero_vad.onnx")
    config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(model_path), num_threads=2, provider="cpu", debug=False)
    if not config.validate():
        raise ValueError("The local voice matcher could not be initialized.")
    extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
    stream = extractor.create_stream()
    stream.accept_waveform(sample_rate=SAMPLE_RATE, waveform=voiced)
    stream.input_finished()
    if not extractor.is_ready(stream):
        raise ValueError("I need a longer, clearer voice sample. Please try again.")
    embedding = np.asarray(extractor.compute(stream), dtype=np.float64)
    if embedding.shape != (192,) or not np.all(np.isfinite(embedding)):
        raise ValueError("The voice matcher returned an invalid result. Please try again.")
    norm = float(np.linalg.norm(embedding))
    if norm <= 1e-8:
        raise ValueError("The voice matcher returned an empty result. Please try again.")
    return {"embedding": (embedding / norm).tolist(), "duration": duration,
            "speech_duration": len(voiced) / SAMPLE_RATE, "rms": rms,
            "model_id": MODEL_ID, "model_sha256": MODEL_SHA256}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--vad", help="Defaults to silero_vad.onnx alongside the speaker model.")
    args = parser.parse_args()
    try:
        result = extract(args.model, args.audio, args.vad)
    except ImportError:
        result = {"error": "The local voice runtime is missing. Run the voice setup again."}
    except (ValueError, OSError, RuntimeError) as error:
        result = {"error": str(error)}
    except Exception:
        result = {"error": "Voice matching failed. Please retry or set up the voice runtime again."}
    print(json.dumps(result, allow_nan=False, separators=(",", ":")))
    return 1 if "error" in result else 0


if __name__ == "__main__":
    sys.exit(main())
