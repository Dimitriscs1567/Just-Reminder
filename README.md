# Just Reminder

A simple, beautiful reminder app for **Android and iOS**, built with Flutter.
Set up reminders that fire once or on a repeating schedule, at a fixed time or
inside a time range, and see at a glance on your home screen whether something
needs your attention:

- 👍 **green** — nothing is waiting for you
- 👎 **red** — a reminder fired and is waiting to be acknowledged

A reminder stays active until you acknowledge it — in the app, on the home
screen widget, or with the **Acknowledge** button on its notification.

> **Status:** feature complete. Android is tested on the emulator (debug and
> release builds); the iOS code is written but has not been compiled yet —
> see [iOS notes](#ios-notes) and [Known limitations](#known-limitations).

## Features

### Reminders

Each reminder has:

| Field            | Required | Where it is shown                                       |
| ---------------- | -------- | ------------------------------------------------------- |
| **Name**         | yes      | In the app (lists, details)                             |
| **Display name** | yes      | On the home screen widget and as the notification title |
| **Description**  | no       | In the app and as the notification text                 |

### Scheduling

**When it happens**

- **Once** — on a specific date.
- **Repeat**
  - **Daily** — every _N_ days (every day, every 3 days, …).
  - **Weekly** — every _N_ weeks on the weekdays you pick (e.g. Mon–Fri, or
    only Sat & Sun every 2 weeks).
  - **Monthly** — every _N_ months on a day of the month (e.g. the 15th). A
    day that a month doesn't have (29th–31st) falls on that month's **last
    day** (e.g. "the 31st" fires on Apr 30 and Feb 28/29).
  - Starts on a start date, with an optional **end date**.

**What time**

- **Fixed time** — e.g. 09:00.
- **Time range** — e.g. 09:00–17:00. An end time before the start time runs
  past midnight (e.g. 22:00–02:00). Inside the range, choose:
  - **Interval** — every _X_ minutes from the start of the range, until the
    range ends, or until the optional _max activations_ is reached.
  - **Random** — exactly _N_ activations at random times. The range is split
    into _N_ equal slots with one random time in each, so activations never
    bunch up. The times are fixed per day, so they don't move when the app
    restarts.
- _Max activations_ always counts **per window** (e.g. per day).
- In interval mode an activation that lands exactly on the range end counts
  (09:00–17:00 every 60 min → 9 activations).
- A one-time reminder with a time range stays within its date (or runs past
  midnight as above).

While you set up a reminder, a **schedule preview** shows its next activation
times, so you can check it is right.

### Activation, acknowledgment and history

- When a reminder activates you get a notification (title = display name,
  text = description) with an **Acknowledge** button, and the reminder turns
  red (👎) in the app and on its widget — also while the app is closed.
- Swiping the notification away only hides it; the reminder **stays active**
  until you acknowledge it.
- If a new activation arrives while the previous one is still unacknowledged,
  you are notified again. The previous one is recorded as **missed** in the
  history, and the app, the widget and the new notification ("2 missed") show
  how many were missed until you acknowledge the current one. On Android the
  older notification is replaced by the new one; on iOS they are grouped.
- Tapping a notification opens the reminder. Acknowledging from the
  notification or the widget works without opening the app.
- Every activation is kept in the reminder's **history** (acknowledged with
  time / missed / active). History is kept forever.

### Permissions

- The app asks to send notifications right after you save a reminder; a
  banner on the home screen offers it again if notifications are off.
- **Android 12+:** for notifications at the exact minute, allow _Alarms &
  reminders_ (the banner opens the setting). Without it Android may deliver
  them a few minutes late.

### Pause, archive and delete

- **Pause / resume** a reminder without deleting it. Editing or pausing a
  reminder that is currently active keeps it active until you acknowledge
  it; only future activations change.
- **Archive** keeps a reminder and its history but it never fires again.
  **Delete** removes the reminder and its history. Archiving a reminder that
  is currently active records the waiting activation as missed.
- Finished reminders (a one-time reminder after it fired, or a repeating one
  past its end date) move to the **archive automatically** once acknowledged.
