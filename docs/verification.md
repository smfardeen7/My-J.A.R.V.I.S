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
