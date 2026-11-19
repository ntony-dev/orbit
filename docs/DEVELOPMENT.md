# Development

## Requirements

- macOS 26 or later
- Xcode with the macOS 26 SDK (developed with Xcode 27.2; the Swift package needs Swift tools 6.2)
- No paid Apple Developer account. Builds sign ad hoc by default.

## Build and run

1. Clone the repository:

   ```
   git clone https://github.com/ntony-dev/orbit.git
   cd orbit
   ```

2. Optionally, add your Client ID:

   ```
   cp Config/Local.example.xcconfig Config/Local.xcconfig
   ```

   Then set `SPOTIFY_CLIENT_ID = your_client_id_here`. This file is gitignored. Without it, you enter the Client ID in Orbit's Settings instead.
3. Build and run, either in Xcode (`open Orbit.xcodeproj`, choose the Orbit scheme, then Product > Run) or from the command line:

   ```
   xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug -derivedDataPath build build
   open build/Build/Products/Debug/Orbit.app
   ```

The first build downloads the one Swift package dependency. You don't need XcodeGen.

## Stable signing (stop repeat permission prompts)

macOS identifies an ad-hoc build by its hash, so every rebuild counts as a new app and asks for Keychain and Automation access again. A certificate-signed build is identified by its bundle ID and certificate, which stay the same, so permissions carry over.

1. In `Config/Local.xcconfig`, uncomment the three signing lines and set `DEVELOPMENT_TEAM` to your team ID. The example file shows how to find it. The free Apple Development certificate (Xcode > Settings > Accounts) works.
2. Build and install:

   ```
   Scripts/install-local.sh [--destination folder] [--quit-running] [alias-folder]
   ```

macOS asks for permissions one last time the first time you run the signed copy.

The script:

- makes a clean Release build with your identity, and refuses an ad-hoc result
- installs `Orbit.app` to `/Applications` (or `--destination`) and keeps a copy in `dist/Orbit.app`
- won't replace a running copy unless you pass `--quit-running`, which quits it first and doesn't reopen it
- writes a Finder alias named Orbit into `alias-folder`, if you give one

Keep only one installed copy, so launch at login and permissions refer to a single app.

## Release builds

```
Scripts/archive.sh
```

Writes `dist/Orbit-<version>.zip`, containing `Orbit.app`, `LICENSE.txt` and `Acknowledgements.txt`. The script:

- makes a clean Release build, signed ad hoc whatever `Local.xcconfig` says
- verifies the signature (ad hoc, no team, hardened runtime)
- checks that the third-party notices match the bundled packages' licenses
- prints the architectures and the SHA-256 checksum
- never includes a Client ID. It ignores the one in `Local.xcconfig` and fails if one reaches the app anyway.

`--friends` builds a `.dmg` with your Client ID instead. See [SHARING.md](SHARING.md).

## XcodeGen

`Orbit.xcodeproj` is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed. Regenerate it after you:

- edit `project.yml`, including its Info.plist and entitlement properties (these overwrite `App/Info.plist` and `App/Orbit.entitlements`)
- add, remove or rename files under `App/`

```
brew install xcodegen
xcodegen generate
```

Changes inside `OrbitKit/` or to `.xcconfig` files don't need it.

## Project layout

`App/` is a thin entry point. All the code lives in the local Swift package `OrbitKit`:

| Module | Contents |
|---|---|
| `OrbitCore` | Domain models, service protocols, errors, preferences, the panel contract |
| `SpotifyKit` | OAuth with PKCE, the loopback callback listener, Keychain storage, the Web API client |
| `OrbitEngine` | Spotify automation through Apple events, the playback coordinator, library and account stores, persistence |
| `OrbitUI` | The design system and every SwiftUI view |
| `OrbitShell` | The floating panel, positioning, menu bar item, Settings window, shortcuts, app lifecycle, and the one place concrete services are built |
| `OrbitMocks` | Mock services and fixtures for tests, previews and demo mode |

Dependencies point one way: `OrbitCore` <- `SpotifyKit`, `OrbitEngine` <- `OrbitUI` <- `OrbitShell`.

## Tests and demo mode

Run the unit tests:

```
cd OrbitKit
swift test
```

Run with mock services. This needs no Spotify account, doesn't talk to the Spotify app, and keeps its settings separate from your real ones:

```
open build/Build/Products/Debug/Orbit.app --args --demo
```

Other launch arguments are documented in `OrbitKit/Sources/OrbitShell/LaunchOptions.swift`. Debug-only ones are in `OrbitKit/Sources/OrbitUI/Support/UIDebugOptions.swift`.

## Screenshots

`Scripts/screenshot.sh` launches the Debug build, captures one of its windows by window ID, and quits it, without moving the pointer or changing focus. Your terminal app needs Screen Recording permission.

```
Scripts/screenshot.sh docs/images/library-dark.png --demo --expanded --ui-screen library --ui-shelf --ui-backdrop plain --appearance dark
```

## Acknowledgements

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus (MIT), used for global shortcuts. Its license is in `App/Acknowledgements.txt` and shown under About Orbit in the menu bar.
