# Rhythm — Full Development Specification for Claude Code

> **Product:** Rhythm  
> **Platform:** iPhone first; native Apple-platform architecture  
> **Stack:** Swift, SwiftUI, SwiftData, WidgetKit, ActivityKit, App Intents, UserNotifications  
> **SDK target:** iOS 27 SDK using a compatible Xcode 27 release  
> **Product principle:** An elegant, local-first student productivity companion that makes the school day legible at a glance. It complements Apple’s existing apps; it does not recreate them.

---

## 0. Instructions for Claude Code

Build Rhythm as a production-minded native iOS app, not a web app wrapped in a shell. Work in small, compiling increments. Before writing code, inspect the repository, identify its existing project structure, and report the current state. Preserve working code unless a change is required.

### Required engineering behaviour

1. Use **SwiftUI-first**, native Apple frameworks, and system components wherever practical. UIKit may be used through small representable wrappers only when SwiftUI does not provide the needed system capability.
2. Use the latest stable **Xcode 27** available in the development environment and the **iOS 27 SDK**. Do not invent APIs. Verify framework availability and signatures against the SDK actually installed.
3. Make local functionality work without an account, server, network connection, or AI service.
4. Compile and run tests after each meaningful phase. Fix compiler errors and warnings introduced by the implementation before moving on.
5. Keep business logic out of SwiftUI views. Create testable models, services, and a deterministic schedule engine.
6. Do not leave primary buttons as placeholders, use fake data in production screens, or label a feature complete if it only has a mock UI.
7. Add useful Swift documentation comments to non-obvious public types and algorithms. Name types and methods clearly; avoid giant view files and giant view bodies.
8. Use Swift concurrency safely. Prefer Swift 6-compatible code, isolate UI state to `@MainActor`, and resolve strict-concurrency warnings rather than suppressing them indiscriminately.
9. Do not add third-party dependencies unless a concrete requirement cannot be met with Apple frameworks. No analytics SDK, advertising SDK, AI API, or telemetry by default.
10. Maintain this file as the source of truth. If a technical constraint requires a deviation, explain it and update this spec rather than silently changing the product.

### Definition of done

The project opens and builds in Xcode; a user can create a timetable; Rhythm correctly determines the current/upcoming period; countdowns remain correct after backgrounding and relaunch; reminders are permission-aware; Quicklinks open supported destinations; Shortcuts integration uses public Apple APIs; widgets and Live Activities fail gracefully when unavailable or disabled; accessibility and light/dark appearances work; and automated tests cover schedule calculations and important failure cases.

---

## 1. Product vision

Rhythm is a calm, polished view of a student’s day. A student sets up their recurring school schedule once—for example, six classes and lunch—and Rhythm automatically identifies the current period, shows how much time remains, and previews what comes next. It should reduce the friction of repeatedly checking the clock, schedule, reminders, or favorite links.

It should feel like something Apple could plausibly ship: focused, fast, private, accessible, restrained, and deeply integrated with iOS. **The schedule is the core product.** Every secondary feature must make the day easier to navigate without turning Rhythm into a cluttered suite of duplicate apps.

### Product pillars

- **At-a-glance awareness:** current period, time remaining, end time, and next period are instantly understandable.
- **Set up once:** recurring days and schedules work automatically, with exceptions for assemblies, late starts, minimum days, holidays, and one-off changes.
- **System integration:** widgets, Live Activities, notifications, App Intents, and native sharing where useful.
- **Useful handoffs:** Quicklinks open the relevant existing app, website, or supported Shortcut rather than copying its functionality.
- **Local-first privacy:** core data stays on device. No account is required.
- **Quiet interface:** no feed, social layer, AI assistant, streaks, points, ads, or unnecessary gamification.

### Primary audience

Students who follow a recurring daily schedule and want an unobtrusive way to know what period they are in, what is next, and what they need to remember.

### Explicit exclusions

Do **not** build:

- A Notes clone, note editor, journaling system, or embedded “Notes” section.
- A replacement for Apple Calendar, Reminders, Clock, Focus, Shortcuts, Safari, or school learning-management apps.
- AI features, chatbot, AI-generated schedules, predictive recommendations, or cloud AI calls.
- Social profiles, messaging, classroom management, grades/gradebooks, homework LMS, ads, subscriptions, or user tracking.
- A custom browser, music player, calculator, file manager, or general-purpose task manager.
- A background loop that tries to keep a one-second timer running while the app is suspended.

---

## 2. Release scope

### MVP — must ship

1. First-run onboarding and empty states.
2. Recurring schedule setup with multiple schedule templates and weekday assignments.
3. Automatic live schedule resolution: current period, time remaining, next period, free time, and no-school state.
4. Today screen with clear countdown and day timeline.
5. Schedule editor with validation and date-specific overrides.
6. Schedule-linked special reminders using local notifications.
7. Quicklinks for websites, supported app links, and optional Shortcuts URL launch links.
8. Rhythm App Intents / App Shortcuts for a small, useful set of native actions.
9. Home Screen widgets and a Live Activity for the current period, subject to system support and user permission/settings.
10. Settings for notifications, Live Activity behaviour, appearance/accent, and data management.
11. Accessibility, dark mode, Dynamic Type, and unit/UI tests.

### Strong follow-up after MVP stability

- Import/export timetable as a versioned JSON file.
- Optional Calendar read integration, clearly separated from Rhythm’s own bell schedule.
- iPad-adaptive layout and richer widget sizes.
- Optional Focus-filter support if it offers a clear, supported benefit without replacing Focus.
- More advanced rotating-day patterns (such as A/B or a multi-day cycle), only after ordinary weekly schedules are reliable.

### Do not add without explicit approval

Cloud accounts or sync, shared schedules, school directory integrations, third-party analytics, AI, or a large plugin system.

---

## 3. Core user journeys

### Journey A — first launch

1. Show a short introduction: “Your day, in rhythm.” Explain that Rhythm tracks a schedule and can surface it on the Lock Screen and Home Screen.
2. Let the user choose **Set up my schedule** or **Explore a sample**. Sample data must be clearly labelled and removable.
3. Ask how many recurring schedule types they need only if it helps setup; do not force a long onboarding questionnaire.
4. Guide them to create a template and add periods: title, category, start, end, applicable weekdays through template assignment, and optional reminder.
5. Preview the day in order and validate conflicts before saving.
6. Ask for notification permission contextually when enabling a reminder, not as an unexplained first-launch permission wall.
7. Explain Live Activities only when the user enables them or first uses the feature. Respect denied permissions and system settings.

