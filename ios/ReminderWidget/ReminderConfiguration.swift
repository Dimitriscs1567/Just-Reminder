import AppIntents
import WidgetKit

/// A reminder that a widget can show (from the app's widget index).
struct ReminderEntity: AppEntity {
  let id: String
  let name: String
  let displayName: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Reminder" }
  static var defaultQuery: ReminderQuery { ReminderQuery() }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(displayName)", subtitle: "\(name)")
  }
}

struct ReminderQuery: EntityQuery {
  func entities(for identifiers: [ReminderEntity.ID]) async throws -> [ReminderEntity] {
    let index = WidgetStore.index()
    return identifiers.map { id in
      if let entry = index.first(where: { $0.id == id }) {
        return ReminderEntity(id: entry.id, name: entry.name, displayName: entry.displayName)
      }
      // Deleted: keep the widget's choice so it can say "Deleted".
      let snapshot = WidgetStore.loadSnapshot(id)
      return ReminderEntity(
        id: id,
        name: snapshot?["name"] as? String ?? "",
        displayName: snapshot?["displayName"] as? String ?? "Deleted reminder"
      )
    }
  }

  /// The reminders offered when choosing (archived ones are left out).
  func suggestedEntities() async throws -> [ReminderEntity] {
    WidgetStore.index()
      .filter { !$0.archived }
      .map { ReminderEntity(id: $0.id, name: $0.name, displayName: $0.displayName) }
  }

  func defaultResult() async -> ReminderEntity? {
    try? await suggestedEntities().first
  }
}

/// The widget's setting: which reminder it shows (long-press → Edit Widget).
struct SelectReminderIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Choose reminder" }
  static var description: IntentDescription { "Pick the reminder this widget shows." }

  @Parameter(title: "Reminder")
  var reminder: ReminderEntity?

  init() {}
}
