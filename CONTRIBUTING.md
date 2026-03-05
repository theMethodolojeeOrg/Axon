# Contributing to Axon

Thank you for your interest in contributing. This document covers how to get started, the development workflow, and guidelines for contributions.

## Before You Start

- Read the [README](README.md) for architecture and setup
- Check [open issues](https://github.com/tooury/Axon/issues) and PRs to avoid duplicating work
- For significant changes, open an issue first to discuss your approach

## Setup

### Requirements

- Xcode 16+
- iOS 17+ / macOS 14+ deployment targets
- Apple Developer account (free tier works for simulator builds)

### Building

1. Clone the repo
2. Open `Axon.xcodeproj` (not `.xcworkspace` — this project uses SPM)
3. Xcode will resolve SPM packages automatically on first open
4. Set your Development Team in **Signing & Capabilities** for all targets
5. Build with `Cmd+B`

### Axon-Artifacts Package

Axon depends on a local Swift package (`Axon-Artifacts`) that is being prepared for public release as a separate repository. Check the [Issues](https://github.com/tooury/Axon/issues) page for the tracking issue and setup instructions.

### Firebase / Cloud Backend (Optional)

Cloud features are optional. To use them:

1. Copy `Axon/Config/PublicConfig.example.plist` to `Axon/Config/PublicConfig.local.plist`
2. Fill in your Firebase API key and App ID
3. Never commit `PublicConfig.local.plist`

### iCloud and App Group Identifiers

The entitlements contain identifiers tied to the original developer's Apple account. When building locally you must:

1. Set your own Team ID in **Signing & Capabilities**
2. Change the iCloud container identifier (`iCloud.NeurXAxon`) to one registered under your team
3. Change the app group identifier (`group.com.e2a0f78c018434b3.Axon`) to one registered under your team

These values appear in the following files:
- `Axon/Services/Sync/CloudKitSyncService.swift`
- `Axon/Services/Sync/AudioSyncService.swift`
- `Axon/Services/Sync/UserDataZoneService.swift`
- `Axon/Services/Persistence/CoreDataCloudKitStack.swift`
- `Axon/Views/Components/WidgetConversationSnapshot.swift`
- `AxonLiveActivity/WidgetSharedModels.swift`

A future improvement will centralize these identifiers into a single config file.

### TTS Voices

To use Kokoro on-device TTS, generate the voice data:

```bash
python3 create_voices_builtin.py
```

## Code Style

- **Swift 6 strict concurrency** — `StrictConcurrency` is enabled. Follow existing actor isolation patterns.
- **Logging** — Use `debugLog(.category, "message")` for all new logging. Do not use bare `print()`. Bare `print()` calls are silenced in release builds.
- **File headers** — Follow the existing pattern: `// [Filename].swift / Axon`
- **MARK comments** — Use `// MARK: -` to organize sections within files

## Submitting a Pull Request

1. Fork the repo and create a branch from `main`
2. Make your changes with focused, descriptive commits
3. Ensure the project builds without errors or warnings
4. Open a PR against `main` using the PR template
5. Fill out the template completely

## What We Don't Accept

- API keys, Firebase credentials, or personal data in commits
- Changes to entitlement identifiers (they vary per developer account)
- `GoogleService-Info.plist` or other secrets
- Bare `print()` calls in new code (use `debugLog()`)

## License

By contributing, you agree that your contributions are licensed under the project's [MIT License](LICENSE).
