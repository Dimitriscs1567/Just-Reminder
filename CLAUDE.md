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

Dart 3.13 allows initializing formals for private named parameters
(`ReminderService({required this._repository})`, called as
`repository:`); the linter (`prefer_initializing_formals`) asks for them.

More gotchas:
- intl's 12-hour format separates AM/PM with a narrow no-break space
  (`'9:30 PM'`).
- `x ?? const []` infers `List<dynamic>`; write `const <ReminderView>[]`.
- Widget tests: `find.byType(FilledButton)` doesn't match
  `FilledButton.icon` (a subclass) — find by text; `enterText` doesn't pump,
  so pump before testing anything that depends on the rebuild (e.g.
  `PopScope.canPop`).
- On Git Bash, `adb` device paths need `MSYS_NO_PATHCONV=1`.
- `adb shell pm clear` also deletes `files/` — launch the app once before
  copying a database into it.
- Emulator widget test: long-press home → Widgets → search "Just" → tap the
  preview → Add → the configuration screen opens. Notification shade:
  `adb shell cmd statusbar expand-notifications`. Resize: long-press the
  widget, then `adb shell input swipe` from a handle. A 1×1 cell on the
  Medium_Phone emulator is about 76×91 dp; Android's docs give 57×102 dp
  (portrait, 5-column grid) as the narrow case to design for.
- Windows PowerShell's `Set-Content -Encoding utf8` writes a BOM — avoid it
  for source files.
- The iOS Swift code cannot be compiled on this machine; metadata
  properties (`title`, `description`, `defaultQuery`, …) are computed
  `static var`s like Apple's templates (safe with Swift 6 concurrency).

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
- Archiving a reminder while it is active records the waiting activation as
  **missed**.
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
explains). Android widgets are **1×1 by default** and resizable (requested
2026-11-04); iOS has no 1×1 home screen size, so it stays `systemSmall`.

**Theme:** Material You (dynamic color, Android 12+) with indigo `#4F46E5` /
teal `#14B8A6` fallback; light/dark follow the system; positive green,
negative red.

**Project:** app name "Just Reminder"; Android `com.example.just_reminder`;
iOS `com.example.justReminder`; English UI; 12/24 h follows the device.

### Implementation choices (made by Claude, not specified by the user)

Reasonable defaults that were reported to the user; ask before changing the
*behavior* they describe.

- Input limits (`ReminderLimits`): name ≤ 60, display name ≤ 30 (widget
  space), description ≤ 500 characters; repeat every 1–99; interval 1 min –
  24 h; interval cap and random count 1–100 (random also ≤ the range's
  minutes).
- Start time == end time is invalid (no 24-hour windows).
- Random times are whole minutes inside `[start, end)`.
- Reminders follow the device's local wall clock (they move with time-zone
  changes).
- Restoring resets the missed count and replays nothing from the archived
  period.
- A paused reminder whose schedule can no longer activate (e.g. its one-time
  date passed while paused) is archived like any finished reminder.
- UI defaults: a new reminder starts as "repeat daily at the next full
  hour"; the display name follows the name until the user edits it;
  interval presets 5 min – 3 h plus "Custom…" (minutes); the editor
  preview shows 8 activations, details shows 6; history loads 30 at a
  time.
- Archive's snackbar offers **Undo** only when nothing was waiting (undo
  can't un-miss the waiting activation). Delete always asks for
  confirmation. Closing the editor with changes asks "Discard changes?".
- Restoring a reminder that could never activate again opens the editor
  in restore mode (`/reminder/:id/edit?mode=restore`); otherwise it is
  restored directly.
- Notifications: body falls back to "Tap Acknowledge once you’ve done it.";
  "N missed" as Android subText / iOS subtitle; on Android the previous
  notification of a reminder disappears when its next one arrives; tapping
  a notification opens the reminder.
