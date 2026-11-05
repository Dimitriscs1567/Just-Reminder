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
flutter test tool/app_icon/generate_app_icon_test.dart   # regenerate app icons
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
- `HomeWidget.registerInteractivityCallback` is called on Android only: on
  iOS < 17 home_widget throws (the app would never reach `runApp`), and on
  iOS 17+ it starts an unused engine (the iOS widget acknowledges in Swift).
- Release builds aren't debuggable, so `run-as` (database seeding) fails:
  seed under the debug build, then `adb install -r` the release APK over it
  (same debug signing key, data kept). For the emulator use
  `flutter build apk --release --target-platform android-x64` (~22 MB):
  installing the 55 MB all-ABI APK once froze the emulator (recover with a
  cold boot, `emulator -avd Medium_Phone -no-snapshot-load`), and the
  interrupted install removed the home screen widgets.
- Widget tests run on an 800×600 screen: pump after `ensureVisible` before
  tapping; a floating SnackBar covers the bottom (scroll the target up
  first); ListView children scrolled far away aren't built, so scroll back
  before `find` (or `scrollUntilVisible(..., scrollable:
  find.byType(Scrollable).first)` for something further down, like the
  editor's "Add time"). Times show in 12-hour format there
  (`'9:00 AM'`).
- A `Hero` flight draws the destination's hero child in the navigator's
  overlay, which has no `Material` — so never put an `InkResponse` /
  `InkWell` (or anything else that needs a Material ancestor) inside a
  `Hero`. `StatusIcon(heroTag:)` flies only the drawing; its tap target
  stays outside (going back from a due reminder showed "No Material widget
  found" mid-flight). `test/ui/app_test.dart` checks a flight back.
- Seeding the emulator for a quick end-to-end check: force-stop the app,
  append a sembast record line (`{"key":…,"store":"reminders","value":{…}}`)
  with `run-as … sh -c 'cat >> files/just_reminder.db'`, start it again.
- `dart format` has never been applied (about 30 files would change); don't
  reformat whole files as part of unrelated changes.
- Flutter's deep linking is **on by default** (no manifest/plist entry
  needed): Android hands the whole intent URI to the framework as the
  initial route and on `onNewIntent`; iOS does it on a cold start (when the
  app runs, home_widget claims `?homeWidget` URLs first). go_router turned
  `justreminder://reminder/<id>` into the unknown path `/<id>` and showed
  its error page until `SyncScope` navigated. It is now off
  (`flutter_deeplinking_enabled` on both Android activities,
  `FlutterDeepLinkingEnabled` in Info.plist); home_widget still gets the
  URLs through its own callbacks. Keep it off unless the router learns the
  URL forms.
- The emulator's installed debug APK can end up corrupt ("Can't load Kernel
  binary: Invalid kernel binary" in logcat, stuck on the splash): reinstall
  it. A snapshot boot can hang too (qemu idle): `emulator -avd Medium_Phone
  -no-snapshot-load`.

## Product decisions

Agreed with the user on 2026-11-04, revised on 2026-11-05 (times, states,
wording, look). These are the spec.

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

**Schedule — times** (2026-11-05; replaced "fixed time" vs "time range")
- A reminder has **one or more times**. Each time has a **start**, an
  **optional end** (`end < start` → past midnight; a time still belongs to
  the day it starts on) and **how often to notify**: *Once*, *Repeat* every
  X minutes (with an optional **max number of notifications**) or — only
  with an end — *Random*: **exactly N** notifications, start–end split into
  N equal parts with one random time in each, deterministic per (reminder,
  date, start) so they don't move between app launches.
- Each time is **one reminder** (one history entry). It becomes due at its
  **first notification** (the start; with Random the first random time) and
  notifications repeat until it is **Done**, which stops its remaining
  notifications.
- **Without an end** it stays due and keeps notifying until Done or until
  the reminder's **next time starts**, where it is recorded as **missed**.
  The optional max only limits the notifications; it stays due either way
  (a one-time reminder's last time stays due until Done).
- **With an end** it notifies only between start and end and is recorded as
  **missed at the end** if it isn't Done.
- Times must **not overlap**; **back-to-back is allowed** (a time may start
  exactly when the previous one ends; the earlier one then sends nothing at
  that instant). All times together must fit in **one day**: the last end
  may not run past the first start of the next day.
- Every list (history, coming up, editor preview) shows each time **once**
  (as `09:00 – 17:00` when it has an end), done or not.

**States** (2026-11-05)
- Three states, the same in the app and on the widgets: **firing** (a time
  is due), **missed** (today's latest time was missed and nothing is due),
  **done** (nothing due: everything done, or nothing has happened yet that
  day).
- The **missed count** counts only the missed times of the **same day** and
  shows in all three states (Done doesn't reset it). A new day **starts
  clean** (done, no count) until its first time; a time still due from the
  previous evening keeps showing as firing (with its own day's count).
- Notifications: title = display name, text = description, a **Done**
  button, "N missed" (the day's). Swiping a notification away does **not**
  mark it done.
- History of every time (done / missed / due), kept **forever** (user chose
  this knowing sembast keeps all data in memory).

**Wording** (2026-11-05): the UI never says "activation" — it says
**reminder** — and **Done** replaces "Acknowledge" (buttons, notification
action, history).

**Look** (chosen 2026-11-05 from mockups; replaced the green/red thumbs)
- Firing: teal (the app's main color, `#0F766E`) tint and a ring with a
  **thumbs-up** inside; tapping it marks Done. Missed: gray **dashed ring**
  with a thumbs-up crossed by a dashed line. Done: a **faint check**. The
  missed count is a neutral gray bubble, never red.
- Editor: the times are **rows that open in place** (layout A): a summary
  per time, tap to open its settings; times sort themselves by start; "Add
  time" adds one an hour after the last; Random is only offered with an
  end.

**Lifecycle: edit, pause, archive, delete**
- Editing or pausing a reminder while a time is due keeps it **due until
  Done** (or missed at its end; when it has none, at the new schedule's
  next time — none comes while paused); only future times change. Paused
  reminders don't remind.
- Two separate actions: **Archive** (keeps the history, never reminds again,
  moves to the Archive screen) and **Delete** (removes the reminder *and*
  its history).
- Archiving a reminder while a time is due records it as **missed**.
- A **finished** reminder (one-time reminder after its times, or a
  repeating one past its end date) is **moved to the archive automatically**
  once nothing is due (i.e. after Done, or missed). There is no "Done" list.
- Archive screen: view history, **Restore** (back to the list; for a finished
  one-time reminder the editor opens so a new date can be picked) and
  **Delete**.

**Extras chosen:** pause/resume, end date for recurring, schedule preview
(next few times in the editor). *Not* chosen: snooze.

**Widget:** one widget per reminder (user picks the reminder when adding it).
Until step 8 it keeps its 2026-11-04 look: display name, thumb (green up /
red down) and a "N missed" badge; tap the thumbs down to mark it done. If its
reminder is archived or deleted, the widget shows the display name with a
neutral "Archived" / "Deleted" label instead of the thumb, and tapping it
lets the user pick another reminder (Android: reopens the widget
configuration; iOS: long-press → Edit Widget, which the app explains).
Android widgets are **1×1 by default** and resizable (requested 2026-11-04);
iOS has no 1×1 home screen size, so it stays `systemSmall`.

**Pending for step 8 (agreed 2026-11-05):**
- The widgets show the three states with the new look; done is a
  **translucent** tile that blends into the wallpaper.
- **List widget** (new, Android and iOS): the user picks several reminders
  in its setup and they are shown in the **order picked** (tick order, drag
  to reorder). One row per reminder: state icon, display name, status;
  resizable; on Android it scrolls when they don't fit. An archived or
  deleted reminder keeps its row with a neutral "Archived" / "Deleted"
  label.

**Theme:** Material You (dynamic color, Android 12+) with indigo `#4F46E5` /
teal `#14B8A6` fallback; light/dark follow the system; a due reminder is
always teal; missed and done are neutral.

**App icon** (chosen 2026-11-05 from nine concepts): white bell with a green
(`#1E8E3E`) thumbs-up badge on a teal gradient (`#2DD4BF` → `#0F766E`).

**Project:** app name "Just Reminder"; Android `com.example.just_reminder`;
iOS `com.example.justReminder`; English UI; 12/24 h follows the device.

### Implementation choices (made by Claude, not specified by the user)

Reasonable defaults that were reported to the user; ask before changing the
*behavior* they describe.

- Input limits (`ReminderLimits`): name ≤ 60, display name ≤ 30 (widget
  space), description ≤ 500 characters; repeat every 1–99; **up to 24
  times** per reminder; interval 1 min – 24 h; notification limit and
  random count 1–100 (random also ≤ the minutes between start and end).
- A time's start == end is invalid (no 24-hour windows); two times can't
  start at the same minute.
- **Repeats stop before the end** (2026-11-05): a time is missed at its end,
  so a notification at that moment could no longer be done. (Replaces the
  2026-11-04 rule that interval ranges included their end.)
- Random times are whole minutes inside `[start, end)`.
- A time is missed when the next time **starts**, even if that one (Random)
  becomes due later.
- Reminders follow the device's local wall clock (they move with time-zone
  changes).
- Restoring resets the missed count and replays nothing from the archived
  period.
- A paused reminder whose schedule can no longer remind (e.g. its one-time
  date passed while paused) is archived like any finished reminder.
- **Paused reminders send no notifications**, also not for a time that is
  still due.
- Data from before 2026-11-05 is read as is: a fixed time becomes a time
  that notifies once, a range a time with an end (interval → repeat with
  its max, random → random). A waiting activation stays due as a time
  without an end; the missed count starts over. History entries keep
  their time ("acknowledged" reads as done).
- UI defaults: a new reminder starts as "repeat daily, once at the next
  full hour" with its time open; the display name follows the name until
  the user edits it; interval presets 5 min – 3 h plus "Custom…"
  (minutes); the editor preview shows 8 times, details shows 6; history
  loads 30 at a time.
- Home: "Due now" (firing), "Coming up" (missed, done, ended), "Paused";
  the summary card says "N reminders are due" (teal) or "Nothing due" with
  the day's missed count and the next time.
- Archive's snackbar offers **Undo** only when nothing was due (undo can't
  un-miss the due time). Delete always asks for confirmation. Closing the
  editor with changes asks "Discard changes?".
- Restoring a reminder that could never remind again opens the editor in
  restore mode (`/reminder/:id/edit?mode=restore`); otherwise it is
  restored directly.
- Notifications: body falls back to "Tap Done once you’ve done it.";
  "N missed" as Android subText / iOS subtitle (the day's misses, assuming
  earlier times not done yet will be missed); on Android the previous
  notification of a reminder disappears when its next one arrives; tapping
  a notification opens the reminder. The Done action keeps its old id
  (`acknowledge`) and the widget's URL its old host, so notifications and
  widgets from older versions keep working.
- Widget: tapping the thumb marks it done only while due, anywhere else
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
    domain/     Schedule (Recurrence + ReminderTime list), Occurrence,
                Reminder, OccurrenceRecord, ReminderRuntime,
                ScheduleEngine, advanceRuntime / advanceReminder,
                ReminderStanding, validation                       pure Dart
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
tool/app_icon/  app icon design + generator (writes the Android and iOS
                icon files; run as a flutter test)
```

Naming: the code calls one time of one day an **occurrence** (the UI says
"reminder"); a due occurrence is **pending** ("firing" in the decisions);
Done marks are still logged in the "ack" inbox.

### Domain (`lib/src/domain`, pure Dart — no Flutter imports)

- `Schedule` = `Recurrence` (sealed: `OnceRecurrence(date)` |
  `RepeatRecurrence(unit day/week/month, every, startDate, endDate?,
  weekdays, dayOfMonth)`) + `times: List<ReminderTime>` (any order;
  `orderedTimes` sorts by start). `ReminderTime(start, end?, mode
  once/repeat/random, intervalMinutes, maxNotifications?, randomCount)`.
  `Schedule.fromJson` also reads the pre-2026-11-05 `timing` (fixed →
  once, range interval → repeat with an end, range random → random).
- `Occurrence` = one time on one date: `start`, `end?`, `nextStart?` (the
  schedule's next time), `missesAt` (= end ?? nextStart), `notifications`
  (lazy, maybe endless: repeat before the end / next start / max; random
  in `[start, end)`), `dueAt` = first notification.
- `ScheduleEngine`: `occurrencesFrom(id, schedule, date)` (in start order,
  each with its `nextStart`; ends with the recurrence or after 3700 days);
  `dueBetween(id, schedule, from, to)` = occurrences becoming due in
  `(from, to]`; `upcoming(...)` / `upcomingFor(reminder, ...)` = due
  strictly after; `isFinished(reminder, now)`; `missesAt(reminder,
  pending)` / `nextStartAfter(reminder, start)` (only times that will
  really come: none while paused/archived, none due at or before
  `activeSince`). Times past midnight are found by scanning from the day
  before. Random seeds `SeededRandom` with
  `stableHash32('$reminderId|$date|$start')`; never switch to `dart:math`
  `Random(seed)` (its sequence may change between SDK releases).
  `test/core/hash_and_random_test.dart` pins the output — it was
  cross-checked against the reference JavaScript mulberry32/FNV-1a.
- `advanceRuntime` is the state machine: replays occurrences becoming due,
  misses (`missesAt`; `pendingMissesAt` for the stored pending one) and
  Done marks in time order (miss, then due, then Done at the same instant).
  A due occurrence becomes `pending` (one replacing a still-pending one
  misses it — only after schedule edits); a miss counts for its occurrence's
  date (`missedDate` / `missedCount`); Done finishes the pending one
  without touching the count; `last` = latest outcome.
  `advanceReminder(reminder, runtime, engine, now, acknowledgments)` wraps
  it for a reminder (the sync, and — without acks — the views, so the app
  is right between syncs). `closePendingAsMissed` is used by archive.
- `ReminderStanding.at(runtime, now)`: firing (pending, count of its date),
  missed (today's last outcome missed) or done; the count only for today
  (or the firing time's date), so a new day starts clean.
- `ReminderRuntime` (`pending` occurrence incl. its `ReminderTime` — edits
  don't change it —, `missedDate`/`missedCount`, `last`, `processedUntil`,
  `appliedAckUntil`) is persisted separately from the history so lists,
  widgets and notifications never scan history; it still reads the old
  `pendingAt` format.
- `Reminder.activeSince`: occurrences due at or before it never happen. Set
  to "now" on create, schedule edit, resume and restore — this is what
  prevents catch-up after a pause/edit/archive.
- Equality is **semantic**: `RepeatRecurrence` ignores `weekdays` unless
  weekly and `dayOfMonth` unless monthly; `ReminderTime` ignores the
  interval and max unless repeating and the random count unless random;
  `Schedule` ignores the order of times. The editor keeps unused values
  (for switching back) but `EditorDraft.schedule` normalizes them, so
  "unchanged" really compares equal.
- `validateSchedule`: issues carry a `timeIndex` into `Schedule.times`
  (`timeSpan` for start/end, overlaps and "more than a day").

### Data (`lib/src/data`)

sembast database `just_reminder.db` in the app support directory, schema
version 1 (the 2026-11-05 formats are read leniently, no migration step).
Stores: `reminders` (id → Reminder JSON), `runtimes` (id → ReminderRuntime
JSON), `history/<reminderId>` (occurrence start, epoch ms →
OccurrenceRecord JSON; one store per reminder so queries stay small and
delete is a `drop`). `ReminderRepository.save` writes reminder, runtime and
records in one transaction. DateTimes are stored as epoch ms ints.

### Services (`lib/src/services`)

- **sembast is opened only in the main isolate.** Notification-action and
  widget-tap handlers run in background isolates and must never open it.
- `AckInbox` is the bridge: every Done (app, widget, notification button)
  is appended, with its time, to home_widget storage key
  `jr.acks.<reminderId>` (JSON array of epoch ms, last 50 kept).
  `HomeWidgetAckInbox` in the app; `MemoryAckInbox` in tests.
- `ReminderService` performs every mutation, serialized through an internal
  queue: `create`, `update`, `setPaused`, `archive`, `restore`, `delete`,
  `markDone` (= log to inbox + sync), `syncAll`. Sync per reminder:
  `advanceReminder` with the inbox's Done marks newer than
  `appliedAckUntil` → save; archives the reminder when it is finished and
  nothing is due. Edits, pause and archive sync first, so the old
  schedule's history is complete. A sync without new history or Done marks
  writes nothing.
- `ReminderSideEffects.onRemindersChanged()` runs after every mutation
  (inside the service queue). `AppSideEffects` publishes widget snapshots
  and reschedules notifications; failures are logged, never thrown.
  `sideEffectsProvider` falls back to `NoSideEffects` when
  `notificationServiceProvider` is null (tests).

### Notifications (`lib/src/services/notifications`)

- `planNotifications` (pure): per live reminder the remaining
  notifications of its pending occurrence (none once done or missed) and
  those of the occurrences due within 14 days; budget iOS 60 / Android 200
  total, each reminder first gets its next 3 (round-robin), then
  soonest-first; per reminder always a gap-free prefix. Title = display
  name, body = description or `defaultNotificationBody`, subtitle/subText
  "N missed" = the date's misses so far + earlier unfinished occurrences of
  that date (assumed missed), Android `timeoutAfter` = time to the
  reminder's next scheduled notification (it replaces the old one).
- Ids: `notificationIdFor(id, at)` = `stableHash31('$id@$ms')`. Payload JSON
  `{r: reminderId, t: ms, s: occurrence start ms, m: missedBefore,
  h: hash(content + exact/inexact)}` — `payloadFor(exact:)`; the iOS
  extension reads `s` and `m` too. The mode is part of the hash so
  granting/revoking exact alarms reschedules everything (found on the
  emulator: inexact alarms stayed inexact after granting).
- `NotificationScheduler.apply` diffs plan vs `pendingNotificationRequests`
  (unchanged stay, changed rescheduled, others cancelled) but keeps a due,
  undelivered notification of a reminder's pending occurrence (late
  inexact alarm; `dueStarts`). `clearDeliveredExcept(dueIds)`,
  `clearDelivered(id)`, `afterDoneOutsideApp(id, occurrenceStart:)`
  (background: cancels the occurrence's remaining notifications, lowers
  `m` by one on later ones of the same date).
  `NotificationGateway` abstracts the plugin (fake in tests).
- `NotificationService`: `initialize(onBackgroundResponse:, onResponse:)` —
  **every isolate must pass the same background handler**
  (`notificationBackgroundHandler`), or the stored handle may be cleared.
  Android channel `reminders` (high importance, category reminder, tag =
  reminder id, teal, Done action without UI — its id `doneActionId` is
  still `'acknowledge'`). iOS category `reminder` with a plain Done action,
  `threadIdentifier` = reminder id. Scheduling uses `tz.UTC` (absolute
  instants; no tz database needed). `exactAllowWhileIdle` when allowed,
  else `inexactAllowWhileIdle`.
- Permissions: `PermissionBanner` on home (notifications off → request /
  settings; Android exact alarms → "Alarms & reminders"); the editor asks
  for notification permission after saving if not granted.

### Widgets (`lib/src/services/widget`, native code)

- Storage contract (`WidgetStorageKeys`, mirrored in `WidgetStore.kt` /
  `WidgetStore.swift`): `jr.reminder.<id>` snapshot JSON (`v, id, name,
  displayName, state live|paused|archived|deleted, asOf, pendingAt,
  missedCount, upcoming[], pending{start, due, missesAt}?,
  occurrences[{start, due, missesAt}], reminder{}`), `jr.reminders` index
  (`[{id, name, displayName, archived}]`), `jr.acks.<id>` Done log,
  Android `jr.widget.<appWidgetId>` → reminder id. Deleted reminders keep a
  tombstone snapshot.
- State at time t (same in Dart `widgetStatusAt`, Kotlin, Swift) — the
  2026-11-04 rule, until step 8 gives the widgets the three states:
  `total = (pendingAt != null ? 1 + missedCount : 0) + |upcoming ∩ (asOf, t]|`
  (`pendingAt` / `upcoming` = due times, `missedCount` = the pending
  occurrence's date); waiting if `total > 0`, missed = `total − 1`. A time
  missed at its end still shows as waiting until the app publishes again.
- `pending` / `occurrences` tell a Done outside the app which occurrence it
  finishes: `dueOccurrenceStartAt` (Dart) / `WidgetStore.dueOccurrenceStart`
  (Swift) = the latest due by then, unless already missed.
- `WidgetBridge.publish` (after every change): snapshots, index, tombstones,
  Android `scheduleWidgetUpdates` at the upcoming due times (≤ 500), then
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
  "deleted" entity), timeline entry now + one per upcoming due time,
  thumbs-down `Button(intent: AcknowledgeReminderIntent)` runs **in the
  extension**: `WidgetStore.markDone` appends to the Done log, rewrites the
  snapshot and returns the finished occurrence's start;
  `NotificationCleanup.done` clears the tray, cancels that occurrence's
  remaining notifications and lowers "N missed" on the date's later ones
  (payload `s` / `m`) — no Flutter engine in the extension.
  Archived/deleted → `justreminder://widget-help` (the app explains Edit
  Widget). A missing snapshot (e.g. App Group unreadable before the first
  unlock) gets a 15-minute retry instead of the 6-hour reload. Small
  widget: 52 pt thumb so a 2-line name + "N missed" fit.
- **iOS open items for the first Mac build** (from an independent review;
  no compile errors were found): (1) check that the notification's Done
  works after a force-quit (README "First test on an iPhone"); if not,
  handle the action natively in `AppDelegate`
  (`userNotificationCenter(_:didReceive:withCompletionHandler:)` →
  `WidgetStore.markDone` + `NotificationCleanup.done`, adding those two
  files to the Runner target); (2) `self as? UNUserNotificationCenterDelegate`
  may warn "always succeeds" (harmless; it's the plugin's documented
  line); (3) check the small widget in the Xcode preview.

### Done outside the app (`lib/src/background`)

`markDoneInBackground(id)`: Done log + done snapshot (+ `updateWidgets`) +
clear tray + `afterDoneOutsideApp` for the occurrence from
`dueOccurrenceStartAt`. Used by `widgetInteractionCallback` (Android
widget) and `notificationBackgroundHandler` (Done button, both platforms).
`AppEvents` (main isolate): `OpenReminder` (notification/widget tap,
launch), `MarkReminderDone` (button while running),
`ExplainWidgetEditing`; handled in `SyncScope`.

### State and UI (`lib/src/state`, `lib/src/ui`)

- `nowProvider` (`NowNotifier`) ticks at every minute boundary;
  `refresh()` after syncs. `reminderViewsProvider` combines reminders,
  runtimes, now and the engine into `ReminderView`s: the runtime brought
  forward to now (`advanceReminder`, no acks), its `ReminderStanding`, the
  `next` occurrence, `dueMissesAt` and a `ReminderStatus` (archived >
  firing > paused > ended > missed / done); `reminderViewProvider(id)`,
  `nextChangeProvider` (next due time or miss of any reminder),
  `historyProvider((reminderId:, limit:))`.
- `SyncScope` (in `MaterialApp.router`'s builder) runs `syncAll()` on
  start, on resume (`AppLifecycleListener`) and with a timer at the next
  change (+1 s), so history, notifications and widgets follow. The minute
  tick usually shows the change first (the views advance to "now"), which
  moves `nextChangeProvider` on and cancels that timer — so when the
  previous next change has already passed, it syncs at once (found on the
  emulator: a missed time's notification stayed in the tray; the old app
  had the same race at activation times).
- `main()` calls `deferFirstFrame()`: the launch screen stays up until
  `SyncScope`'s first sync is done and `remindersProvider` /
  `runtimesProvider` have loaded (it then calls `startupReadyProvider`,
  which `main()` overrides with `allowFirstFrame`; a 3 s timer is the
  fallback). So the first visible frame is complete and current — no
  loading spinner, no outdated state. `startupReadyProvider` is `null` in
  tests (no deferral there).
- `routerProvider` (GoRouter per ProviderScope): `/`, `/new`, `/archive`,
  `/reminder/:id`, `/reminder/:id/edit[?mode=restore]`. Editors are
  full-screen dialogs. When a widget or notification launched the app
  (`AppEvents.launchEvent` set in `main()` before `runApp`), the router's
  `initialLocation` is that reminder, so the first frame is its details;
  `SyncScope` then syncs and skips navigating when already there. Running
  app: `SyncScope` syncs, then `go`es to the reminder.
- Editor: `EditorDraft` (flat, immutable form state, `times:
  List<TimeDraft>` in start order; `TimeDraft.key` identifies a row while
  it re-sorts, ignored by `==`) + `EditorController`
  (`editorProvider(EditorTarget)` — `(mode: create|edit|restore,
  reminderId:)`; `editTime` / `addTime` / `removeTime`). The open row is
  widget state (`_openTime`). The draft id is generated up front so the
  preview's random times equal the saved ones.
- `reminder_actions.dart`: done / pause / archive (+undo) / restore /
  delete with their snackbars and dialogs — reuse these from any screen.
- Theme (`ui/theme/app_theme.dart`): `buildAppTheme(scheme)`; dynamic
  scheme or `fallbackColorScheme` (indigo + teal tertiary).
  `StatusColors` theme extension (`context.statusColors`): only the due
  teal (`due`, `onDue`, `dueContainer`, `onDueContainer`), fixed per
  brightness and **not harmonized**; missed and done use the scheme's
  neutrals (`outline`, `onSurfaceVariant`, `surfaceContainerHigh`). Dark
  cards use `surfaceContainerHigh`. Widget colors (Android
  `values*/colors.xml`, iOS `Palette`) are separate constants (still the
  2026-11-04 green/red until step 8).
- Components: `StatusIcon` (`StatusIconKind.of(status)`: teal ring +
  thumbs-up, dashed ring + slashed thumb drawn with painters, faint check;
  `surface` = the color behind it, for the slash's cut-out; `heroTag` =
  `statusHeroTag(id)` flies the drawing between card and details, drawn
  for the size it gets mid-flight; `onTap` makes the firing card's ring a
  Done button), `ReminderCard`,
  `ReminderStatusLine`, `MissedBadge`, `SectionCard`, `NumberStepper`,
  `PickerField`, `OccurrenceTimes` (times grouped by day, each once),
  `EmptyState`.

### App icon (`tool/app_icon`)

- `app_icon.dart` is the single source: geometry on a 96-unit tile (Material
  "notifications" and "thumb_up" paths, Apache 2.0), colours, the painter,
  and the Android/iOS file contents. `icon_path.dart` parses SVG path data
  (M L H V C S Z) into absolute segments, for `dart:ui` and for vector XML.
  `png.dart` is a tiny PNG encoder. `generate_app_icon_test.dart` writes the
  files; it's a test only so `dart:ui` can render, and `flutter test`
  (test/) doesn't run it.
- **Generated, don't edit by hand:** `res/drawable/ic_launcher_{background,
  foreground,monochrome}.xml`, `res/mipmap-anydpi-v26/ic_launcher.xml`,
  `res/mipmap-*/ic_launcher.png` (Android 7 launchers: a circle 44/48 of the
  size) and everything in `ios/Runner/Assets.xcassets/AppIcon.appiconset`
  (the generator deletes any other PNG there).
- Android adaptive icon: the tile maps onto the inner 72 dp of the 108 dp
  canvas; bell and badge stay within the 66 dp safe circle (about 26 dp
  from the centre). The monochrome (themed) layer is one colour, so the
  bell is clipped around the badge — a clip-path of the canvas plus a circle
  wound the other way (nonzero winding leaves a hole) — and the thumb is cut
  out of the badge with `fillType="evenOdd"`.
- iOS: single-size 1024 px set (Xcode makes the other sizes) with iOS 18
  dark (no background, the system draws it) and tinted (grayscale)
  variants. The light icon is written as **RGB without an alpha channel**:
  the App Store rejects icons with one, even fully opaque, and Flutter's
  own PNG encoder always writes RGBA.

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
- [x] **Step 5 — Final tests, docs, verification** (2026-11-05): 13 more
  tests (120 in total: random range past midnight, max per window, paused
  one-time reminder archived, notification details, the widget storage
  contract through a mocked home_widget channel, UI pause/resume, delete
  confirmation, restore-mode editor). Release build verified on the
  emulator: notification on time, Acknowledge in the background, widget
  configuration screen, widget turning red by itself, thumb acknowledging,
  alarms re-armed after a reboot. Independent review of the iOS code; fixed
  the iOS < 17 launch crash, the widget's retry when its data can't be read
  and the small widget's sizing; README Xcode steps completed. README known
  limitations added; throwaway seed tool removed.
- [x] **App icon** (2026-11-05): bell with a thumbs-up badge, generated from
  `tool/app_icon` for Android (adaptive, themed, Android 7 PNGs) and iOS
  (light, dark, tinted). Checked on the emulator: app drawer, dock, and the
  themed ("Minimal") icon preview. iOS icons not checked in Xcode.
- [x] **Step 6 — Widget tap without the go_router error** (2026-11-05):
  Flutter's deep linking turned off (Android activities, iOS Info.plist),
  so `justreminder://` links no longer reach go_router; a launch from a
  widget or notification starts the router at the reminder; the launch
  screen stays up until the first sync and the data are loaded. 121
  tests (new: first frame of a widget launch is the reminder). Verified
  on the Android emulator with screen captures: the last commit showed
  go_router's "Page Not Found — no routes for location:
  justreminder://reminder/…?homeWidget" for several frames on a cold
  start; now cold start goes splash → reminder (current state), warm
  start goes straight to the reminder, Back leads to the list, the
  archived widget still opens "Choose a reminder". iOS not run.
- [x] **Step 7 — Times and states in the app** (2026-11-05): several times
  per reminder (start, optional end, once / repeat with optional max /
  random N), one history entry per time (`Occurrence`, `OccurrenceRecord`),
  firing / missed / done with the same-day missed count
  (`ReminderStanding`), notifications repeating until Done or missed (Done
  outside the app cancels the rest, also in the iOS extension), "reminder"
  and "Done" wording, the teal look in the app (`StatusIcon`), the times
  editor (rows that open in place); old data is read as is; `SyncScope`
  now syncs when a change shows at the minute tick (race fixed); the
  status icon's hero flight no longer carries its tap target ("No
  Material widget found" when going back from a due reminder). 156
  tests. Verified on the Android emulator (light and dark) with the old
  database: converted reminders and history, home / details / editor; a
  test reminder (21:43–21:46 every minute, 21:47–21:49 once):
  notifications at 21:43 and 21:44 with a Done button, none at the end,
  Done on the notification cancelled 21:45 and cleared the tray, the app
  showed "Done 9:44 PM · next 9:47 PM", then due at 21:47 and missed at
  21:49 ("1 missed", notification removed). The widgets still have the
  old look and two states (step 8). iOS not compiled.
- [ ] **Step 8 — Widgets**: the single widget's three states and new look,
  and the new list widget with several reminders (Android and iOS).
