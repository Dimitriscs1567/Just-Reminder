# Just Reminder

A simple, beautiful reminder app for **Android and iOS**, built with Flutter.
Set up reminders that fire once or on a repeating schedule, at a fixed time or
inside a time range, and see at a glance on your home screen whether something
needs your attention:

- 👍 **green** — nothing is waiting for you
- 👎 **red** — a reminder fired and is waiting to be acknowledged

A reminder stays active until you acknowledge it — in the app, on the home
screen widget, or with the **Acknowledge** button on its notification.

> **Status:** early development. See [Roadmap](#roadmap) for what is already
> implemented.

## Features

### Reminders

Each reminder has:

| Field | Required | Where it is shown |
| --- | --- | --- |
| **Name** | yes | In the app (lists, details) |
| **Display name** | yes | On the home screen widget and as the notification title |
| **Description** | no | In the app and as the notification text |

### Scheduling

**When it happens**

- **Once** — on a specific date.
- **Repeat**
  - **Daily** — every *N* days (every day, every 3 days, …).
  - **Weekly** — every *N* weeks on the weekdays you pick (e.g. Mon–Fri, or
    only Sat & Sun every 2 weeks).
  - **Monthly** — every *N* months on a day of the month (e.g. the 15th). A
    day that a month doesn't have (29th–31st) falls on that month's **last
    day** (e.g. "the 31st" fires on Apr 30 and Feb 28/29).
  - Starts on a start date, with an optional **end date**.

**What time**

- **Fixed time** — e.g. 09:00.
- **Time range** — e.g. 09:00–17:00. An end time before the start time runs
  past midnight (e.g. 22:00–02:00). Inside the range, choose:
  - **Interval** — every *X* minutes from the start of the range, until the
    range ends, or until the optional *max activations* is reached.
  - **Random** — exactly *N* activations at random times. The range is split
    into *N* equal slots with one random time in each, so activations never
    bunch up. The times are fixed per day, so they don't move when the app
    restarts.
- *Max activations* always counts **per window** (e.g. per day).
- A one-time reminder with a time range stays within its date (or runs past
  midnight as above).

While you set up a reminder, a **schedule preview** shows its next activation
times, so you can check it is right.

### Activation, acknowledgment and history

- When a reminder activates you get a notification (title = display name,
  text = description) with an **Acknowledge** button, and the reminder turns
  red (👎) in the app and on its widget.
- Swiping the notification away only hides it; the reminder **stays active**
  until you acknowledge it.
- If a new activation arrives while the previous one is still unacknowledged,
  you are notified again. The previous one is recorded as **missed** in the
  history, and the app and widget show how many were missed until you
  acknowledge the current one.
- Every activation is kept in the reminder's **history** (acknowledged with
  time / missed / active). History is kept forever.
- In interval mode an activation that lands exactly on the range end counts
  (09:00–17:00 every 60 min → 9 activations).

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
  (red), and a **"N missed"** badge while missed activations are waiting.
- Tap the thumbs down to acknowledge right from the home screen.
- If the reminder is archived or deleted, the widget shows an "Archived" or
  "Deleted" label instead of the thumb; tap it (Android) or long-press → Edit
  Widget (iOS) to pick another reminder.

### Look and feel

Material 3 with **Material You**: on Android 12+ the app uses your wallpaper
colors; elsewhere it falls back to an indigo & teal palette. Light and dark
mode follow the phone's setting. Positive is always green and negative always
red. The UI is in English; 12/24-hour time follows the phone's setting.

## Tech stack

| Concern | Package |
| --- | --- |
| UI | Flutter 3.47 with [`material_ui`](https://pub.dev/packages/material_ui) (Flutter's Material library, now a separate package) |
| State management | [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3 |
| Navigation | [`go_router`](https://pub.dev/packages/go_router) |
| Local database | [`sembast`](https://pub.dev/packages/sembast) |
| Home screen widgets | [`home_widget`](https://pub.dev/packages/home_widget) (+ native Kotlin / Swift widget code) |
| Notifications | [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) + [`timezone`](https://pub.dev/packages/timezone) |
| Material You colors | [`dynamic_color`](https://pub.dev/packages/dynamic_color) |
| Helpers | [`path_provider`](https://pub.dev/packages/path_provider), [`intl`](https://pub.dev/packages/intl) |

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
flutter build apk        # Android release build
```

## Platform notes

### Android notes

- Package / application ID: `com.example.just_reminder` (placeholder — change
  `applicationId` and `namespace` in `android/app/build.gradle.kts` before
  publishing).
- Core library desugaring is enabled (required by
  `flutter_local_notifications`).
- More details (notification and exact-alarm permissions, widget setup) will
  follow with the notifications and widget step.

### iOS notes

- Bundle ID: `com.example.justReminder` (placeholder — change it in Xcode
  before publishing).
- The home screen widget is a WidgetKit extension that has to be added in
  Xcode on a Mac. Step-by-step instructions will be added with the widget
  step.

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

## Project structure

```text
lib/
  main.dart                 app entry point (opens the database)
  src/
    app.dart                MaterialApp.router + Material You theme
    core/                   dates, times, stable hash, seeded random, ids
    domain/                 reminder & schedule models, schedule engine,
                            missed/acknowledged state machine, validation
    data/                   sembast database and repository
    services/               ReminderService (all changes + sync), ack log
    state/                  Riverpod providers
    ui/
      routing/              go_router configuration
      screens/              app screens
test/                       unit and widget tests (core, domain, services)
android/, ios/              platform projects (native widget code lives here)
```

## Roadmap

- [x] Project scaffold, dependencies, Android build configuration
- [x] Reminder model, schedule engine and sembast storage
- [ ] Theme and screens (list, editor with schedule preview, details &
  history, archive)
- [ ] Notifications with Acknowledge action
- [ ] Home screen widgets (Android + iOS)
- [ ] Final tests and documentation pass