### Journey B — daily use

1. Open Rhythm and land on **Today**.
2. Show the current class/lunch and accurate remaining time. If no period is active, show the next period and how long until it begins; do not fabricate a “class” during a gap.
3. Show the next period, a compact timeline for today, and any relevant special reminder.
4. The user taps a period to view its details or quickly edit a schedule exception.
5. A widget or Live Activity provides the most useful status without requiring the app to stay open.

### Journey C — schedule changes

1. User opens Schedule and selects a date/template.
2. User edits the template or chooses **Change this date only**.
3. Validate start/end ordering and overlaps immediately.
4. On save, persist the change, recompute current/next period, reconcile scheduled notifications, refresh widget data, and update or end a Live Activity if relevant.

### Journey D — Quicklinks and Shortcuts

1. User adds a title, optional icon, and destination.
2. Destination types: web URL, universal/app URL, or Shortcut launch URL.
3. Show a sensible warning/confirmation for malformed URLs or unsupported types.
4. On tap, open via public system URL-opening mechanisms. If iOS cannot open the destination, show an actionable error.
5. Rhythm’s own App Intents must appear in Shortcuts with meaningful names, parameters, and descriptions.

---

## 4. Information architecture and screens

Use a compact iPhone-first tab structure. Recommended tabs: **Today**, **Schedule**, **Quicklinks**. Settings should be reached through a standard toolbar button, not become a fourth top-level destination unless usability testing proves it necessary.

### 4.1 Today

Top area:
- Current date, with a simple date picker/date navigation affordance for reviewing another day.
- Active schedule/template label if more than one exists.
- Settings toolbar button.

Main live-event module:
- State: **In Progress**, **Up Next**, **Free Time**, **No School**, or **Schedule Needed**.
- Period title and type (Class, Lunch, Break, Passing, Other).
- Large readable remaining-time value; show an end time as supporting information.
- A restrained progress indicator showing elapsed/remaining progress.
- Start/end labels where helpful.
- The next period below or beside the main module.

Lower content:
- A scrollable ordered timeline for the day, with past/current/upcoming state clearly distinguished.
- A compact special-reminder area only when a relevant reminder exists. Do not reserve a large empty card when there is nothing to show.
- A small Quicklinks section showing favourites, not a feed of everything.

Behaviour:
- The primary timer updates visibly while Today is on screen.
- Backgrounding must not break the timer. Recalculate from absolute dates on foreground; do not accumulate seconds by counting ticks.
- If the current time is in a gap, display “Free time” and the next scheduled period/countdown.
- If the user has no schedule for today, show a clear empty state with actions to assign/create a schedule.
- Time-sensitive progress must remain intelligible with VoiceOver and not rely on colour alone.

### 4.2 Schedule

Views:
- Today/day timeline with date navigation.
- Schedule template picker/list.
- Weekly assignment view mapping templates to weekdays.
- Template editor with ordered periods.
- Date exception editor for special day schedules, no school, late start, early release, and one-off period changes.

Period editor fields:
- Title (required).
- Type/category (Class, Lunch, Break, Passing, Other).
- Start and end time (required, same local day for MVP).
- Optional short label/teacher/room (only if it stays lightweight; do not turn into a gradebook or student information system).
- Optional display colour/icon selected from accessible, system-friendly choices.
- Optional reminder rules.
- Enabled/disabled state if required for template editing.

Schedule rules:
- A template is a full ordered day schedule. Multiple weekdays may use the same template.
- MVP supports a normal weekly pattern and date-specific overrides. Rotating A/B cycles can come later.
- Periods cannot overlap inside one template. Gaps are allowed. A period must end after it starts.
- The editor should provide useful conflict copy such as “Biology overlaps Lunch by 5 minutes,” not only a generic error.
- Sorting is chronological after a time edit; avoid silently changing the user’s intended period order while they are entering times.
- Provide a safe delete/undo affordance for destructive schedule edits.

### 4.3 Quicklinks

Purpose: a launchpad for existing tools, not a replacement for them.

Supported types:
- Website URL (`https`).
- Universal link or app URL scheme entered by the user.
- Optional Shortcut launch URL, such as a `shortcuts://` run-shortcut URL, with clear explanation that the Shortcuts app/OS may require confirmation and behaviour depends on iOS.

Each item may have:
- Title, URL, optional note/description, icon/SF Symbol choice, favourite state, and sort order.
- Category grouping such as School, Study, Utility, or Personal; keep categories optional.
- Edit, reorder, duplicate, and delete actions.

Safety and reliability:
- Trim whitespace and validate the URL.
- Do not silently rewrite unknown URL schemes.
- Use `canOpenURL`/public allow-list configuration only when needed and appropriate; do not assume private app schemes exist.
- If a destination fails to open, display a helpful error and leave the link editable.
- Do not scrape other apps or promise that a given app URL will remain supported.

### 4.4 Settings

Sections:
- **Appearance:** System / Light / Dark, accent choice, reduced decorative motion if a Rhythm-specific switch is useful. Default appearance follows the system.
- **Live Activity:** enabled/disabled, with a brief explanation that availability and display are controlled by iOS.
- **Notifications:** notification status, reminder preferences, and a route to iOS Settings if permission was denied.
- **Schedule:** default schedule, week-start preference if needed, time format follows system locale by default.
- **Data:** export JSON, import JSON with validation/preview, reset sample schedule, delete all local Rhythm data.
- **About:** app version, privacy statement, open-source notices if applicable.

Do not create a large preferences dashboard. Use native Settings-style rows and standard navigation.

---

## 5. Schedule engine — correctness is the top priority

Implement the engine as a pure, independently testable service. Views must not implement schedule calculations.

### Inputs

- An injectable `now: Date`.
- User calendar/time zone and locale.
- Weekly weekday-to-template assignments.
- Selected template periods.
- Date-specific overrides (custom schedule or no-school day).
- Optional disabled periods.

### Output model