- In the archive you can view the history, **restore** a reminder (for a
  finished one-time reminder the editor opens so you can pick a new date) or
  delete it.

### Home screen widget

- **One widget per reminder**: when you add the widget, you pick which
  reminder it tracks. Add several widgets to track several reminders.
- Shows the reminder's display name, a thumbs up (green) or thumbs down
  (red), and how many activations were missed while one is waiting.
- _Android:_ **1×1 by default**: the thumb with a small missed-count bubble
  and the display name below it. Resize it to about 2×2 or larger for a
  bigger thumb and a **"N missed"** badge.
- _iOS:_ the small widget size (iOS has no 1×1 home screen widgets), with a
  **"N missed"** badge.
- Tap the thumbs down to acknowledge right from the home screen; tap
  anywhere else on the widget to open the reminder.
- It turns red at activation time on its own, even when the app is closed.
- If the reminder is archived or deleted, the widget shows an "Archived" or
  "Deleted" label instead of the thumb; tap it (Android) or long-press → Edit
  Widget (iOS) to pick another reminder.

**Adding the widget**

- _Android:_ long-press the home screen → **Widgets** → **Just Reminder** →
  drag (or tap → Add) the _Reminder_ widget, then choose the reminder.
- _iOS (17+):_ long-press the Home Screen → **Edit** → **Add Widget** →
  **Just Reminder**, then long-press the widget → **Edit Widget** → choose the
  reminder.

### Screens

- **Home** — a summary card at the top ("All clear" with the next reminder,
  or "2 reminders need you"), then _Needs attention_ (waiting reminders, each
  with a big **Acknowledge** button and its missed count), _Coming up_
  (sorted by next activation) and _Paused_.
- **New / edit reminder** — Details (name, display name, description), When
  (once or repeat: daily / weekly with weekday picker / monthly, every N,
  start and optional end date), Time (fixed time or range with interval
  presets or random count) and a live **preview** of the next activations.
  The display name fills itself from the name until you change it. Closing
  with unsaved changes asks before discarding them.
- **Reminder details** — status panel (acknowledge, resume, or restore),
  schedule with a pause switch, the next activations, and the full history
  grouped by day. Archive and delete are in the ⋮ menu.
- **Archive** — archived reminders; open one to restore or delete it.

### Look and feel

Material 3 with **Material You**: on Android 12+ the app uses your wallpaper
colors; elsewhere it falls back to an indigo & teal palette. Light and dark
mode follow the phone's setting. Positive is always green and negative always
red (they are not tinted by the wallpaper, so red never turns pink). The UI
is in English; 12/24-hour time follows the phone's setting.

## Tech stack

