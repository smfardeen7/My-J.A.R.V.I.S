# J.A.R.V.I.S. — implementation guide

Built a React/TypeScript assistant interface with SVG and audio-reactive visuals, then integrated a native macOS assistant with local Ollama conversation, speech recognition and spoken replies. Added explicit Mac commands, a local owner-voice filter and Touch ID confirmation for actions. The browser demo is a UI simulation; the Mac app supplies the local assistant workflow. Voice matching is a fallible filter, not replay-proof authentication.

![Source-derived architecture for J.A.R.V.I.S.](images/project-overview.png)

The graphic describes the checked-in implementation. It is an architecture diagram, not a screenshot, a benchmark result or evidence of a live production deployment.

## Source map

- **React voice HUD:** State machine, SVG reactor and audio visualisation. See [src/state.ts](../src/state.ts).
- **macOS bridge:** Speech recognition, spoken replies and app commands. See [native/OllamaClient.swift](../native/OllamaClient.swift).
- **Local Ollama:** Conversation stays on the configured local model server. See [native/MacCommands.swift](../native/MacCommands.swift).
- **Explicit actions:** Owner voice filter plus Touch ID for Mac actions. See [native/OwnerAuthenticator.swift](../native/OwnerAuthenticator.swift).

## Scope

Browser demo simulates responses. Voice matching is a fallible filter, not replay-proof authentication.

This presentation was checked against source revision `f9b7be714ca7b7b4f11d2471aaf5ac548bbd5962` on September 24, 2026. The documentation update does not claim a new application test run, cloud deployment or performance measurement.