A value such as `ScheduleSnapshot` that contains:
- `dayState`: schedule-needed, no-school, in-progress, free-time, or upcoming.
- `activePeriod`, if any.
- `nextPeriod`, if any.
- `previousPeriod`, if useful for timeline presentation.
- Absolute `startDate` and `endDate` for relevant periods.
- Remaining duration and progress derived from the current instant, never stored as a ticking counter.
- The relevant schedule/template and override identifiers for deep links and edits.

### Resolution algorithm

1. Resolve the local calendar date for `now`.
2. Check for a date-specific override. A no-school override takes priority. A custom-day override replaces the ordinary template for that date.
3. Otherwise resolve the template assigned to the current weekday.
4. Build absolute `Date` values for each period’s local start/end wall times using `Calendar`; do not assume every day has exactly 86,400 seconds.
5. Sort periods by start time and validate them. Invalid persisted data must not crash the app; report a recoverable schedule issue and skip invalid records.
6. If `start <= now < end`, the period is active. Use half-open intervals so one period ending at 10:00 and the next starting at 10:00 do not overlap at the boundary.
7. Otherwise, if the next period starts after `now`, state is upcoming when there is no gap classification, or free-time when the previous period has ended and next has not started. Provide the next period’s start countdown.
8. If no future period remains, show the finished-day/no-upcoming-period state.
9. On every recomputation, derive `remaining = max(0, endDate.timeIntervalSince(now))` and `progress = clamp((now - start)/(end - start), 0...1)`.

### Clock and lifecycle handling

- Use `TimelineView` or a narrowly scoped timer mechanism to update the visible countdown while the screen is active. Do not publish a full app-wide state update every second.
- Use absolute start/end dates and recalculate on app activation. Do not increment a stored “seconds remaining” property.
- Recompute on foreground, significant time change, time-zone change, calendar day change, schedule edits, and date-override edits.
- Ensure timers and publishers are cancelled/paused when their screen is not visible.
- Treat daylight-saving changes and time-zone changes as test cases, not edge cases to ignore.
- In background, rely on notifications, WidgetKit timeline refreshes, and ActivityKit-supported date/countdown rendering; never rely on the process remaining alive.

### Date/time policy

MVP periods occur within one local day and do not span midnight. Use the user’s current system calendar and time zone. Store recurring clock times as minutes after local midnight (or a well-defined hour/minute value) and generate real `Date` values at resolution time. Store actual one-off dates as absolute dates. Document the distinction in code.

---

## 6. Data model and persistence

Use **SwiftData** for the main app’s local database unless inspection of the installed SDK reveals a material limitation. Put models in a dedicated `Models` group and migrations in a clearly isolated layer. Do not put SwiftData models directly in widget code.

Suggested conceptual models (adapt names to idiomatic Swift):

- `ScheduleTemplate`: stable ID, name, creation/update dates, periods, and active/default metadata.
- `WeekdayAssignment`: weekday identifier and template ID. Ensure only one effective template per weekday unless an explicitly modelled rule resolves the conflict.
- `SchedulePeriod`: stable ID, template ID, title, kind, start minute, end minute, optional metadata, icon/colour key, order, enabled state, reminder configuration.
- `ScheduleOverride`: local calendar date key, type (`noSchool` or `customSchedule`), optional custom periods/template reference, note/title, update date.
- `Quicklink`: stable ID, title, URL string, link type, SF Symbol, optional category, favourite flag, sort order.
- `ReminderRule`: stable ID, associated period or override, trigger offset/clock time, title/body, enabled state, recurrence/one-off semantics.
- `RhythmPreferences`: appearance preference, accent key, default template, Live Activity preference, onboarding/sample-data state, week-start preference if supported.

Data model requirements:
- Use stable identifiers and explicit relationships; never key objects by display title.
- Persist local data only for MVP. No login or server dependency.
- Add a schema/migration plan before changing persisted model shape.
- Provide sample timetable insertion only when the database is empty and the user explicitly selects it.
- Export a versioned JSON DTO format, not a direct dump of internal SwiftData objects. On import, decode into temporary DTOs, validate all relationships and times, show a preview, then commit atomically where practical.
- Deleting all user data must require confirmation and provide a clear result.

### Shared data for widgets and Live Activities

Use an App Group only if extension data sharing is necessary and correctly configured. Keep the extension payload small and independent from SwiftData internals. Have the main app write a compact, versioned JSON snapshot containing only what the widget/Live Activity needs: current/next period title, kind, relevant start/end `Date`s, snapshot generation date, and display-safe accent/category keys. Validate snapshot version and staleness in the extension. If the snapshot is missing or invalid, render an empty/refresh state rather than crashing.

Do not put private or unnecessary data into the extension snapshot.

---

## 7. Live Activity, widgets, notifications, Shortcuts

### 7.1 Live Activity (ActivityKit + WidgetKit extension)

Goal: the student can see the current class/lunch and time remaining on the Lock Screen and Dynamic Island where supported.

Display states:
- **In period:** period title, category, end time/countdown.
- **Between periods:** “Free time” plus next period and start time/countdown when space permits.
- **No current period / no school:** use a compact, useful state or end the activity when continuing it would be confusing.

Implementation requirements:
- Create a Widget Extension target and implement an `ActivityAttributes` type with compact static attributes and a small Codable content state.
- Use ActivityKit to request, update, and end the activity according to current state and user setting.
- Use the system’s date/countdown rendering for time-to-end when supported instead of pushing a fresh update every second.
- Keep the combined activity content payload within Apple’s documented size limit (currently 4 KB).
- Handle disabled Live Activities, authorization restrictions, activity limits, app termination, and schedule edits.
- Do not assume an Activity will stay active forever. End stale activities and reconcile state on app foreground / schedule changes.
- The Live Activity must be legible in compact, minimal, and expanded Dynamic Island layouts plus Lock Screen presentation.
- Keep interactivity minimal and relevant; tapping the activity should deep-link to the matching period or Today view.

### 7.2 Widgets (WidgetKit)

Build at least:
- **Small widget:** current period or next period, title, remaining/starts-in timer, and a tiny progress element only if legible.
- **Medium widget:** current period, next period, and a simple day-at-a-glance timeline/summary.

