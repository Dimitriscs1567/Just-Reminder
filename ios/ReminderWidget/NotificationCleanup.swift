import Foundation
import UserNotifications

/// What the Dart side does after an acknowledgment outside the app, for
/// acknowledgments made on the iOS widget: removes the reminder's shown
/// notifications and re-numbers "N missed" on its upcoming ones.
///
/// flutter_local_notifications sets each notification's threadIdentifier to
/// the reminder id (see notification_service.dart).
enum NotificationCleanup {
  static func acknowledge(_ reminderId: String) async {
    let center = UNUserNotificationCenter.current()

    let shown = await center.deliveredNotifications()
      .filter { $0.request.content.threadIdentifier == reminderId }
      .map { $0.request.identifier }
    if !shown.isEmpty {
      center.removeDeliveredNotifications(withIdentifiers: shown)
    }

    let upcoming = await center.pendingNotificationRequests()
      .filter { $0.content.threadIdentifier == reminderId }
      .compactMap { request -> (request: UNNotificationRequest, date: Date)? in
        guard let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        else { return nil }
        return (request: request, date: date)
      }
      .sorted { $0.date < $1.date }

    for (rank, item) in upcoming.enumerated() {
      let subtitle = rank == 0 ? "" : "\(rank) missed"
      guard
        item.request.content.subtitle != subtitle,
        let content = item.request.content.mutableCopy() as? UNMutableNotificationContent
      else { continue }
      content.subtitle = subtitle
      let replacement = UNNotificationRequest(
        identifier: item.request.identifier,
        content: content,
        trigger: item.request.trigger
      )
      try? await center.add(replacement)
    }
  }
}
