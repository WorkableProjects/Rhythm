# Rhythm

A calm, local-first iPhone app that shows a student's school day at a glance: the current period, time remaining, and what's next — in the app, in Home Screen widgets, and in a Live Activity.

by Workable & Claude

The product and engineering specification is [`Rhythm_Dev_Spec.md`](Rhythm_Dev_Spec.md). Implementation decisions and deviations are recorded in §16 of that file.

## Project layout

```text
Rhythm.xcodeproj            Xcode project (app, widget extension, unit + UI test targets)
Packages/RhythmCore/        Swift package: schedule engine and all pure logic (+ 93 tests)
Rhythm/                     App target
  App/                      Entry point, AppModel (composition root), router, root view
  Models/                   SwiftData models, schema version + migration plan, mapping
  Scheduling/               ScheduleRepository (all persistence reads/writes)
  Services/                 Notifications, Live Activity, widget snapshot, preferences
  Intents/                  App Intents + App Shortcuts
  DesignSystem/             Spacing/radius/motion tokens and shared components
  Features/                 Onboarding, Today, Schedule, Quicklinks, Settings
  Resources/                Asset catalog (app icon, accent colour)
Shared/                     Compiled into both the app and the widget extension
RhythmWidgets/              Widget extension: small/medium widgets and the Live Activity UI
RhythmTests/                App-level unit tests (SwiftData repository, integration mapping)
RhythmUITests/              End-to-end UI tests
Config/                     Info.plists and entitlements
scripts/ci-ios.sh           Build + test on the iOS Simulator
```

### Where the logic lives

`RhythmCore` contains everything that must be correct and deterministic, with no Apple-UI dependencies:

| Type | Purpose |
| --- | --- |
| `ScheduleEngine` | Resolves a date to periods (overrides → weekday template), computes the live `ScheduleSnapshot` from an injected `now` |
| `ScheduleValidator` | Overlaps, ranges, empty titles, duplicate weekday assignments — with specific copy ("Lunch overlaps Biology by 5 minutes.") |
| `ReminderPlanner` / `ReminderReconciler` | Bounded, idempotent local-notification planning and reconciliation behind a `NotificationCenterClient` protocol |
| `WidgetSnapshot` | Compact, versioned payload for the widget extension, with staleness and version checks |
| `ExportImportCodec` | Versioned JSON export; import validation without touching existing data |
| `QuicklinkURLValidator` | Trims and validates destinations; never rewrites unknown schemes |
| `DeepLink` | `rhythm://` routes used by widgets, notifications, the Live Activity, and intents |

## Requirements

- macOS with **Xcode 26 or later** (the spec targets Xcode 27 / iOS 27 SDK; the project builds with any SDK ≥ iOS 26).
- Deployment target: **iOS 26.0**. The app uses Liquid Glass APIs (`glassEffect`, `.glass` button styles) introduced in iOS 26.
- No third-party dependencies.

## Build and run

1. Open `Rhythm.xcodeproj`.
2. Set your bundle identifier prefix once: select the **Rhythm** project → **Build Settings** → search `RHYTHM_BUNDLE_ID_PREFIX` and replace `com.example` with something you own (e.g. `com.yourname`). This sets the app (`<prefix>.rhythm`), widget (`<prefix>.rhythm.widgets`), and App Group (`group.<prefix>.rhythm`) identifiers consistently.
3. For both the **Rhythm** and **RhythmWidgetsExtension** targets → **Signing & Capabilities**: enable *Automatically manage signing* and choose your team (a Personal Team works).
4. Choose an iPhone simulator and press **⌘R**.

Step-by-step Xcode setup and iPhone install instructions, including Developer Mode and troubleshooting, are in [`docs/INSTALL.md`](docs/INSTALL.md).

### App Group note

Widgets read a small snapshot the app writes into an App Group container. If your team can't provision the App Group, remove the `com.apple.security.application-groups` entry from **both** `Config/Rhythm.entitlements` and `Config/RhythmWidgets.entitlements`. The app keeps working; widgets will show "Open Rhythm to update" instead of your schedule. The Live Activity does not need the App Group.

## Tests

```bash
# Core logic (works on macOS or Linux)
cd Packages/RhythmCore && swift test

# Everything, on the iOS Simulator
scripts/ci-ios.sh
```

In Xcode, **⌘U** on the Rhythm scheme runs the RhythmCore tests, the app unit tests, and the UI tests. UI tests launch with `-RhythmUITesting` (empty in-memory store, isolated preferences) and `-RhythmClock 2026-10-09T09:30:00` (a fixed local time that keeps ticking), so schedule states are deterministic.

CI (`.github/workflows/ci.yml`) runs the core tests on Linux and builds + tests the app on a macOS runner.

## Status

See §16 of the spec for what has been verified and what still needs a Mac or a physical iPhone (Live Activity on device, Siri/Shortcuts discovery, widget appearance).