- Widget: tapping the thumb acknowledges only while waiting, anywhere else
  opens the reminder. Android compact layout (1×1 and anything smaller than
  120×160 dp): 48 dp thumb (shrinks when short) with the missed count as a
  number bubble ("99+" above 99), display name below (2 lines), short
  labels "Archived" / "Deleted" / "Tap to choose". Large layout (≥ 120×160
  dp, about 2×2): name on top, 60 dp thumb, "N missed" pill, full labels
  ("Archived · tap to choose another"). iOS widget is `systemSmall` and
  needs iOS 17 (the app itself stays iOS 15+).

## Architecture

```text
lib/
  main.dart     main(): App Group, notification plugin + handlers, widget
                interactivity callback, launch event, DB, ProviderScope;
                widgetConfigurationMain(): Android widget configuration
  src/
    background/ background_handlers.dart — widget tap / notification
                button entry points (no database)
    core/       LocalDate, LocalTime, FNV-1a stableHash, SeededRandom
                (mulberry32), newId, Clock, app constants            pure Dart
    domain/     Schedule (Recurrence + Timing), Reminder, ActivationRecord,
                ReminderRuntime, ScheduleEngine, advanceRuntime,
                validation                                          pure Dart
    data/       openAppDatabase(), ReminderRepository (sembast)
    services/   ReminderService, AckInbox, WidgetStorageKeys, AppEvents,
                AppSideEffects, notifications/ (plan, scheduler, service),
                widget/ (snapshot, bridge)
    state/      Riverpod providers: data (providers.dart), clock (now.dart),
                view models (reminder_views.dart)
    ui/         theme, routing (go_router), components, screens
                (home, editor, details, archive, widget_config),
                formatting, actions, sync_scope.dart
android/app/src/main/kotlin/com/example/just_reminder/
                ReminderWidgetProvider, WidgetStore, WidgetConfigurationActivity
ios/ReminderWidget/
                WidgetKit extension (needs the Xcode target, see README)
```

### Domain (`lib/src/domain`, pure Dart — no Flutter imports)

- `Schedule` = `Recurrence` (sealed: `OnceRecurrence(date)` |
  `RepeatRecurrence(unit day/week/month, every, startDate, endDate?,
  weekdays, dayOfMonth)`) + `Timing` (sealed: `FixedTiming(time)` |
  `RangeTiming(start, end, mode interval/random, intervalMinutes,
  maxActivations?)`).
- `ScheduleEngine` turns a schedule into local `DateTime` instants:
  `between(id, schedule, from, to)` is `(from, to]`; `upcoming(...)` /
  `upcomingFor(reminder, ...)` are strictly after; `isFinished(reminder, now)`.
  Windows that run past midnight are found by scanning from the day before.
  Random mode seeds `SeededRandom` with `stableHash32('$reminderId|$date')`;
  never switch to `dart:math` `Random(seed)` (its sequence may change between
  SDK releases). `test/core/hash_and_random_test.dart` pins the output —
  it was cross-checked against the reference JavaScript mulberry32/FNV-1a.
- `advanceRuntime` is the state machine: replays new activations and
  acknowledgments in time order (activation first on ties). An activation
  while another is pending marks that one **missed** (`missedCount++`); an
  acknowledgment acknowledges the pending one and resets `missedCount`.
  `closePendingAsMissed` is used by archive.
- `ReminderRuntime` (pending activation, missed count, last ack,
  `processedUntil`, `appliedAckUntil`) is persisted separately from the
  history so lists, widgets and notifications never scan history.
- `Reminder.activeSince`: activations at or before it never happen. Set to
  "now" on create, schedule edit, resume and restore — this is what prevents
  catch-up after a pause/edit/archive.
- Schedule equality is **semantic**: `RepeatRecurrence` ignores `weekdays`
  unless weekly and `dayOfMonth` unless monthly; `RangeTiming` ignores
  `intervalMinutes` in random mode. The editor keeps those values (for
  switching back) but `EditorDraft.schedule` normalizes them, so
  "unchanged" really compares equal.

### Data (`lib/src/data`)

