# Verification

- Production TypeScript/Vite build succeeds.
- 15 Vitest tests pass: valid and invalid state transitions, state reset, opt-in microphone access, analyser routing without speaker echo, repeated starts, late permission results after stop/unmount, cleanup, permission retry, unsupported browser handling, and clearing stale microphone errors.
- Browser checked at desktop (1440px), tablet/default preview, and mobile (390px and 320px). No horizontal overflow at tested widths.
- All four state preview controls update reactor state. A typed command and diagnostic shortcut progress through the demo controller and display a sample response.
- Motion toggle produces `data-reduced-motion="true"` and disables ring animation. Operating-system reduced-motion handling is implemented through Motion and CSS.
- Mobile microphone control retains an accessible name. Empty command submission is disabled. Interface settings open and close, with focus restored on close.
- No browser console warnings/errors observed.
- Real microphone hardware and actual TTS playback were not exercised in the browser session. Their integration is provided through Web Audio, with microphone lifecycle covered by mocks and real-output routing documented in README.
- No universal frame-rate guarantee: canvas avoids React updates per frame, DPR is capped, and render loops pause in background tabs. Actual performance depends on hardware.

## Native Mac assistant

- React/controller suite: 21 passing tests across four files.
- Native command/model suite: 32 passing checks, including cancel-before-execution and cloud-model exclusion. No tests open apps or alter volume.
- AppKit/WebKit/voice/services compile for macOS14+ on arm64 using installed Command Line Tools. Local app code signature verifies.
- Installed and launched `~/Applications/JARVIS.app`; bundled web assets render without a development server.
- Downloaded local `qwen3.5:4b`; actual Ollama inference returned a greeting. The installed app also completed a full local AI request and displayed the response.
- Native app displayed live microphone state during user interaction. No automated utterance was supplied to the hardware microphone.
- Voice-service checks exercised cancellation, late final callbacks, CAF writing/cleanup and real local TTS generation (23,368 PCM frames at22,050Hz). Synthetic lifecycle tests were run during implementation; persistent command/controller tests are available with `npm run mac:test` and `npm test`.
- Desktop sidebar commands become inert when hidden, cancellation remains accessible while final transcription is pending, and activity IDs avoid secure-context-only browser APIs.
# Owner voice update — 2026-09-17

- React/Vitest: 24 passing checks.
- Native: 59 command/model, 12 speaker-profile, 12 synthetic voice/audio and 25 authentication checks pass. Touch ID tests use injected contexts and never approve a real action.
- Python worker: 8 input-validation checks and 4 real-model integration checks pass, using public model-release fixtures. A pure tone is rejected. These fixtures do not establish real-world biometric accuracy.
- Live Ollama probes correctly used Fardeen's name and current date, suggested native diagnostics for battery questions, and remembered a simulated failed app launch without claiming success.
- Production React build, Swift compile and strict code-signature verification succeeded. Updated app installed to `~/Applications/JARVIS.app`; previous version preserved by installer.
- Native UI shows the enrolled-voice setup panel and a ready local runtime. Clicking the mic before enrollment stays idle and displays the enrollment requirement. A typed “Jarvis, please tell me what time it is?” reaches the native time handler and speaking state.
- Fardeen must perform Touch ID and record three real samples to complete enrollment. No owner recordings, actual fingerprint approval, or representative impostor trials were fabricated. Microphone recognition quality, subjective robotic voice quality and real-owner acceptance need his live trial.
