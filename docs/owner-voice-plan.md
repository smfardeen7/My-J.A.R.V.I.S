# Fardeen voice update

The user selected local voice enrollment with Touch ID for Mac actions and reported both recognition and answer errors.

1. Fix anchored natural command parsing and ground local answers in Fardeen's name, actual capabilities and current date. Test command acceptance and rejection.
2. Capture private, bounded speech samples alongside transcripts. Improve locale selection and fail closed on recognizer errors. Render an intelligible robotic voice with actual output metering.
3. Extract local speaker embeddings using a pinned pretrained ONNX model. Enroll three consistent samples after Touch ID; store only embeddings in Keychain. Delete temporary recordings after use.
4. Reject unmatched or inadequate voice samples before sending text to the command dispatcher or local AI. Require a fresh Touch ID confirmation for every app, volume, mute or web-search action, including typed requests. Cancellation invalidates pending authentication and verification.
5. Add an enrollment panel with progress, quality errors, accent selection and a clear explanation that voice matching is probabilistic and can accept replays. Touch ID accepts any fingerprint enrolled in this macOS account; it cannot identify a particular named person.
6. Run parser, profile, worker, audio and React tests; compile/sign/install the native app and inspect its UI. Fardeen must supply his own enrollment recordings and Touch ID. Do not fabricate enrollment or claim measured speaker accuracy without those recordings.

No continuous background listening, cloud voice processing, model-generated commands or arbitrary shell execution. Enrollment and reset need Touch ID. Voice commands remain locked until enrollment and the local verification runtime are ready.
