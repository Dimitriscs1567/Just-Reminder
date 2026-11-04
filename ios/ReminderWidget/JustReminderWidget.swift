import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ReminderEntry: TimelineEntry {
  enum Status: Equatable {
    case waiting(missed: Int)
    case clear
    case archived
    case deleted
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
    ReminderEntry(date: Date(), reminderId: nil, displayName: "Water", status: .clear)
  }

  func snapshot(for configuration: SelectReminderIntent, in context: Context) async -> ReminderEntry {
    if context.isPreview && configuration.reminder == nil {
      return placeholder(in: context)
    }
    return entry(for: configuration.reminder, at: Date())
  }

  /// One entry now and one at each upcoming activation, so the widget turns
  /// thumbs down on time without the app running.
  func timeline(for configuration: SelectReminderIntent, in context: Context) async -> Timeline<ReminderEntry> {
    let now = Date()
    guard let reminder = configuration.reminder else {
      return Timeline(entries: [entry(for: nil, at: now)], policy: .never)
    }
    let snapshot = WidgetStore.loadSnapshot(reminder.id)
    guard snapshot != nil else {
      // No data yet, e.g. before the first unlock after a restart, when the
      // App Group can't be read. A deleted reminder leaves a tombstone, so
      // try again soon instead of showing "Deleted" for hours.
      return Timeline(
        entries: [entry(for: reminder, snapshot: nil, at: now)],
        policy: .after(now.addingTimeInterval(15 * 60))
      )
    }
    let changes = (snapshot.map(WidgetStore.upcoming) ?? [])
      .map(WidgetStore.date(fromMillis:))
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
    let status: ReminderEntry.Status
    switch WidgetStore.status(of: snapshot, at: date) {
    case .waiting(let missed): status = .waiting(missed: missed)
    case .clear: status = .clear
    case .archived: status = .archived
    case .deleted: status = .deleted
    }
    return ReminderEntry(
      date: date,
      reminderId: reminder.id,
      displayName: snapshot?["displayName"] as? String ?? reminder.displayName,
      status: status
    )
  }
}

// MARK: - View

private enum Palette {
  static let positive = Color(rgb: 0x1E8E3E)
  static let negative = Color(rgb: 0xD93025)

  static func background(_ status: ReminderEntry.Status, _ scheme: ColorScheme) -> Color {
    let dark = scheme == .dark
    switch status {
    case .waiting: return Color(rgb: dark ? 0x5C1310 : 0xFFDAD6)
    case .clear: return Color(rgb: dark ? 0x13391F : 0xDCF5E3)
    default: return Color(rgb: dark ? 0x2B2930 : 0xF3EDF7)
    }
  }

  static func foreground(_ status: ReminderEntry.Status, _ scheme: ColorScheme) -> Color {
    let dark = scheme == .dark
    switch status {
    case .waiting: return Color(rgb: dark ? 0xFFDAD6 : 0x5C0B06)
    case .clear: return Color(rgb: dark ? 0xB7F1C7 : 0x00391A)
    default: return Color(rgb: dark ? 0xE6E0E9 : 0x1D1B20)
    }
  }
}

private extension Color {
  init(rgb: UInt32) {
    self.init(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }
}

struct ReminderWidgetView: View {
  let entry: ReminderEntry
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    // Sized so a 2-line name, the thumb and the "N missed" badge fit the
    // ~126 pt of a small widget (the name shrinks first when they don't).
    VStack(spacing: 6) {
      Text(entry.displayName)
        .font(.headline)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .foregroundStyle(Palette.foreground(entry.status, colorScheme))

      switch entry.status {
      case .waiting(let missed):
        if let reminderId = entry.reminderId {
          Button(intent: AcknowledgeReminderIntent(reminderId: reminderId)) {
            thumb(down: true)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Acknowledge")
        }
        if missed > 0 {
          Text("\(missed) missed")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.negative))
        }
      case .clear:
        thumb(down: false)
          .accessibilityLabel("All clear")
      case .archived:
        label("Archived")
      case .deleted:
        label("Deleted")
      case .unconfigured:
        label("Long-press and choose Edit Widget to pick a reminder")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .containerBackground(for: .widget) {
      Palette.background(entry.status, colorScheme)
    }
    .widgetURL(url)
  }

  private func thumb(down: Bool) -> some View {
    Image(systemName: down ? "hand.thumbsdown.fill" : "hand.thumbsup.fill")
      .font(.system(size: 24, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 52, height: 52)
      .background(Circle().fill(down ? Palette.negative : Palette.positive))
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .multilineTextAlignment(.center)
      .foregroundStyle(Palette.foreground(entry.status, colorScheme))
  }

  /// Taps outside the button open the reminder in the app; for an archived
  /// or deleted reminder the app explains how to pick another one. The
  /// `homeWidget` parameter lets home_widget recognize widget links.
  private var url: URL? {
    switch entry.status {
    case .waiting, .clear:
      guard let reminderId = entry.reminderId else { return nil }
      return URL(string: "justreminder://reminder/\(reminderId)?homeWidget")
    case .archived, .deleted:
      return URL(string: "justreminder://widget-help?homeWidget")
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
    .description("One reminder at a glance: thumbs up when all is clear, thumbs down when it needs you. Tap the thumbs down to acknowledge.")
    .supportedFamilies([.systemSmall])
  }
}
