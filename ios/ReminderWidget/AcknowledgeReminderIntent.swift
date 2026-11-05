import AppIntents
import WidgetKit

/// The widgets' Done button (iOS 17 interactive widgets). Runs in the
/// widget extension, so it works without starting the app: the app applies
/// the logged Done mark to its history the next time it runs. (The type
/// name predates the "Done" wording.)
struct AcknowledgeReminderIntent: AppIntent {
  static var title: LocalizedStringResource { "Mark reminder done" }
  static var description: IntentDescription { "Marks the reminder that is due as done." }
  static var isDiscoverable: Bool { false }

  @Parameter(title: "Reminder ID")
  var reminderId: String

  init() {}

  init(reminderId: String) {
    self.reminderId = reminderId
  }

  func perform() async throws -> some IntentResult {
    let finished = WidgetStore.markDone(reminderId, at: Date())
    await NotificationCleanup.done(reminderId, occurrenceStart: finished)
    // Every widget showing the same reminder, one-reminder and list ones.
    WidgetCenter.shared.reloadTimelines(ofKind: ReminderWidget.kind)
    WidgetCenter.shared.reloadTimelines(ofKind: ReminderListWidget.kind)
    return .result()
  }
}