Requirements:
- Design for stale snapshots and delayed timeline refreshes. WidgetKit is system scheduled; do not promise real-time per-second refreshes for arbitrary custom drawing.
- Prefer system-rendered countdown text when possible.
- Refresh snapshots and request appropriate timeline reloads when the schedule changes. Avoid aggressive reload loops.
- Add widget deep links to Today, schedule date, or a specific period as supported.
- Test light and dark appearances, text sizes where available, and small screen widths.

### 7.3 Special reminders (UserNotifications)

A period can optionally have reminder rules, for example:
- “Bring gym clothes” 15 minutes before PE.
- “Turn in worksheet” at a chosen time on a particular date.
- “Leave for class” before a selected period.

MVP supports schedule-linked reminders only; do not build a full general-purpose Reminders clone.

Requirements:
- Ask for notification authorization contextually, after the user turns on reminders or chooses to enable them.
- Check current notification settings before scheduling. If permission is denied, preserve the reminder rule and show the next step to enable notifications in iOS Settings.
- Use stable identifiers per rule/occurrence to update or cancel correctly.
- Reconcile pending notifications after timetable changes, template reassignment, date override edits, timezone/calendar changes, and app launch.
- Keep scheduled requests bounded: schedule only a sensible rolling horizon for individual date occurrences, or use repeating calendar triggers where the recurrence is unambiguous. Avoid scheduling unlimited duplicates.
- Do not notify for periods that were deleted, disabled, or covered by a no-school override.
- Avoid duplicate notifications when the app opens repeatedly.
- User settings may independently enable/disable the reminder feature and individual reminder rules.

### 7.4 Shortcuts and App Intents

Implement Rhythm-owned actions through the public App Intents framework. Initial candidates:
- **Show Today in Rhythm** — opens Today.
- **Get Current Period** — returns the current period name/state where supported by the intent’s return type.
- **Get Next Period** — returns the next period name and start time.
- **Open a Quicklink** — accepts a user-owned Quicklink identifier or a safely exposed supported parameter, then opens it through a supported URL action.
- **Refresh Rhythm Schedule** — recomputes local schedule state and extension snapshot; no network operation.

Create a small set of meaningful `AppShortcut` phrases/titles. Keep action names stable and user-readable. Test these actions in the Shortcuts app and Siri/system discovery on a real device where available.

Important platform boundary:
- Rhythm **can expose its own actions** to the Shortcuts app using App Intents.
- Rhythm may store a user-provided Shortcut launch URL as a Quicklink and ask iOS to open it.
- Do not use private APIs or claim Rhythm can inspect, list, or silently execute arbitrary user-created Shortcuts. iOS behaviour/confirmation depends on the target OS and the Shortcut configuration.
- Do not add Apple Intelligence or an AI assistant; App Intents are for system integration, not a reason to add AI features.

---

## 8. Liquid Glass and Apple design language — visual specification

Treat Apple’s current Human Interface Guidelines and the installed iOS 27 SDK as the authority. Adopt native platform behaviour instead of creating a fake glass theme over every view. Apple’s guidance distinguishes the Liquid Glass functional layer (navigation and controls) from the content layer; use that distinction throughout Rhythm.

### 8.1 Overall character

- Calm, tactile, spacious, precise, and quietly energetic.
- Clean typography and hierarchy before decoration.
- The schedule itself is the visual content; glass should never compete with it.
- Native iOS navigation bars, sheets, tab bar, menus, pickers, toggles, and standard buttons should be preferred so they inherit system styling and accessibility behaviour.
- No oversized marketing gradients, glass cards stacked over glass cards, neon glows, hard skeuomorphic bevels, or always-on particle effects.

### 8.2 Material rules

**Use Liquid Glass sparingly for the functional layer:**
- System tab bar and navigation/toolbars.
- Floating controls or a prominent add/action control where it floats over content.
- Small contextual controls over a timeline only if they benefit from separation.
- Menus and presentation chrome where native system components provide the effect.

**Use standard content surfaces for information:**
- Period rows, timeline entries, labels, reminder content, and schedule details should sit on clean system backgrounds or appropriate standard materials.
- Do not wrap every class in a glass capsule.
- Avoid glass behind long blocks of text; it reduces legibility and adds unnecessary layers.
- Use `.regular`-style glass for normal navigation/control surfaces when building custom controls; use a clearer variant only where the background is visually rich and text contrast remains strong.
- Prefer standard SwiftUI controls whose appearance adapts to system material settings. Custom glass should be an exception and remain visually restrained.

### 8.3 Colour

- Default to adaptive system colours and semantic foreground/background roles.
- Use one user-selectable accent colour for selected controls, progress, and the current-period emphasis; do not use accent colour for every icon or label.
- Offer a restrained accessible palette (for example, blue, indigo, teal, coral, purple, and system default) only if each choice remains legible in light and dark mode.
- Period category colours should be muted and consistent. Always pair colour with text/icon/shape; colour alone must not encode class versus lunch.
- Test translucent controls behind both light and dark, busy and plain content. Never hard-code white text over a translucent background that can change luminance.
- Avoid large saturated gradients behind the schedule. A subtle adaptive background tint is acceptable only if it improves hierarchy without lowering contrast.

### 8.4 Typography

- Use system SF typography and semantic text styles: `.largeTitle`, `.title`, `.title2`, `.headline`, `.body`, `.subheadline`, `.footnote`, `.caption` as appropriate.
- Current period title: strong headline/title-level hierarchy, generally one line where possible and gracefully wraps if not.
- Remaining-time value: large, high-contrast, tabular numerals (`monospacedDigit()`), no novelty typeface.
- Period titles must remain readable at accessibility Dynamic Type sizes. Avoid fixed heights that cut off text.
- Use secondary text for start/end labels; do not create multiple competing headline sizes.
- Avoid using SF Symbols as decorative wallpaper; every symbol should communicate a function or category.

### 8.5 Shape, spacing, layout

Use a small, consistent spacing scale: **4, 8, 12, 16, 20, 24, 32 points**. Use it consistently rather than arbitrary values throughout the codebase.

Suggested shape scale:
- Small controls/tags: 8–12 pt corner radius where custom shape is needed.
- Content grouping: 14–18 pt.
- Main live-event module: 20–28 pt depending on geometry.
- Capsules only for semantic tags, selected filter controls, and system glass controls—not as the shape for every piece of content.

