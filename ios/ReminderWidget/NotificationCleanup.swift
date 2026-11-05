import Foundation
import UserNotifications

/// What the Dart side does after a Done outside the app
/// (`NotificationScheduler.afterDoneOutsideApp`), for Done on the iOS
/// widget: removes the reminder's shown notifications, cancels the
/// remaining notifications of the time that was done, and lowers "N missed"
/// by one on the same day's later times (they had counted it as missed).
///
/// flutter_local_notifications sets each notification's threadIdentifier to
/// the reminder id and keeps the payload in userInfo["payload"]: JSON with
/// `r` (reminder), `t` (when), `s` (start of its time), `m` (the "N missed"
/// it shows) and `h` — see notification_plan.dart.
enum NotificationCleanup {
  static func done(_ reminderId: String, occurrenceStart: Int64?) async {
    let center = UNUserNotificationCenter.current()

    let shown = await center.deliveredNotifications()
      .filter { $0.request.content.threadIdentifier == reminderId }
      .map { $0.request.identifier }
    if !shown.isEmpty {
      center.removeDeliveredNotifications(withIdentifiers: shown)
    }

    guard let occurrenceStart else { return }
    let doneDay = WidgetStore.date(fromMillis: occurrenceStart)
    var finished: [String] = []
    for request in await center.pendingNotificationRequests()
    where request.content.threadIdentifier == reminderId {
      guard var payload = decode(request) else { continue }
      let start = number(payload["s"]) ?? number(payload["t"])
      guard let start else { continue }
      if start == occurrenceStart {
        finished.append(request.identifier)
        continue
      }
      let missed = Int(number(payload["m"]) ?? 0)
      guard
        start > occurrenceStart,
        missed > 0,
        Calendar.current.isDate(WidgetStore.date(fromMillis: start), inSameDayAs: doneDay),
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
      else { continue }
      payload["m"] = missed - 1
      content.subtitle = missed - 1 == 0 ? "" : "\(missed - 1) missed"
      if let data = try? JSONSerialization.data(withJSONObject: payload),
        let raw = String(data: data, encoding: .utf8)
      {
        var userInfo = content.userInfo
        userInfo["payload"] = raw
        content.userInfo = userInfo
      }
      try? await center.add(
        UNNotificationRequest(
          identifier: request.identifier,
          content: content,
          trigger: request.trigger
        )
      )
    }
    if !finished.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: finished)
    }
  }

  private static func decode(_ request: UNNotificationRequest) -> [String: Any]? {
    guard
      let raw = request.content.userInfo["payload"] as? String,
      let data = raw.data(using: .utf8)
    else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func number(_ value: Any?) -> Int64? {
    (value as? NSNumber)?.int64Value
  }
}