sembast database `just_reminder.db` in the app support directory, schema
version 1. Stores: `reminders` (id → Reminder JSON), `runtimes` (id →
ReminderRuntime JSON), `history/<reminderId>` (activation epoch ms →
ActivationRecord JSON; one store per reminder so queries stay small and
delete is a `drop`). `ReminderRepository.save` writes reminder, runtime and
records in one transaction. DateTimes are stored as epoch ms ints.

### Services (`lib/src/services`)

- **sembast is opened only in the main isolate.** Notification-action and
  widget-tap handlers run in background isolates and must never open it.
- `AckInbox` is the bridge: every acknowledgment (app, widget, notification
  button) is appended, with its time, to home_widget storage key
  `jr.acks.<reminderId>` (JSON array of epoch ms, last 50 kept).
  `HomeWidgetAckInbox` in the app; `MemoryAckInbox` in tests.
- `ReminderService` performs every mutation, serialized through an internal
  queue: `create`, `update`, `setPaused`, `archive`, `restore`, `delete`,
  `acknowledge` (= log to inbox + sync), `syncAll`. Sync per reminder:
  activations in `(max(processedUntil, activeSince), now]` (none if paused
  or archived) + inbox acks newer than `appliedAckUntil` → `advanceRuntime`
  → save; archives the reminder when it is finished and nothing is waiting.
  Edits, pause and archive sync first, so the old schedule's history is
  complete. A sync with nothing new writes nothing.
- `ReminderSideEffects.onRemindersChanged()` runs after every mutation
  (inside the service queue). `AppSideEffects` publishes widget snapshots
  and reschedules notifications; failures are logged, never thrown.
  `sideEffectsProvider` falls back to `NoSideEffects` when
  `notificationServiceProvider` is null (tests).

### Notifications (`lib/src/services/notifications`)

- `planNotifications` (pure): live reminders' upcoming activations within
  14 days; budget iOS 60 / Android 200 total, each reminder first gets its
  next 3 (round-robin), then soonest-first; per reminder always a gap-free
  prefix. Title = display name, body = description or
  `defaultNotificationBody`, subtitle/subText "N missed" (= missed so far
  + index), Android `timeoutAfter` = time to the reminder's next scheduled
  notification (it replaces the old one).
- Ids: `notificationIdFor(id, at)` = `stableHash31('$id@$ms')`. Payload JSON
  `{r: reminderId, t: ms, h: hash(content + exact/inexact)}` —
  `payloadFor(exact:)`. The mode is part of the hash so granting/revoking
  exact alarms reschedules everything (found on the emulator: inexact
  alarms stayed inexact after granting).
- `NotificationScheduler.apply` diffs plan vs `pendingNotificationRequests`
  (unchanged stay, changed rescheduled, others cancelled) but keeps a due,
  undelivered notification of a reminder's waiting activation (late
  inexact alarm). `clearDeliveredExcept(waitingIds)`,
  `clearDelivered(id)`, `renumberAfterAcknowledgment(id)` (background).
  `NotificationGateway` abstracts the plugin (fake in tests).
- `NotificationService`: `initialize(onBackgroundResponse:, onResponse:)` —
  **every isolate must pass the same background handler**
  (`notificationBackgroundHandler`), or the stored handle may be cleared.
  Android channel `reminders` (high importance, category reminder, tag =
  reminder id, Acknowledge action without UI). iOS category `reminder` with
  a plain Acknowledge action, `threadIdentifier` = reminder id. Scheduling
  uses `tz.UTC` (absolute instants; no tz database needed).
  `exactAllowWhileIdle` when allowed, else `inexactAllowWhileIdle`.
- Permissions: `PermissionBanner` on home (notifications off → request /
  settings; Android exact alarms → "Alarms & reminders"); the editor asks
  for notification permission after saving if not granted.

### Widgets (`lib/src/services/widget`, native code)

- Storage contract (`WidgetStorageKeys`, mirrored in `WidgetStore.kt` /
  `WidgetStore.swift`): `jr.reminder.<id>` snapshot JSON (`v, id, name,
  displayName, state live|paused|archived|deleted, asOf, pendingAt,
  missedCount, upcoming[], reminder{}`), `jr.reminders` index
  (`[{id, name, displayName, archived}]`), `jr.acks.<id>` ack log,
  Android `jr.widget.<appWidgetId>` → reminder id. Deleted reminders keep a
  tombstone snapshot.