Touch targets should meet Apple accessibility guidance (aim for at least 44 × 44 pt). Keep the Today screen focused: one primary status, one clear next event, then the schedule timeline. Use layout margins consistently and respect safe areas. Avoid too many inset cards, nested rounded rectangles, or redundant dividers.

### 8.6 Motion and transitions

- Prefer native navigation/sheet transitions and restrained SwiftUI animation.
- Animate meaningful state changes: period transition, progress state change, selection, add/remove, and schedule reassignment.
- Use short, subtle spring/ease animations; motion must never delay the information becoming readable.
- Avoid continuous decorative motion or animations that imply precision when data is stale.
- Respect Reduce Motion and other accessibility settings. Provide a non-animated equivalent.
- The countdown number should update without a dramatic scale bounce every second. Period transitions may use a single subtle crossfade or position transition.

### 8.7 Navigation, sheets, and controls

- Use `NavigationStack` with clear, contextual titles.
- Use a native tab bar for Today, Schedule, Quicklinks.
- Use sheets for focused creation/editing tasks. Use a confirmation dialog for destructive or small-choice actions, not a custom glass popover for every control.
- Prefer system `Form`, `List`, `DatePicker`, `Picker`, `Toggle`, `Menu`, and toolbar buttons where appropriate. Style should complement the content, not fight default iOS behaviour.
- Primary actions should be unmistakable and not duplicated by several competing floating buttons.
- Avoid custom-drawn controls unless the native control cannot express the required interaction accessibly.

### 8.8 Light, dark, accessibility, and contrast

- Support System, Light, and Dark appearance. System is the default.
- Do not assume glass is always white or bright; material adapts to appearance and system settings.
- Support Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast, Differentiate Without Color, and button shapes where applicable.
- Set meaningful accessibility labels/values for countdown and progress. Example: “Biology, 12 minutes remaining, ends at 10:42 AM.”
- Hide purely decorative symbols from VoiceOver.
- Ensure context menus and drag/reorder controls have non-gesture alternatives.
- Test with larger accessibility sizes and long names such as “Advanced Placement Environmental Science.”

### 8.9 Suggested reusable design tokens

Create a central design-token file/namespace for spacing, semantic colour keys, and animation durations. Use system semantic colours where possible and avoid locking adaptive system colours to static RGB values.

Example token names (values are starting points, not absolute rules):

- `RhythmSpacing.xs = 4`, `sm = 8`, `md = 12`, `lg = 16`, `xl = 24`, `xxl = 32`.
- `RhythmRadius.row = 12`, `module = 24`, `capsule = .infinity`.
- `RhythmMotion.quick = 0.16s`, `standard = 0.25s`.
- `RhythmColor.currentPeriod`, `nextPeriod`, `lunch`, `break`, `freeTime` map to semantic/adaptive colours and symbols.

Do not hard-code these example values into many files; centralize them.

---

## 9. Recommended technical architecture

Keep modules small and understandable. For an MVP, separate folders/groups in a single Xcode project are sufficient; do not introduce a complex multi-package architecture without a real need.

Suggested structure:

```text
Rhythm/
  App/
    RhythmApp.swift
    AppContainer.swift
    RootTabView.swift
    DeepLinkRouter.swift
  Models/
    ScheduleTemplate.swift
    SchedulePeriod.swift
    ScheduleOverride.swift
    Quicklink.swift
    ReminderRule.swift
    RhythmPreferences.swift
  Scheduling/
    ScheduleEngine.swift
    ScheduleSnapshot.swift
    ScheduleValidator.swift
    ScheduleRepository.swift
    Clock.swift
  Services/
    NotificationScheduler.swift
    LiveActivityCoordinator.swift
    WidgetSnapshotStore.swift
    QuicklinkOpener.swift
    ExportImportService.swift
  Intents/
    ShowTodayIntent.swift
    GetCurrentPeriodIntent.swift
    GetNextPeriodIntent.swift
    OpenQuicklinkIntent.swift
    RhythmAppShortcuts.swift
  DesignSystem/
    RhythmSpacing.swift
    RhythmColours.swift
    RhythmShapes.swift
    RhythmMotion.swift
    Components/
  Features/
    Onboarding/
    Today/
    Schedule/
    Quicklinks/
    Settings/
  Resources/
  RhythmWidgets/   # Widget/Live Activity extension target
  RhythmTests/
  RhythmUITests/
```

Suggested boundaries:
- **Models:** persisted data and simple value types only.
- **ScheduleEngine:** deterministic date/time resolution; no SwiftUI, notifications, database writes, or global clock calls.
- **Repositories:** load/save models and validate changes.
- **Services:** Apple framework integration (notifications, ActivityKit, widget snapshots, URL opening, file import/export).
- **View models/state holders:** coordinate feature-level UI state; use `@Observable` or the appropriate SwiftUI state mechanism supported by the SDK.
- **Views:** render state and send user actions to the relevant service/repository.

Prefer dependency injection for the clock, repository, and notification coordinator so tests can use a fixed instant and in-memory data. Do not create a singleton for every service; use one explicit app container where it keeps setup understandable.

---

## 10. Reliability, edge cases, and failure behaviour

The implementation must handle these cases gracefully:

- No schedule has been created.
- Today has no assigned template.
- The date is marked as no school.
- All periods for the day have ended.
- There is a gap between periods.
- Periods touch exactly at a boundary.
- A period was deleted while a reminder or Live Activity refers to it.
- User changes start/end times or changes which template applies to a weekday.
- User changes time zone, calendar day, or system clock while the app is open.
- Daylight-saving transition changes local-time interpretation.
- Notification permission is denied or later revoked.
- Live Activities are disabled or unavailable for the current state.
- Widget snapshot is missing, corrupt, from a newer version, or stale.
- Quicklink URL is malformed, has an unsupported scheme, or cannot be opened.
- JSON import contains malformed data, overlapping periods, duplicate IDs, unknown schema version, or invalid relationships.
- User deletes all data during an active day.
- App launches with a partially migrated database or invalid old data.

For every feature, define a useful empty/error state. Do not crash or leave the UI indefinitely loading because a permission is denied or a system extension cannot be started.

---

## 11. Testing strategy and acceptance criteria

### Unit tests — mandatory