| Concern             | Package                                                                                                                                 |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| UI                  | Flutter 3.47 with [`material_ui`](https://pub.dev/packages/material_ui) (Flutter's Material library, now a separate package)            |
| State management    | [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3                                                                       |
| Navigation          | [`go_router`](https://pub.dev/packages/go_router)                                                                                       |
| Local database      | [`sembast`](https://pub.dev/packages/sembast)                                                                                           |
| Home screen widgets | [`home_widget`](https://pub.dev/packages/home_widget) (+ native Kotlin / Swift widget code)                                             |
| Notifications       | [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) + [`timezone`](https://pub.dev/packages/timezone) |
| Material You colors | [`dynamic_color`](https://pub.dev/packages/dynamic_color)                                                                               |
| Helpers             | [`path_provider`](https://pub.dev/packages/path_provider), [`intl`](https://pub.dev/packages/intl)                                      |

## Getting started

### Prerequisites

- Flutter **3.47.8** or newer (Dart 3.13)
- Android: Android SDK 36, a device or emulator
- iOS: a Mac with Xcode (needed to build and to add the widget extension;
  see [iOS notes](#ios-notes))

### Commands

```bash
flutter pub get          # install dependencies
flutter run              # run on a connected device / emulator
flutter test             # run unit and widget tests
flutter analyze          # static analysis
flutter build apk        # Android release build (signed with the debug key)
```

## Platform notes

### Android notes

- Package / application ID: `com.example.just_reminder` (placeholder — change
  `applicationId` and `namespace` in `android/app/build.gradle.kts` and the
  Kotlin package before publishing).
- Release builds are signed with the debug key (Flutter's default); set up
  your own [signing configuration](https://docs.flutter.dev/deployment/android#sign-the-app)
  before publishing.
- Core library desugaring is enabled (required by
  `flutter_local_notifications`).
- Permissions: `POST_NOTIFICATIONS` (asked at runtime), `SCHEDULE_EXACT_ALARM`
  (the user grants _Alarms & reminders_), `RECEIVE_BOOT_COMPLETED` (to
  re-arm notifications and widget refreshes after a reboot).
- The widget is native (`android/app/src/main/kotlin/.../ReminderWidgetProvider.kt`
  with RemoteViews layouts in `res/layout`: `reminder_widget_small.xml` for
  1×1 and other small sizes, `reminder_widget.xml` from about 2×2). Picking
  its reminder runs a small Flutter screen in `WidgetConfigurationActivity`.
- The notification icon `res/drawable/ic_stat_reminder.xml` is kept in
  release builds by `res/raw/keep.xml`.
- Some manufacturers (e.g. Xiaomi, Huawei) stop background work
  aggressively; if notifications arrive late, allow the app to run in the
  background (see [dontkillmyapp.com](https://dontkillmyapp.com)).

### iOS notes

- Bundle ID: `com.example.justReminder` (placeholder — change it in Xcode
  before publishing, and the App Group with it).
- The app is set up for notifications (`ios/Runner/AppDelegate.swift`) and
  the `justreminder://` URL scheme (`Info.plist`).
- iOS keeps at most 64 scheduled notifications per app, so the app schedules
  the next ones and tops them up whenever it runs.

#### Adding the iOS widget extension (once, in Xcode on a Mac)

The widget's Swift code is in [`ios/ReminderWidget/`](ios/ReminderWidget/);
the Xcode target for it has to be created by hand. These files were written
on Windows and have not been compiled yet — build once in Xcode and fix
anything it reports.

1. Run `flutter pub get`, then open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Widget Extension.** Product name
   **`ReminderWidget`**. Uncheck _Include Live Activity_, _Include Control_
   and _Include Configuration App Intent_. Finish (and _Activate_ the
   scheme if asked).
3. Xcode adds template files to `ios/ReminderWidget/`. **Delete** its
   `ReminderWidget.swift` and `ReminderWidgetBundle.swift` (Move to Trash);
   keep `Assets.xcassets` and `Info.plist`. Make sure the repo's files —
   `JustReminderWidget.swift`, `JustReminderWidgetBundle.swift`,
   `ReminderConfiguration.swift`, `AcknowledgeReminderIntent.swift`,
   `NotificationCleanup.swift`, `WidgetStore.swift` — belong to the
   **ReminderWidgetExtension** target (Xcode 16 folders pick them up
   automatically; otherwise _Add Files to "Runner"…_ with only that target
   ticked).
4. Select the **ReminderWidgetExtension** target → _General_ → _Minimum
   Deployments_: **iOS 17.0** (interactive and configurable widgets).
5. **Version:** in the extension's _Build Settings_ set _Marketing Version_
   (`MARKETING_VERSION`) to `$(FLUTTER_BUILD_NAME)` and _Current Project
   Version_ (`CURRENT_PROJECT_VERSION`) to `$(FLUTTER_BUILD_NUMBER)`, and in
   _Project → Info → Configurations_ base the extension's Debug
   configuration on `Flutter/Debug.xcconfig` and Release/Profile on
   `Flutter/Release.xcconfig`, so its version always matches the app's.
6. **Signing and App Groups** (needs a paid Apple Developer account): for
   both the **Runner** and **ReminderWidgetExtension** targets, _Signing &
   Capabilities_ → pick your _Team_, then _+ Capability_ → _App Groups_ →
   add **`group.com.example.justReminder`**. It must match `iosAppGroupId`
   in `lib/src/core/app_constants.dart` and `WidgetStore.appGroup`. If Xcode
   won't register the `com.example.*` identifiers, change the bundle ID and
   the App Group (in Xcode and in both places above); the extension's bundle
   ID must stay `<app bundle ID>.ReminderWidget`.
7. Build and run (`flutter run`).
   - A build cycle involving _Thin Binary_: select the **Runner** target →
     _Build Phases_ and drag _Thin Binary_ to the bottom of the list.
   - Actor-isolation errors in the widget code: newer Xcode templates may
     set the extension's _Default Actor Isolation_ to _MainActor_; set it
     to _nonisolated_ (Build Settings → Swift Compiler – Concurrency) and
     keep the Swift 5 language mode.

**First test on an iPhone** (the parts that can't be checked on Windows):

1. Create a reminder a few minutes ahead, then **force-quit** the app. When
   the notification arrives, tap **Acknowledge**, wait a few seconds and
   reopen the app: the history must show that activation as acknowledged.
2. Add the widget and pick the reminder (long-press → **Edit Widget**). At
   the next activation it turns red on its own; tapping the thumbs down
   turns it green and clears the notification.
3. Tap the widget elsewhere: the reminder opens in the app.

The iOS widget needs no Flutter code: it reads the data the app stores in
the App Group and acknowledges with an App Intent that runs in the widget
extension.

## How it works

- **Everything stays on your device.** Reminders and their history live in
  a local [sembast](https://pub.dev/packages/sembast) database; nothing is
  sent anywhere.
- A **schedule engine** (pure Dart, fully unit-tested) computes every
  activation time from the reminder's schedule. Random times are derived
  from the reminder and the day, so they never change once picked.
- Acknowledging from the widget or a notification happens while the app may
  be closed. Those acknowledgments are logged with their time and applied
  to the history the next time the app runs, in the order they happened,
  so the history is always correct.
- After every change the app writes a small **snapshot** per reminder for
  the widgets (state + upcoming activation times) and reschedules the
  notifications. With the upcoming times the widget can turn red by itself
  at the right moment (Android redraws it at those times; iOS gets a
  timeline entry for each).

## Known limitations

- **iOS has not been compiled yet** (the code was written on Windows). Expect
  to fix small things in Xcode the first time.
- **Activations are planned ahead while the app runs.** Notifications cover
  the next 14 days, up to 200 on Android and 60 on iOS (which keeps at most
  64), with each reminder getting its next 3 first. The widgets know up to
  200 upcoming times per reminder. The app tops this up whenever it runs; with
  very frequent reminders (e.g. every 5 minutes) it lasts only hours, so open
  the app now and then.
- **Time zone changes:** notifications and widget redraws are scheduled as
  exact moments. After moving to another time zone, open the app once and
  they move to the new local times.
- Some Android manufacturers delay background work; see the
  [Android notes](#android-notes).

## Project structure

```text
lib/
  main.dart                 app entry point (+ Android widget configuration
                            entry point)
  src/
    app.dart                MaterialApp.router + Material You theme
    background/             Acknowledge from a widget / notification without
                            the app
    core/                   dates, times, stable hash, seeded random, ids
    domain/                 reminder & schedule models, schedule engine,
                            missed/acknowledged state machine, validation
    data/                   sembast database and repository
    services/               ReminderService (all changes + sync), ack log,
                            notifications/, widget/ (snapshots for widgets)
    state/                  Riverpod providers (data, clock, view models)
    ui/
      theme/                Material You theme + green/red status colors
      routing/              go_router configuration
      components/           thumb, cards, steppers, pickers, banners, …
      screens/              home, editor, details, archive, widget config
      sync_scope.dart       keeps data current; handles notification and
                            widget taps
test/                       unit and widget tests (core, domain, services, ui)
android/app/src/main/       widget provider + configuration activity
                            (Kotlin), widget layouts and resources
ios/ReminderWidget/         WidgetKit extension sources (Swift)
```