- State at time t (same in Dart `widgetStatusAt`, Kotlin, Swift):
  `total = (pendingAt != null ? 1 + missedCount : 0) + |upcoming ∩ (asOf, t]|`;
  waiting if `total > 0`, missed = `total − 1`.
- `WidgetBridge.publish` (after every change): snapshots, index, tombstones,
  Android `scheduleWidgetUpdates` at the upcoming times (≤ 500), then
  `updateWidget(qualifiedAndroidName: …ReminderWidgetProvider, iOSName:
  ReminderWidget)`.
- Android layouts: `reminder_widget_small.xml` (compact, the 1×1 default)
  and `reminder_widget.xml` (large), with the same view ids. API 31+ gets
  both as `RemoteViews(Map<SizeF, RemoteViews>)` (compact at 0×0, large at
  120×160 dp), so the launcher switches by itself on resize; below API 31
  the provider picks from the size options (portrait / landscape
  `RemoteViews`) and redraws in `onAppWidgetOptionsChanged`. The thumbs
  `widget_thumb_up/down` are single vectors (circle + icon), so the compact
  thumb can shrink with `adjustViewBounds` without distorting.
- Android: `ReminderWidgetProvider` (HomeWidgetProvider + RemoteViews):
  waiting → red, thumb tap =
  `HomeWidgetBackgroundIntent` `justreminder://acknowledge?id=…`
  (home_widget runs `widgetInteractionCallback` via WorkManager), rest opens
  `justreminder://reminder/<id>?homeWidget`; archived / deleted /
  unconfigured → label, tap reopens `WidgetConfigurationActivity`
  (`FlutterActivity` with entry point `widgetConfigurationMain` → Flutter
  picker reading the index, then `finishHomeWidgetConfigure`). Material You
  neutral colors on API 31+ (`values-v31`).
- iOS (`ios/ReminderWidget`, iOS 17+): `AppIntentConfiguration` with
  `SelectReminderIntent` (entities from the index; unknown ids resolve to a
  "deleted" entity), timeline entry now + one per upcoming activation,
  thumbs-down `Button(intent: AcknowledgeReminderIntent)` runs **in the
  extension**: appends to the ack log, rewrites the snapshot, clears and
  re-numbers notifications (`NotificationCleanup`) — no Flutter engine in
  the extension. Archived/deleted → `justreminder://widget-help` (the app
  explains Edit Widget).

### Background acknowledgment (`lib/src/background`)

`acknowledgeInBackground(id)`: ack log + acknowledged snapshot (+
`updateWidgets`) + clear tray + renumber. Used by
`widgetInteractionCallback` (Android widget) and
`notificationBackgroundHandler` (Acknowledge button, both platforms).
`AppEvents` (main isolate): `OpenReminder` (notification/widget tap,
launch), `AcknowledgeReminder` (button while running),
`ExplainWidgetEditing`; handled in `SyncScope`.

### State and UI (`lib/src/state`, `lib/src/ui`)

- `nowProvider` (`NowNotifier`) ticks at every minute boundary;
  `refresh()` after syncs. `reminderViewsProvider` combines reminders,
  runtimes, now and the engine into `ReminderView`s with a
  `ReminderStatus` (waiting > paused > scheduled / ended; archived);
  `reminderViewProvider(id)`, `nextActivationProvider`,
  `historyProvider((reminderId:, limit:))`.
