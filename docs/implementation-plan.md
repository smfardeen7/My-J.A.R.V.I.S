# J.A.R.V.I.S. interface

Goal: reusable controlled React components with an independent interactive demo.

Visual direction: near-black #05070a, cyan #00d9ff, ice #4dc3ff, amber #ff8c42, muted blue #67808d. Rajdhani for geometric interface type, Share Tech Mono for telemetry. A generous central reactor framed by quiet, asymmetrical instrumentation; compact header and persistent bottom command console. SVG/canvas geometry, no image assets required.

Architecture: `JarvisOrb` owns only visual rendering; accepts state, optional AnalyserNode, amplitude, reducedMotion and className. `JarvisHUD` provides controlled layout and callbacks. Audio hooks own browser resources with cleanup. The demo owns simulated responses and state transitions; none live in exported visual components.

Work:
- Scaffold React/TypeScript/Vite with Framer Motion.
- Build analyser-driven orb and particle field, with reduced-motion and visibility controls.
- Build safe microphone hook and state reducer; verify transitions and resource lifecycle.
- Build responsive HUD with telemetry, activity, settings, state selector and command controls.
- Add demo interaction and typed public exports; document microphone/TTS integration.
- Build, exercise states, microphone failure, command flow, settings, mobile layout and reduced motion in browser.

Acceptance: all four states are visually distinct; audio samples affect radial bars and glow without React rerenders at 60fps; microphone is opt-in and stops on exit/unmount; output audio can share an external analyser; fake telemetry is identified as simulated; no assistant service or API key is required.