**ScheduleEngine** tests must include:
- Active class mid-period.
- Active lunch period.
- Exact start boundary is active.
- Exact end boundary is no longer active.
- Gap between two periods.
- Before first period.
- After final period.
- No-school override.
- Custom date override takes priority over weekday template.
- Missing weekday assignment.
- Invalid and overlapping period data.
- Template with six classes plus lunch.
- Time-zone/DST-sensitive date construction where practical.
- Remaining time and progress are correct from an injected `now`.

**ScheduleValidator** tests:
- Start equals end.
- End before start.
- Overlapping periods.
- Duplicate weekday assignments.
- Empty period title.
- Valid gaps and adjacent periods.

**Quicklinks / import-export** tests:
- Valid HTTPS URL.
- Empty/malformed URL.
- Unknown schema version.
- Duplicate ID.
- Invalid period range.
- Import validation does not mutate existing data before confirmation.

**NotificationScheduler** tests with an abstraction/fake:
- Duplicate scheduling is idempotent.
- Changed reminder updates/cancels old request.
- Deleted period cancels related requests.
- No-school override suppresses events.
- Denied permission preserves user settings but does not claim that a notification was scheduled.

### UI tests — mandatory

- First-run empty state and create schedule flow.
- Create a six-class timetable with lunch and verify the Today screen.
- Edit a period and ensure Today updates.
- Create a date exception.
- Add, edit, reorder, and delete a Quicklink.
- Test denied notification permission presentation without a crash.
- Verify Dynamic Type / basic accessibility labels for the Today countdown.

### Manual device testing

- At least one physical iPhone running iOS 27.
- Light and dark mode.
- With/without Dynamic Island if supported by available hardware/simulator testing.
- Lock Screen Live Activity, compact/expanded Dynamic Island, small/medium widgets.
- Force-quit/reopen around a period boundary.
- Edit schedule while a Live Activity is active.
- Change system time zone and re-open app.
- Test with Reduce Motion, Increase Contrast, and larger accessibility text.

### Acceptance criteria for MVP

1. The app’s current/upcoming period matches the configured schedule at every tested boundary.
2. Remaining time is derived from absolute date values and does not drift after backgrounding.
3. The app never shows overlapping periods as simultaneously active.
4. Schedule conflicts are identified before saving.
5. Notification permissions are requested contextually, and denied permission does not break the app.
6. The user can manage Quicklinks without granting unrelated permissions.
7. Rhythm’s App Intents work through public APIs and have meaningful metadata.
8. Widgets and Live Activities degrade gracefully if system support/settings prevent them from appearing.
9. Core schedule functionality works offline.
10. No AI, analytics, ads, account requirement, Notes clone, or custom browser has slipped into scope.

---

## 12. Development phases for Claude Code

### Phase 0 — inspect and scaffold

- Inspect repository state, Xcode project, deployment target, signing setup, and current SDK.
- Confirm the installed Xcode includes the iOS 27 SDK. Record the chosen version in project notes.
- Create the app and test targets or adapt existing targets without deleting working work.
- Configure bundle ID placeholder, Swift version/concurrency settings, assets, and app entry point.
- Add the core folder structure and compile an empty SwiftUI shell.

**Gate:** clean build and app launches in simulator.

### Phase 1 — models and schedule engine

- Implement models, repository protocol, validation rules, injected clock, snapshot, and schedule resolution.
- Add sample-data generation for tests only plus an explicitly chosen onboarding sample timetable.
- Write unit tests for all schedule boundaries and overrides.

**Gate:** all engine tests pass before building the full UI.

### Phase 2 — Today UI and design system

- Build root tab/navigation structure, Today state variants, live countdown, next-period module, and daily timeline.
- Implement design tokens and adaptive light/dark styling.
- Use native system navigation/control styling and keep glass confined to the control layer.
- Add Dynamic Type, accessibility labels, empty states, and Reduce Motion handling.

**Gate:** Today screen works with a fixed test clock and real persisted schedule data.

### Phase 3 — schedule setup and editing

- Build onboarding, template creation, period editor, weekday assignment, conflict validation, and date-specific overrides.
- Add safe delete/undo behaviour where appropriate.
- Recompute Today state after every successful edit.

**Gate:** user can create a six-period school day with lunch, assign weekdays, and override one date without editing code.

### Phase 4 — reminders

- Implement notification permission flow, reminder editor, local notification scheduling, stable request identifiers, and reconciliation.
- Test permission denied/revoked, edits, deletions, and no-school exceptions.

**Gate:** the app accurately reports notification state and does not schedule duplicates.

### Phase 5 — Quicklinks and App Intents

- Build Quicklinks CRUD, validation, favourites, reorder, and URL opening.
- Implement Rhythm App Intents and App Shortcuts; add deep-link routing into the correct view.
- Test intents using the Shortcuts app on a device where possible.

**Gate:** each action either succeeds or reports a useful recoverable error.

### Phase 6 — widgets and Live Activity

- Add Widget Extension target, App Group only if needed, compact snapshot DTO, small/medium widgets, ActivityAttributes, and Dynamic Island/Lock Screen views.
- Add start/update/end reconciliation and deep links.
- Keep activity payload small; use system countdown rendering instead of frequent background updates.

**Gate:** test with a physical device and document any OS-controlled limitation; app remains fully usable when the Activity is unavailable.

### Phase 7 — settings, import/export, and polish

- Finish appearance, permissions, data actions, export/import validation, and About screen.
- Polish transitions, VoiceOver, accessibility contrast, stale snapshot handling, and error states.

**Gate:** no dead controls; all visible settings are functional.

### Phase 8 — quality pass and device install guide

- Run unit tests, UI tests, static analysis/build warnings review, and full simulator/device pass.
- Fix all crashes and high-priority accessibility issues.
- Complete the manual Xcode-to-iPhone instructions below and verify with a personal Apple Account if available.
- Add screenshots to project notes only if useful; do not fabricate evidence of device testing.

**Gate:** documented successful build, installation, and launch on a real iPhone.

---

## 13. How to import the project into Xcode and install Rhythm on an iPhone

These instructions assume a Mac, Xcode 27 or another installed release that supports the project’s iOS SDK, and an iPhone on a compatible iOS version. Apple’s exact UI wording may change between Xcode releases.

### A. Get the source code onto the Mac

**If the project is in GitHub:**