- `SyncScope` (in `MaterialApp.router`'s builder) runs `syncAll()` on
  start, on resume (`AppLifecycleListener`) and with a timer at the next
  activation (+1 s).
- `routerProvider` (GoRouter per ProviderScope): `/`, `/new`, `/archive`,
  `/reminder/:id`, `/reminder/:id/edit[?mode=restore]`. Editors are
  full-screen dialogs.
- Editor: `EditorDraft` (flat, immutable form state) +
  `EditorController` (`editorProvider(EditorTarget)` —
  `(mode: create|edit|restore, reminderId:)`). The draft id is generated
  up front so the preview's random times equal the saved ones.
- `reminder_actions.dart`: acknowledge / pause / archive (+undo) / restore
  / delete with their snackbars and dialogs — reuse these from any screen.
- Theme (`ui/theme/app_theme.dart`): `buildAppTheme(scheme)`; dynamic
  scheme or `fallbackColorScheme` (indigo + teal tertiary).
  `StatusColors` theme extension (`context.statusColors`), **not
  harmonized** (harmonizing turned red pink): solid colors and container
  text from `DynamicSchemeVariant.vibrant`, container backgrounds from
  `tonalSpot` (vibrant containers were neon green). In dark mode the solid
  colors are the mid-tone brand colors with white content (Material's
  dark tones looked washed out / neon); dark cards use
  `surfaceContainerHigh`. Widget colors (Android `values*/colors.xml`, iOS
  `Palette`) are separate constants in the same spirit.
- Components: `StatusThumb` (animated thumb), `ReminderCard`,
  `ReminderStatusLine`, `MissedBadge`, `SectionCard`, `NumberStepper`,
  `PickerField`, `ActivationTimes` (times grouped by day), `EmptyState`.

## Conventions

- Immutable models with `copyWith`, `toJson`/`fromJson`; one concept per file.
- Domain and sync logic need unit tests; use `newDatabaseFactoryMemory()`
  for sembast in tests.
- Widget tests use `test/support/test_app.dart` (`TestHarness`): the real
  app on an in-memory database, `MemoryAckInbox`, a controllable clock and
  a timer-free `nowProvider`; call `harness.dispose(tester)` at the end.
  Open/close the database inside `tester.runAsync`.
- Check UI changes on the Android emulator (build the debug APK, install
  with adb, `adb exec-out screencap -p`), in light **and** dark mode
  (`adb shell cmd uimode night yes|no`).
- Lints: `analysis_options.yaml` (strict casts/inference/raw types, single
  quotes, final locals, ordered directives). Keep `flutter analyze` clean.

## Status

- [x] **Step 1 — Scaffold** (2026-11-04): Flutter project (android, ios),
  dependencies, desugaring, app label, lints, app shell with Material You
  theme and go_router, README/CLAUDE.md.
- [x] **Step 2 — Models, schedule engine, storage** (2026-11-04): core
  types, domain models + JSON, schedule engine, missed/ack state machine,
  validation, sembast repository, ack inbox, reminder service, Riverpod
  providers, DB bootstrap in `main()`; 71 tests (`test/core`,
  `test/domain`, `test/services`).
- [x] **Step 3 — Theme and UI screens** (2026-11-04): Material You theme
  with green/red status colors (light + dark), home (summary, needs
  attention, coming up, paused), editor (create / edit / restore, live
  preview), details (status, schedule, pause, upcoming, history), archive,
  go_router routes, sync on start/resume/next activation; 87 tests
  (incl. widget tests in `test/ui`). Checked on the Android emulator.
- [x] **Step 4 — Notifications and home screen widgets** (2026-11-04):
  scheduled notifications with Acknowledge action and "N missed",
  permission banner, background acknowledgment, widget snapshots, native
  Android widget + Flutter configuration screen, iOS WidgetKit extension
  sources + AppDelegate/Info.plist, deep links; 107 tests. Verified on the
  Android emulator: notification fired and its Acknowledge button worked
  with the app in the background, widget added/configured, turned red on
  its own at an activation, thumb tap acknowledged, widget tap opened the
  reminder with the correct history. iOS not compiled (Windows).
- [x] **Widget 1×1 by default** (2026-11-04, after step 4): compact layout
  for 1×1, large layout from about 2×2, switching on resize. Verified on
  the Android emulator (light + dark): new widget placed at 1×1, waiting
  with count bubble, clear, deleted label, thumb tap acknowledges, resize
  to 2×2 switches layouts. Android < 12 path not run.
- [ ] Step 5 — Final tests, docs, verification
