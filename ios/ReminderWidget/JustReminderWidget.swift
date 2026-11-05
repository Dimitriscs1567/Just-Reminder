import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ReminderEntry: TimelineEntry {
  enum Status: Equatable {
    case reminder(WidgetStore.State)
    case unconfigured
  }

  let date: Date
  let reminderId: String?
  let displayName: String
  let status: Status
}

struct ReminderProvider: AppIntentTimelineProvider {
  /// The most entries handed to WidgetKit at once.
  private static let maxEntries = 100

  func placeholder(in context: Context) -> ReminderEntry {
    ReminderEntry(date: Date(), reminderId: nil, displayName: "Water", status: .reminder(.firing(missed: 0)))
  }

  func snapshot(for configuration: SelectReminderIntent, in context: Context) async -> ReminderEntry {
    if context.isPreview && configuration.reminder == nil {
      return placeholder(in: context)
    }
    return entry(for: configuration.reminder, at: Date())
  }

  /// One entry now and one at each upcoming change (a time due or missed,
  /// midnight), so the widget changes on time without the app running.
  func timeline(for configuration: SelectReminderIntent, in context: Context) async -> Timeline<ReminderEntry> {
    let now = Date()
    guard let reminder = configuration.reminder else {
      return Timeline(entries: [entry(for: nil, at: now)], policy: .never)
    }
    guard let snapshot = WidgetStore.loadSnapshot(reminder.id) else {
      // No data yet, e.g. before the first unlock after a restart, when the
      // App Group can't be read. A deleted reminder leaves a tombstone, so
      // try again soon instead of showing "Deleted" for hours.
      return Timeline(
        entries: [entry(for: reminder, snapshot: nil, at: now)],
        policy: .after(now.addingTimeInterval(15 * 60))
      )
    }
    let changes = WidgetStore.changeTimes(of: snapshot)
      .filter { $0 > now }
      .prefix(Self.maxEntries - 1)
    let dates = [now] + Array(changes)
    let entries = dates.map { entry(for: reminder, snapshot: snapshot, at: $0) }
    // Ask again after the last change (the app also reloads after changes).
    let reload = changes.last.map { max($0, now.addingTimeInterval(3600)) }
      ?? now.addingTimeInterval(6 * 3600)
    return Timeline(entries: entries, policy: .after(reload))
  }

  private func entry(for reminder: ReminderEntity?, at date: Date) -> ReminderEntry {
    guard let reminder else {
      return ReminderEntry(date: date, reminderId: nil, displayName: "Just Reminder", status: .unconfigured)
    }
    return entry(for: reminder, snapshot: WidgetStore.loadSnapshot(reminder.id), at: date)
  }

  private func entry(for reminder: ReminderEntity, snapshot: [String: Any]?, at date: Date) -> ReminderEntry {
    ReminderEntry(
      date: date,
      reminderId: reminder.id,
      displayName: snapshot?["displayName"] as? String ?? reminder.displayName,
      status: .reminder(WidgetStore.state(of: snapshot, at: date))
    )
  }
}

// MARK: - View

struct ReminderWidgetView: View {
  let entry: ReminderEntry
  @Environment(\.colorScheme) private var colorScheme

  private var state: WidgetStore.State? {
    if case .reminder(let state) = entry.status { return state }
    return nil
  }

  var body: some View {
    let current = self.state ?? .deleted
    let tile = Palette.tile(current, colorScheme)
    let text = Palette.onTile(current, colorScheme)
    // Sized so the icon and a 2-line name fit the ~126 pt of a small widget
    // (the name shrinks first when they don't).
    VStack(spacing: 8) {
      switch entry.status {
      case .reminder(let state) where !state.isGone:
        icon(state, surface: tile, text: text)
        name(text)
      case .reminder(.archived):
        name(text)
        label("Archived", text)
      case .reminder:
        name(text)
        label("Deleted", text)
      case .unconfigured:
        label("Long-press and choose Edit Widget to pick a reminder", text)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .topTrailing) {
      if current.missedCount > 0 {
        MissedBubble(count: current.missedCount)
      }
    }
    .containerBackground(for: .widget) { tile }
    .widgetURL(url)
  }

  @ViewBuilder
  private func icon(_ state: WidgetStore.State, surface: Color, text: Color) -> some View {
    let drawing = StateIcon(state: state, size: 52, surface: surface, checkColor: text.opacity(0.8))
    if state.isFiring, let reminderId = entry.reminderId {
      Button(intent: AcknowledgeReminderIntent(reminderId: reminderId)) { drawing }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
    } else {
      drawing
    }
  }

  private func name(_ color: Color) -> some View {
    Text(entry.displayName)
      .font(.system(size: 15, weight: .medium))
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
      .foregroundStyle(color)
  }

  private func label(_ text: String, _ color: Color) -> some View {
    Text(text)
      .font(.caption)
      .multilineTextAlignment(.center)
      .foregroundStyle(color.opacity(0.8))
  }

  /// Taps outside the button open the reminder in the app; for an archived
  /// or deleted reminder the app explains how to pick another one.
  private var url: URL? {
    switch entry.status {
    case .reminder(let state) where state.isGone:
      return WidgetLinks.help
    case .reminder:
      return entry.reminderId.flatMap(WidgetLinks.reminder)
    case .unconfigured:
      return nil
    }
  }
}

// MARK: - Widget

struct ReminderWidget: Widget {
  /// Must match WidgetBridge.iosKind in Dart.
  static let kind = "ReminderWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: Self.kind, intent: SelectReminderIntent.self, provider: ReminderProvider()) { entry in
      ReminderWidgetView(entry: entry)
    }
    .configurationDisplayName("Reminder")
    .description("One reminder at a glance. When it is due, tap the thumbs-up to mark it done.")
    .supportedFamilies([.systemSmall])
  }
}
