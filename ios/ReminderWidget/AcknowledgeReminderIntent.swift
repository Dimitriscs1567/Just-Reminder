import AppIntents
import WidgetKit

/// The widget's thumbs-down button (iOS 17 interactive widgets). Runs in the
/// widget extension, so it works without starting the app: the app applies
/// the logged acknowledgment to its history the next time it runs.
struct AcknowledgeReminderIntent: AppIntent {
  static var title: LocalizedStringResource { "Acknowledge reminder" }
  static var description: IntentDescription { "Marks the reminder's waiting activation as done." }
  static var isDiscoverable: Bool { false }

  @Parameter(title: "Reminder ID")
  var reminderId: String

  init() {}

  init(reminderId: String) {
    self.reminderId = reminderId
  }

  func perform() async throws -> some IntentResult {
    WidgetStore.acknowledge(reminderId, at: Date())
    await NotificationCleanup.acknowledge(reminderId)
    // Other widgets showing the same reminder.
    WidgetCenter.shared.reloadTimelines(ofKind: ReminderWidget.kind)
    return .result()
  }
}
