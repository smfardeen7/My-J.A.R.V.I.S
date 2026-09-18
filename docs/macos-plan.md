# J.A.R.V.I.S. for macOS

User-selected scope: standalone desktop assistant with voice, app launching, Mac commands, and local Ollama conversations.

- Retain reusable HUD and browser demo. Select DesktopApp only when the signed native bridge is injected.
- Native AppKit/WKWebView executable bundles the built React files; no dev server dependency.
- Scheme handler serves only bundled assets. Bridge accepts fixed command names from the bundled main frame. Block remote navigation/new windows and arbitrary shell execution.
- Apple Speech recognition requests microphone/speech permissions on explicit start only; requires on-device recognition. Local speech playback drives the orb with measured amplitude. Stop/cancel tears down resources.
- Deterministic Mac actions support opening installed apps, time/date, real system status, and volume. General conversation goes to loopback Ollama with a local-only model. AI replies never execute Mac actions.
- Menubar and Dock entry open the assistant; closing window stops voice/inference. No launch-at-login changes.
- Settings expose local model, spoken replies, refresh connection, stop, and clear conversation. Indicate actual connection, activity and microphone state. Hide simulated metrics in native mode.
- Build with existing Command Line Tools, ad-hoc sign with microphone/speech entitlements, install to ~/Applications/JARVIS.app, and launch. User grants macOS privacy permissions if requested.
- Verify native compilation, command parser, React tests/build, native bridge UI, real local conversation and cancellation. Record any hardware/permission-dependent verification limitations.
