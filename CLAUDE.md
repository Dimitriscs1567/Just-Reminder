# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Working agreements (set by the user — always follow)

- **Ask, don't assume.** If a requirement or behavior is unclear, ask the user
  (multiple choice with a recommended option first). Record every decision in
  [Product decisions](#product-decisions) so it is never re-asked.
- **Never commit or push.** Git is initialized, but the user makes all
  commits. Work in the steps listed under [Status](#status). When a step is
  done, stop and tell the user what changed and how it was verified, so they
  can commit; continue only when they say so.
- **Keep `README.md` and `CLAUDE.md` updated with every change.** README is
  for humans using the repo (features, setup, platform steps); CLAUDE.md holds
  rules, decisions, architecture and gotchas.

## Commands

```bash
flutter pub get
flutter analyze                 # must report "No issues found!"
flutter test                    # unit + widget tests
flutter build apk --debug       # verifies Gradle/Kotlin/manifest changes
flutter run -d emulator-5554    # run on the Android emulator
flutter emulators --launch Medium_Phone
```

The development machine is Windows: Android can be built, run and tested;
iOS code (Swift widget extension, AppDelegate) **cannot be compiled here**, so
write it carefully and document the Xcode steps in README.

## Tech stack and API gotchas

Versions resolved on 2026-11-04 (Flutter 3.47.8, Dart 3.13.7):

| Package | Version | Notes |
| --- | --- | --- |
| material_ui | 1.10 | **Import `package:material_ui/material_ui.dart`, never `package:flutter/material.dart`.** Flutter 3.47 moved Material out of the framework; go_router and dynamic_color already use `material_ui`, and mixing both gives two different `ThemeData`/`ColorScheme` types. |
| flutter_riverpod | 3.4 | No code generation. `AsyncValue.value` is nullable (`requireValue` for non-null). Family notifiers get the argument through the constructor: `NotifierProvider.family<N, S, A>(N.new)`. Avoid legacy `StateProvider`. |
| go_router | 18.1 | |
| sembast | 3.10 | `sembast_io.dart` in the app, `sembast_memory.dart` in tests. **Main isolate only** (see architecture). |
| flutter_local_notifications | 22.3 | All methods take named parameters: `initialize(settings:, onDidReceiveNotificationResponse:, onDidReceiveBackgroundNotificationResponse:)`, `zonedSchedule(id:, scheduledDate:, notificationDetails:, androidScheduleMode:, title:, body:, payload:)`, `cancel(id:, tag:)`. Android needs core library desugaring (enabled). iOS keeps at most 64 pending notifications. |
| timezone | 0.11 | Required by `zonedSchedule` (`TZDateTime`). |
| home_widget | 0.10 | Data: `saveWidgetData`/`getWidgetData` (Android prefs file `HomeWidgetPreferences`, iOS App Group `UserDefaults`). `scheduleWidgetUpdates(times)` re-renders Android widgets at given instants (needs `HomeWidgetScheduledUpdateReceiver` in the manifest). Android widget configuration via a `FlutterActivity` with its own Dart entrypoint + `initiallyLaunchedFromHomeWidgetConfigure()` / `finishHomeWidgetConfigure()`. Widget taps that run Dart: `registerInteractivityCallback` (top-level `@pragma('vm:entry-point')` function). |
| dynamic_color | 2.1 | `DynamicColorBuilder`, `ColorScheme.harmonized()`, `Color.harmonizeWith()`. |
| path_provider, intl | — | DB file location; date/time formatting. |

Android toolchain from the template: AGP 9.1, Kotlin 2.4, Gradle 9.3,
Java 17. iOS deployment target 15.0 (app); the widget extension will need
iOS 17.

Known build warning: Gradle reports that `home_widget` still applies the
Kotlin Gradle Plugin ("Future versions of Flutter will fail to build…"). It
builds fine today; re-check when upgrading Flutter or home_widget.

## Product decisions

Agreed with the user on 2026-11-04. These are the spec.

**Reminder fields**
- `name` (required) — shown in the app.
- `displayName` (required) — shown on the widget and as the notification title.
- `description` (optional) — app + notification text.

**Schedule — dates**
- *Once* on a date, or *Repeat*:
  - Daily every N days; Weekly every N weeks on selected weekdays; Monthly
    every N months on day D. (This covers the requested patterns: daily,
    selected weekdays, every N days/weeks, monthly.)
  - Monthly day 29–31 in a shorter month → that month's **last day**.
  - Start date + optional end date (inclusive). *(extra: end date)*

**Schedule — time**
- Fixed time, or time range `start–end`. `end < start` → the window runs past
  midnight into the next day. A one-time range stays within its date (plus
  the past-midnight rule); it never spans several days.
- Range mode *Interval*: every X minutes from the range start until the range
  end or until max N is reached (max optional).
- Range mode *Random*: **exactly N** per window, **spread**: window split into
  N equal slots, one random time per slot. Must be deterministic per
  (reminder, window) so times don't move between app launches.
- Max activations counts **per window** (e.g. per day).

**Activation and acknowledgment**
- Activation → notification (title = display name, text = description) with
  an **Acknowledge** action button; reminder shows thumbs down (negative/red)
  in app and widget.
- Stays active until acknowledged via app, widget, or notification button.
  Swiping the notification away does **not** acknowledge.
- New activation while still unacknowledged → notify again; the previous one
  is recorded as **missed** in history; app and widget show the missed count
  until the new one is acknowledged.
- History of every activation (acknowledged / missed / active), kept
  **forever** (user chose this knowing sembast keeps all data in memory).
- Interval mode **includes the range end** when it lands on a step
  (09:00–17:00 every 60 min → 9 activations).

**Lifecycle: edit, pause, archive, delete**
- Editing or pausing a reminder while it is active keeps the waiting
  activation **active until acknowledged**; only future activations change.
  Paused reminders do not activate.
- Two separate actions: **Archive** (keeps the history, never fires again,
  moves to the Archive screen) and **Delete** (removes the reminder *and* its
  history).
- A **finished** reminder (one-time reminder after its activations, or a
  repeating one past its end date) is **moved to the archive automatically**
  once nothing is waiting (i.e. after it is acknowledged). There is no "Done"
  list.
- Archive screen: view history, **Restore** (back to the list; for a finished
  one-time reminder the editor opens so a new date can be picked) and
  **Delete**.

**Extras chosen:** pause/resume, end date for recurring, schedule preview
(next few activation times in the editor). *Not* chosen: snooze.

**Widget:** one widget per reminder (user picks the reminder when adding it).
Shows display name, thumb (green up / red down) and a "N missed" badge. Tap
thumbs down to acknowledge. If its reminder is archived or deleted, the widget
shows the display name with a neutral "Archived" / "Deleted" label instead of
the thumb, and tapping it lets the user pick another reminder (Android:
reopens the widget configuration; iOS: long-press → Edit Widget, which the app
explains).

**Theme:** Material You (dynamic color, Android 12+) with indigo `#4F46E5` /
teal `#14B8A6` fallback; light/dark follow the system; positive green,
negative red.

**Project:** app name "Just Reminder"; Android `com.example.just_reminder`;
iOS `com.example.justReminder`; English UI; 12/24 h follows the device.

## Architecture (planned — refine as each step lands)

```text
lib/src/
  core/       dates (LocalDate/LocalTime), stable hash, seeded PRNG, clock
  domain/     Reminder, Schedule, Activation models + ScheduleEngine (pure Dart)
  data/       sembast database + repositories
  services/   sync, notifications, widget bridge, background handlers
  state/      Riverpod providers
  ui/         theme, routing (go_router), screens, components
```

- **Domain is pure Dart** (no Flutter imports) so the schedule engine is fully
  unit-testable. Random mode uses its own PRNG seeded by a stable hash of
  (reminder id, window date); do not use `dart:math` `Random(seed)` (its
  sequence may change between SDK releases).
- **sembast is the source of truth and is opened only in the main isolate.**
  Notification-action and widget-tap handlers run in background isolates and
  must never open sembast (it is not multi-isolate safe).
- **Widget storage is the bridge.** The app writes a per-reminder snapshot
  (display name, current state, upcoming activation times) to home_widget
  storage. Any isolate that acknowledges appends to an ack log there. On
  start/resume the app syncs: it turns elapsed activations into history,
  applies logged acks in time order (an activation while one is pending marks
  the pending one missed), rewrites snapshots, reschedules notifications
  (diffed by id) and widget updates.
- **Notifications** are scheduled in a rolling window (iOS 64 limit). Ids are a
  stable hash of (reminder id, activation instant).
- **Widgets** are native: Android `HomeWidgetProvider` + RemoteViews (Kotlin),
  iOS WidgetKit extension (Swift, iOS 17+). They compute their state from the
  snapshot, so they flip to thumbs down at activation time without the app
  running (Android via `scheduleWidgetUpdates`, iOS via timeline entries).

## Conventions

- Immutable models with `copyWith`, `toJson`/`fromJson`; one concept per file.
- Domain and sync logic need unit tests; use `databaseFactoryMemory` for
  sembast in tests.
- Lints: `analysis_options.yaml` (strict casts/inference/raw types, single
  quotes, final locals, ordered directives). Keep `flutter analyze` clean.

## Status

- [x] **Step 1 — Scaffold** (2026-11-04): Flutter project (android, ios),
  dependencies, desugaring, app label, lints, app shell with Material You
  theme and go_router, README/CLAUDE.md.
- [ ] Step 2 — Models, schedule engine, sembast storage (+ unit tests)
- [ ] Step 3 — Theme and UI screens (list, editor + schedule preview,
  details + history, archive)
- [ ] Step 4 — Notifications and home screen widgets (Android + iOS)
- [ ] Step 5 — Final tests, docs, verification
