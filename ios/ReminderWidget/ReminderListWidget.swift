import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ReminderListEntry: TimelineEntry {
  struct Row: Identifiable {
    let id: String
    let displayName: String
    let state: WidgetStore.State
  }

  let date: Date
  /// In the order the user picked them; nil when nothing is picked yet.
  let rows: [Row]?
}

struct ReminderListProvider: AppIntentTimelineProvider {
  /// The most entries handed to WidgetKit at once.
  private static let maxEntries = 100

  func placeholder(in context: Context) -> ReminderListEntry {
    ReminderListEntry(
      date: Date(),
      rows: [
        ReminderListEntry.Row(id: "water", displayName: "Water", state: .firing(missed: 1)),
        ReminderListEntry.Row(id: "stretch", displayName: "Stretch", state: .done(missed: 0)),
        ReminderListEntry.Row(id: "vitamins", displayName: "Vitamins", state: .missed(missed: 2)),
      ]
    )
  }

  func snapshot(for configuration: SelectRemindersIntent, in context: Context) async -> ReminderListEntry {
    let reminders = configuration.reminders ?? []
    if context.isPreview && reminders.isEmpty {
      return placeholder(in: context)
    }
    return entry(for: reminders, snapshots: reminders.map { WidgetStore.loadSnapshot($0.id) }, at: Date())
  }

  /// One entry now and one at each upcoming change of any of its
  /// reminders, so the rows change on time without the app running.
  func timeline(for configuration: SelectRemindersIntent, in context: Context) async -> Timeline<ReminderListEntry> {
    let now = Date()
    let reminders = configuration.reminders ?? []
    guard !reminders.isEmpty else {
      return Timeline(entries: [ReminderListEntry(date: now, rows: nil)], policy: .never)
    }
    let snapshots = reminders.map { WidgetStore.loadSnapshot($0.id) }
    if snapshots.contains(where: { $0 == nil }) {
      // The App Group can't be read yet (deleted reminders leave a
      // tombstone): try again soon.
      return Timeline(
        entries: [entry(for: reminders, snapshots: snapshots, at: now)],
        policy: .after(now.addingTimeInterval(15 * 60))
      )
    }
    let changes = Set(snapshots.compactMap { $0 }.flatMap(WidgetStore.changeTimes(of:)))
      .filter { $0 > now }
      .sorted()
      .prefix(Self.maxEntries - 1)
    let dates = [now] + Array(changes)
    let entries = dates.map { entry(for: reminders, snapshots: snapshots, at: $0) }
    let reload = changes.last.map { max($0, now.addingTimeInterval(3600)) }
      ?? now.addingTimeInterval(6 * 3600)
    return Timeline(entries: entries, policy: .after(reload))
  }

  private func entry(
    for reminders: [ReminderEntity],
    snapshots: [[String: Any]?],
    at date: Date
  ) -> ReminderListEntry {
    ReminderListEntry(
      date: date,
      rows: zip(reminders, snapshots).map { reminder, snapshot in
        ReminderListEntry.Row(
          id: reminder.id,
          displayName: snapshot?["displayName"] as? String ?? reminder.displayName,
          state: WidgetStore.state(of: snapshot, at: date)
        )
      }
    )
  }
}

// MARK: - View

struct ReminderListWidgetView: View {
  let entry: ReminderListEntry
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.widgetFamily) private var family

  /// Rows that fit (iOS widgets don't scroll); the rest is "+N more".
  private var capacity: Int { family == .systemLarge ? 8 : 3 }

  var body: some View {
    let surface = Palette.neutralTile(colorScheme)
    VStack(alignment: .leading, spacing: 4) {
      Text("Reminders")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Palette.onNeutral(colorScheme))
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
      if let rows = entry.rows {
        let shown = rows.count > capacity ? Array(rows.prefix(capacity - 1)) : rows
        ForEach(shown) { row in
          rowView(row, surface: surface)
        }
        if shown.count < rows.count {
          Text("+\(rows.count - shown.count) more")
            .font(.system(size: 12))
            .foregroundStyle(Palette.neutralVariant(colorScheme))
            .padding(.horizontal, 8)
        }
      } else {
        Text("Long-press and choose Edit Widget to pick reminders")
          .font(.caption)
          .foregroundStyle(Palette.neutralVariant(colorScheme))
          .padding(.horizontal, 6)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { surface }
  }

  /// State icon (the teal ring is the Done button), display name and status;
  /// the rest of the row opens the reminder.
  private func rowView(_ row: ReminderListEntry.Row, surface: Color) -> some View {
    let firing = row.state.isFiring
    let background = firing ? Palette.firingTile(colorScheme) : surface
    let name = firing
      ? Palette.onFiring(colorScheme)
      : row.state.isGone ? Palette.neutralVariant(colorScheme) : Palette.onNeutral(colorScheme)
    let status = firing ? Palette.onFiringVariant(colorScheme) : Palette.neutralVariant(colorScheme)
    return HStack(spacing: 8) {
      rowIcon(row, surface: background)
      Link(destination: (row.state.isGone ? WidgetLinks.help : WidgetLinks.reminder(row.id)) ?? URL(fileURLWithPath: "/")) {
        HStack(spacing: 8) {
          Text(row.displayName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(name)
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(statusText(row.state))
            .font(.system(size: 12))
            .foregroundStyle(status)
            .lineLimit(1)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
      }
    }
    .frame(height: 34)
    .padding(.leading, 4)
    .padding(.trailing, 10)
    .background(RoundedRectangle(cornerRadius: 14).fill(firing ? background : .clear))
  }

  @ViewBuilder
  private func rowIcon(_ row: ReminderListEntry.Row, surface: Color) -> some View {
    let drawing = StateIcon(
      state: row.state,
      size: 26,
      surface: surface,
      checkColor: Palette.neutralVariant(colorScheme)
    )
    .frame(width: 30, height: 30)
    if row.state.isFiring {
      Button(intent: AcknowledgeReminderIntent(reminderId: row.id)) { drawing }
        .buttonStyle(.plain)
        .accessibilityLabel("Done: \(row.displayName)")
    } else {
      drawing
    }
  }
}

// MARK: - Widget

struct ReminderListWidget: Widget {
  /// Must match WidgetBridge.iosListKind in Dart.
  static let kind = "ReminderListWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: Self.kind, intent: SelectRemindersIntent.self, provider: ReminderListProvider()) { entry in
      ReminderListWidgetView(entry: entry)
    }
    .configurationDisplayName("Reminders")
    .description("Several reminders at a glance, in the order you choose. When one is due, tap its thumbs-up to mark it done.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}