1. Install Xcode from the Mac App Store or Apple Developer downloads and open it once so required components can finish installing.
2. In Terminal, navigate to a folder for projects and clone the repository:

   ```bash
   cd ~/Developer
   git clone <REPOSITORY_URL> Rhythm
   cd Rhythm
   ```

3. If the repository contains `Rhythm.xcodeproj`, open that file. If it contains `Rhythm.xcworkspace` (for example, a project with workspace-level dependencies), open the workspace instead. Open the file that actually exists; do not create a new project on top of an existing project.
4. If Claude Code created only source files and no Xcode project, open Xcode and choose **File → New → Project → iOS → App**, name it `Rhythm`, select **SwiftUI** for the interface and **Swift** for the language, then add the generated source files and targets carefully. Prefer having Claude Code generate a complete `.xcodeproj`/project structure to avoid manual target misconfiguration.

### B. Select the target and check build settings

1. In Xcode’s Project navigator, click the blue project icon.
2. Select the **Rhythm** app target.
3. Under **General**, set a unique Bundle Identifier, such as `com.yourname.Rhythm` (replace it with a value you control; it must be unique for signing).
4. Verify the deployment target. If this build intentionally targets iOS 27 only, set iOS 27; if the project has a lower supported target, only use APIs available at that minimum OS and add availability guards. Do not set a target lower than the app’s actual API usage.
5. Under **Signing & Capabilities**, enable **Automatically manage signing** and choose your Apple Account team / **Personal Team**.
6. If the app uses an App Group for widget/Live Activity snapshot sharing, add the same valid App Group entitlement to the app and extension targets. Do not add an invented App Group identifier; it must be registered/available for the selected team and configured consistently.
7. Confirm the Widget Extension target exists if widgets or Live Activities are part of the build. App Group and Live Activity capabilities must be configured only when actually used.

### C. Build and run in the iOS Simulator first

1. In the Xcode toolbar, choose an iPhone simulator running iOS 27 (or a simulator runtime compatible with the project).
2. Select **Product → Build** (or press **⌘B**).
3. Fix any build errors shown in the Issue navigator. Do not ignore errors and do not “fix” them by deleting required app features.
4. Select **Product → Run** (or press **⌘R**).
5. Verify onboarding, create a sample timetable, inspect Today, edit a period, and confirm the countdown behaves as expected.

### D. Connect and prepare the real iPhone

1. Unlock the iPhone and connect it to the Mac using a data-capable USB cable, or pair it wirelessly through Xcode after the initial connection.
2. If prompted on the iPhone, tap **Trust** and enter the device passcode.
3. In Xcode, choose **Window → Devices and Simulators** (or the equivalent device management window in your Xcode version) and confirm the iPhone is listed and paired.
4. On the iPhone, enable **Developer Mode** if iOS prompts for it. The setting is typically under **Settings → Privacy & Security → Developer Mode**; follow the device restart/confirmation steps if requested.
5. The device’s iOS version must be supported by the installed Xcode. If the device is on a newer iOS build than Xcode supports, update Xcode; if it is on a prerelease version, use a matching supported Xcode release.

### E. Sign and install Rhythm on the iPhone

1. Return to the Rhythm project in Xcode.
2. Select the **Rhythm** app target → **Signing & Capabilities**.
3. Turn on **Automatically manage signing** and select your Personal Team/Apple Account team.
4. Fix any bundle identifier, provisioning profile, or entitlement issue that Xcode reports. App Group and other restricted capabilities can require additional account configuration.
5. In the Xcode toolbar’s run-destination menu, select the connected physical iPhone—not a simulator.
6. Select **Product → Run** (⌘R). Xcode builds, signs, installs, and launches the app on the iPhone.
7. If iOS asks for developer trust or confirmation, follow the on-device prompt. Wording varies by iOS release; if an app cannot launch, inspect the on-device security prompt and Xcode’s signing error rather than repeatedly reinstalling.
8. Open Rhythm and test the core schedule flow. Grant notifications only when testing the reminder feature. Enable Live Activities in iOS settings if the relevant option is presented and needed for testing.

A paid Apple Developer Program membership is **not normally required just to install and debug your own app on your personal iPhone through Xcode**. Paid membership may be necessary for distribution, some entitlements/capabilities, TestFlight/App Store workflows, or other advanced services. Follow the exact entitlement errors shown by Xcode.

### F. Reinstalling after code changes

1. Keep the iPhone connected and selected as the run destination.
2. Make changes in Claude Code or Xcode.
3. Build/run again with ⌘R. Xcode will usually replace the installed development build.
4. If the app fails to launch, read the first relevant error in Xcode’s Issue navigator and device console. Do not delete app data unless it is safe to lose the local schedule.

### G. Installing without launching from Xcode

For a personal development build, the simplest route is **Run from Xcode**. If you later need a build for testers, use TestFlight/App Store Connect or another Apple-supported distribution method appropriate to the account and signing configuration. Do not send someone an unsigned `.app` folder and expect it to install normally.

### H. Troubleshooting quick reference

- **No signing team:** sign into Xcode under Settings → Accounts and select your Personal Team.
- **Bundle ID unavailable:** change the Bundle Identifier to one unique to your team.
- **iPhone missing:** unlock it, reconnect, confirm Trust, check the cable, and open Devices and Simulators.
- **Developer Mode error:** enable Developer Mode on the iPhone and complete any restart confirmation.
- **iOS runtime/device unsupported:** install a compatible Xcode release and platform support.
- **App Group entitlement failure:** verify the identifier and entitlement on both app and extension targets; remove the entitlement only if the app no longer uses it.
- **Notifications do not arrive:** check iOS notification permission and Focus settings; verify the request was scheduled and its trigger time is in the future.
- **Live Activity missing:** check the app’s setting and iOS Live Activities setting, then confirm the ActivityKit request succeeded. A missing Activity must not prevent using Rhythm.
- **Changes appear stale in widgets:** verify snapshot writes, App Group configuration, and WidgetKit reload requests. Do not implement a rapid reload loop.

---

## 14. Apple documentation references

Use these current Apple references when implementing and verify any framework details against the SDK actually installed:

