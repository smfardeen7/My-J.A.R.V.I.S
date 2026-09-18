# J.A.R.V.I.S. for Mac

The native app uses the React HUD inside an AppKit/WKWebView window. It runs independently of Vite, has a Dock icon and menu bar item, and talks to Ollama on this Mac.

## Installed app

Open `~/Applications/JARVIS.app` from Finder or Spotlight. This installation uses the local `qwen3.5:4b` model. The app starts the installed Ollama executable when no server is available. It does not enable launch at login.

## Talk or type

First, use **Set up my voice with Touch ID** in the Fardeen voice access panel. Authenticate with Touch ID, then record each of the three phrases in your natural voice (8–15 seconds each). Click **Finish sample** after each phrase. Only Fardeen should record these samples. Setup expires after five minutes; Stop or closing the window cancels it. Voice commands remain locked until a complete profile is saved. Re-enrollment and deletion also require Touch ID.

After enrollment, click **Start listening**, speak for at least three seconds, then click the microphone again to send it. For example: “Jarvis, please tell me what time it is.” `Cmd+Shift+Space` toggles listening while the app is focused. First use requests macOS Speech Recognition and Microphone permissions. You can manage them under System Settings → Privacy & Security. If offline English recognition is unavailable, enable English Dictation under System Settings → Keyboard and let its language files download.

Speech recognition explicitly requires on-device support. It fails with instructions instead of falling back to cloud speech. General conversation uses a downloaded local Ollama model. Spoken replies use a lowered-pitch English macOS voice with a subtle metallic effect, and the orb is driven by measured microphone/playback amplitude.

Use **Stop**, Escape, or the menu-bar **Stop voice and thinking** command to cancel. A stop prevents pending actions but cannot undo an app that already opened or a volume adjustment already completed. Closing the window stops activity and keeps the menu bar entry; Cmd+Q exits.

## Voice matching and Touch ID

An offline 3D-Speaker CAMPPlus model compares each recording with three enrollment samples. Silero VAD rejects samples without enough speech. The embedding profile is stored in this Mac account's Keychain; recordings are temporary and deleted after processing or cancellation. Only pretrained models and Python packages are downloaded during setup; user voice data is not uploaded. The runtime is installed in `~/Library/Application Support/JARVIS/voice-runtime` and requires the existing Apple Silicon Python 3.11 installation. See [runtime setup and provenance](speaker-runtime.md).

Voice matching is probabilistic. The initial mean cosine threshold of 0.70 and minimum per-sample score of 0.60 are not calibrated to Fardeen and are not proof of identity. Noise, illness, a changed microphone, recordings, voice cloning, or multiple speakers can cause incorrect acceptance or rejection. This app does not perform anti-spoofing or diarization. Use a quiet room and your usual microphone.

App launches, volume changes, mute and web searches require a fresh, biometric-only Touch ID confirmation, for typed commands as well as spoken commands. Cancelling, replacing a request or closing the window invalidates pending approval. These actions stay blocked if Touch ID is unavailable. Touch ID accepts any fingerprint enrolled in this macOS account, so ensure only trusted fingerprints are registered. Time/date/status and typed AI conversations are available to anyone using the unlocked app. This is a voice filter with protected Mac actions, not exclusive ownership of the entire Mac.

Choose your speech accent in the access panel if the system preference is unsuitable; unavailable offline accents fall back to an available English recognizer. AI replies now have Fardeen's name, current date and actual command capabilities in context. The small local model can still make mistakes and cannot fetch live facts.

## Mac commands

- `Open Safari`, `Open Notes`, `Launch Calculator`, or `Open <installed app name>`.
- `What time is it?`, `What is today's date?`.
- `System status` or `Run diagnostics`: real CPU count, memory, uptime, OS and battery data.
- `Set volume to 40%`, `Mute`, `Unmute`: supported output devices only.
- `Search the web for <query>`: opens your default browser's search. The query goes to the search provider when you explicitly ask for this command.

Other text goes to local AI. Mac actions are recognized from explicit commands, never from a model's response. Arbitrary shell commands, file deletion, messaging and purchases are not implemented.

## Controls

The speaker icon turns spoken replies on/off. The Local AI selector switches between downloaded models; switching clears the conversation. **Refresh connection** reconnects to Ollama. **Clear conversation** clears the in-memory conversation and current response. Conversation history is session-only and is not written to an app database. Model/voice preferences and the Keychain voice profile persist. The temporary file for generated speech is deleted after playback or cancellation; abnormal termination may leave an OS-temporary audio file.

## Build / install

```sh
npm install
npm run mac:voice-setup
npm run mac:build
npm run mac:install
npm test
npm run mac:test
```

The build uses Apple Command Line Tools and bundles the production React files in `build/JARVIS.app`. It ad-hoc signs a local app with microphone/speech entitlements. This is a local installation, not a notarized distribution for other Macs. The install script preserves any previous app as a timestamped backup before installing a replacement. Close the running app before replacing it.

Install Ollama separately if moving to another Mac, then download a suitable local model:

```sh
/Applications/Ollama.app/Contents/Resources/ollama pull qwen3.5:4b
```

The browser demo (`npm run dev`) remains a UI simulation. Native functionality is enabled only inside the bundled desktop app.

## Structure

- `native/main.swift`: app lifecycle, menu, local asset scheme, restricted message bridge and orchestration.
- `native/VoiceService.swift`: offline recognition, permission lifecycle, local TTS and amplitude.
- `native/MacCommands.swift`: explicit command parsing and native actions.
- `native/OllamaClient.swift`: loopback-only local AI, local-model checks, cancellation and bounded history.
- `src/desktop/`: native event controller and live connection UI.

Reference APIs: [Apple Speech authorization](https://developer.apple.com/documentation/speech/sfspeechrecognizer/requestauthorization(_:)), [Apple speech audio buffers](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/buffercallback), [Ollama API](https://docs.ollama.com/api), [Qwen 3.5 local models](https://ollama.com/library/qwen3.5).
