# Local voice matching runtime

Run `node scripts/setup-speaker.mjs` once on this Apple Silicon Mac. It uses an existing arm64 Python 3.11 installation, creates a private isolated environment in `~/Library/Application Support/JARVIS/voice-runtime`, and downloads fixed, SHA-256 checked release artifacts. The app runs the bundled `speaker-worker.py` with that environment's `venv/bin/python3 -I`. The worker performs no networking, microphone capture, playback, or profile storage. It only reads the supplied recording and returns JSON to the native app.

The dependencies are sherpa-onnx 1.13.8, sherpa-onnx-core 1.13.8, and NumPy 2.2.6. Their exact PyPI wheel URLs and hashes are in the setup script. Python and its bootstrapped pip come from the existing Python installation. `pip` installs only the verified local wheels, with dependency resolution and the package index disabled.

The selected model is `3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx` (28,281,164 bytes), published by sherpa-onnx from the [3D-Speaker CAM++ model](https://github.com/modelscope/3D-Speaker/blob/main/speakerlab/bin/infer_sv_batch.py). It supports Chinese and English and produces 192-dimensional speaker embeddings. It is distributed by the [official sherpa-onnx speaker release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models). Its pinned SHA-256 is `aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2`.

The [Silero VAD model](https://k2-fsa.github.io/sherpa/onnx/vad/silero-vad.html) detects speech before embedding extraction. Its pinned SHA-256 is `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6`. Both models are checked again whenever the worker uses them. No model bytes are committed to this repository.

The input must be a mono 16 kHz, signed 16-bit PCM WAV lasting 3–45 seconds, with at least 3 seconds of detected speech. Quiet, clipped, incomplete, stereo, and unsupported-format recordings fail with a structured error. The success result includes `embedding`, `duration`, `speech_duration`, `rms`, `model_id`, and `model_sha256`. The embedding is normalized to unit length; the native caller can compare vectors with cosine similarity and enforce a longer minimum for enrollment.

Voice matching is probabilistic. It does not detect playback, cloned voices, or prove that a particular human is present. Conservative thresholds can reject the real owner in noise or with a changed microphone; they cannot guarantee rejection of every other voice. Touch ID confirmation for Mac actions remains necessary. A user account with access to the application files can also replace its runtime; this is a convenience voice filter within the Mac account's security boundary.

## Verification

The boundary suite is `native/tests/test_speaker_worker.py`. Run it with the installed runtime Python. It tests short, quiet, clipped, stereo, wrong-rate, oversized, and substituted-model inputs.

The optional `native/tests/test_speaker_worker_integration.py` uses four public WAVs from the official speaker release, placed in `build/speaker-test-audio`: `fangjun-sr-2.wav`, `fangjun-test-sr-1.wav`, `leijun-sr-1.wav`, and `leijun-test-sr-1.wav`. On this Mac, same-speaker similarities were 0.820 and 0.716; cross-speaker similarities were 0.201–0.307. It also rejects a pure tone using the real VAD model. These are limited integration checks, not a representative biometric evaluation, and do not establish a real-world false-accept rate. The initially investigated English WeSpeaker ResNet34 model was rejected because its cross-speaker similarities were too high in these fixtures.