- [Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Human Interface Guidelines — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [ActivityKit](https://developer.apple.com/documentation/ActivityKit)
- [Live Activities collection](https://developer.apple.com/documentation/widgetkit/liveactivities-collection)
- [Displaying Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [App Intents](https://developer.apple.com/documentation/AppIntents)
- [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)
- [Scheduling local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Running an app on a simulated or physical device](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
- [Apple Developer Program enrollment FAQ](https://developer.apple.com/help/account/membership/program-enrollment/)

**Platform note:** Apple documentation and Xcode interfaces can change. Xcode 27 and the iOS 27 SDK are the intended development baseline; use the current installed stable release when possible and avoid relying on unverified beta-only API behaviour.

---

## 15. Final instruction to Claude Code

Start by inspecting the repository and reporting whether a complete Xcode project already exists. Then implement the phases in order, compiling and testing at every gate. Prioritize correct schedule calculations and a beautiful, accessible Today screen before secondary integrations. The result should feel native, restrained, and dependable: a live view of a student’s day—not a collection of unrelated productivity features.

---

## 16. Implementation notes and deviations

This section records how the MVP was implemented and where it intentionally differs from the text above. Keep it current.

### 16.1 Architecture

- **RhythmCore Swift package (deviation from §9's single-project layout).** All deterministic logic — `ScheduleEngine`, `ScheduleSnapshot`, `ScheduleValidator`, reminder planning and reconciliation, the widget snapshot format, export/import DTOs and validation, Quicklink URL validation, deep links, and countdown formatting — lives in a local package at `Packages/RhythmCore`. Reason: the widget extension needs the same types as the app, and the package depends only on Foundation, so its tests run with `swift test` on any machine (including Linux CI). The app and widget targets link it; the Xcode scheme runs its tests.
- **Shared/** holds the few files compiled into both the app and widget extension that need Apple UI frameworks: `RhythmActivityAttributes`, `SharedStorage` (App Group location), and `RhythmPalette` (accent and category colours).
- **AppModel** is the single composition root. Every edit goes through `AppModel.commit(_:)`, which saves, rebuilds the engine configuration, reconciles notifications, rewrites the widget snapshot (reloading timelines only when content changed), and reconciles the Live Activity.
- **Preferences** (`RhythmPreferences`) are stored in `UserDefaults`, not SwiftData: they are device-level, relationship-free, and excluded from export. The "default schedule" and "week-start" settings from §4.4 were not added: weekday assignment covers the first, and the system calendar's `firstWeekday` is used for the second, so neither would be a functional control.
- **Xcode project** uses folder-synchronized groups (Xcode 16+ format), so files added under `Rhythm/`, `Shared/`, `RhythmWidgets/`, `RhythmTests/`, and `RhythmUITests/` are picked up without editing the project file. Bundle IDs and the App Group derive from one build setting, `RHYTHM_BUNDLE_ID_PREFIX`.

### 16.2 Platform targets

- **Deployment target iOS 26.0**, built with any SDK ≥ iOS 26 (Xcode 26 or 27). No iOS 27-only API is used, so the project also builds with Xcode 26; when building with the iOS 27 SDK nothing changes. Liquid Glass is used through system chrome (tab bar, toolbars, sheets) plus three explicit control-layer uses: the floating Undo bar (`glassEffect`), the "Today" return button, and onboarding buttons (`.glass` / `.glassProminent`). Content surfaces use standard grouped backgrounds.
- **Swift language mode 5 with `SWIFT_STRICT_CONCURRENCY = complete`** for the app targets; the RhythmCore package builds in Swift 6 mode with no warnings. UI state is `@MainActor`. Moving the app targets to Swift 6 mode is a follow-up once the project has been compiled and the remaining concurrency diagnostics reviewed in Xcode.

### 16.3 Behaviour details

- **Day states.** `DayState` adds `dayComplete` (all periods ended) alongside the states in §5. `noSchool` covers a no-school override, an unassigned weekday, and an empty template; `DaySource` tells them apart for copy and actions.
- **Overlaps in stored data** are resolved by keeping the earlier period and skipping the later one, and the issue is shown on Today ("Some periods were skipped"). Two periods can never be active at once.
- **Date overrides.** A special schedule either reuses another template (late start, minimum day) or has its own one-off periods, initially copied from that day's regular schedule.
- **Reminders** are per-period: "N minutes before start, every time the period occurs" or "once at a date and time". Occurrences are generated only for periods that appear in the resolved day, so deletions, disabled periods, and no-school days suppress them automatically. A 14-day rolling horizon is capped at 60 pending requests (iOS allows 64). Request identifiers embed a content fingerprint, so reconciliation is idempotent and changed reminders replace old requests.
- **Live Activity.** Shown while a period is in progress, during free time between periods, and from one hour before the first period. Without a push server, content can only be updated while Rhythm runs (on launch, foreground, edits, and at each boundary while foregrounded). Each update sets `staleDate` to the next boundary; after it the Lock Screen shows "Open Rhythm" plus what's next instead of a finished timer. Live Activities are off until the user enables them in Settings, where they are explained the first time.
- **Widgets.** The app writes a ≤ 8 KB JSON snapshot covering three days; the widget builds timeline entries at each boundary and uses system-rendered `Text(timerInterval:)` countdowns. Missing, corrupt, newer-version, or out-of-range snapshots show "Open Rhythm to update".
- **Import** replaces all data after a preview and confirmation. If writing fails, the previous data (captured as an export first) is restored.
- **Testing hooks.** `-RhythmUITesting` (in-memory store, isolated preferences), `-RhythmClock yyyy-MM-ddTHH:mm:ss` (shifts "now" for deterministic UI tests), and `-RhythmNotificationsDenied` (simulates denied permission). They have no effect in normal launches.

### 16.4 Verification status

| Item | Status |
| --- | --- |
| RhythmCore: 75 unit tests (engine boundaries, overrides, DST/time zones, validator, reminders + reconciliation, widget snapshot, import/export, Quicklinks, deep links) | Passing (`swift test`, Swift 6.1) |
| App, widget extension, app unit tests, UI tests | Written; compiled and run only via Xcode/CI (`scripts/ci-ios.sh`). Not yet verified on a Mac in this development session. |
| Physical iPhone: Live Activity, Dynamic Island, widgets, Siri/Shortcuts discovery, Reduce Motion / Increase Contrast / large text pass | Not yet done — requires a device (Phase 8 gate). |
