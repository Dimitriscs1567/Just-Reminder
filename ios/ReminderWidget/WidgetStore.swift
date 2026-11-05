import Foundation

/// Reads and updates what the Flutter app stores for the widgets in the App
/// Group's UserDefaults (written with home_widget).
///
/// Mirrors lib/src/services/widget_storage_keys.dart and
/// lib/src/services/widget/widget_snapshot.dart — change them together.
enum WidgetStore {
  static let appGroup = "group.com.example.justReminder"
  static let indexKey = "jr.reminders"
  static let maxAcknowledgments = 50

  static func snapshotKey(_ reminderId: String) -> String { "jr.reminder.\(reminderId)" }
  static func acknowledgmentsKey(_ reminderId: String) -> String { "jr.acks.\(reminderId)" }

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  struct IndexEntry {
    let id: String
    let name: String
    let displayName: String
    let archived: Bool
  }

  enum Status: Equatable {
    case waiting(missed: Int)
    case clear
    case archived
    case deleted
  }

  /// All reminders the app knows (not deleted ones).
  static func index() -> [IndexEntry] {
    guard let items = json(forKey: indexKey) as? [[String: Any]] else { return [] }
    return items.compactMap { item in
      guard let id = item["id"] as? String else { return nil }
      return IndexEntry(
        id: id,
        name: item["name"] as? String ?? "",
        displayName: item["displayName"] as? String ?? "",
        archived: item["archived"] as? Bool ?? false
      )
    }
  }

  static func loadSnapshot(_ reminderId: String) -> [String: Any]? {
    json(forKey: snapshotKey(reminderId)) as? [String: Any]
  }

  /// Activations after the snapshot was taken (epoch ms).
  static func upcoming(_ snapshot: [String: Any]) -> [Int64] {
    (snapshot["upcoming"] as? [Any] ?? []).compactMap(int64)
  }

  /// What the widget shows at `date`:
  /// waiting = (pendingAt != null ? 1 + missedCount : 0)
  ///         + activations in (asOf, date].
  static func status(of snapshot: [String: Any]?, at date: Date) -> Status {
    guard let snapshot else { return .deleted }
    switch snapshot["state"] as? String {
    case "deleted": return .deleted
    case "archived": return .archived
    default: break
    }
    let asOf = int64(snapshot["asOf"]) ?? 0
    let now = millis(date)
    let isPending = snapshot["pendingAt"].map { !($0 is NSNull) } ?? false
    let base = isPending ? 1 + Int(int64(snapshot["missedCount"]) ?? 0) : 0
    let due = upcoming(snapshot).filter { $0 > asOf && $0 <= now }.count
    let total = base + due
    return total > 0 ? .waiting(missed: total - 1) : .clear
  }

  /// Marks the reminder done from the widget, like `markDoneInBackground`
  /// in Dart: logs it for the app's next sync and marks nothing as due.
  /// Returns the start (epoch ms) of the time it finished, if one was due
  /// (`dueOccurrenceStartAt` in Dart), for `NotificationCleanup`.
  @discardableResult
  static func markDone(_ reminderId: String, at date: Date) -> Int64? {
    let now = millis(date)

    var acknowledgments = (json(forKey: acknowledgmentsKey(reminderId)) as? [Any] ?? [])
      .compactMap(int64)
    acknowledgments.append(now)
    acknowledgments.sort()
    if acknowledgments.count > maxAcknowledgments {
      acknowledgments = Array(acknowledgments.suffix(maxAcknowledgments))
    }
    setJSON(acknowledgments, forKey: acknowledgmentsKey(reminderId))

    guard var snapshot = loadSnapshot(reminderId) else { return nil }
    let finished = dueOccurrenceStart(snapshot, at: now)
    snapshot["asOf"] = now
    snapshot["pendingAt"] = NSNull()
    snapshot["missedCount"] = 0
    snapshot["pending"] = NSNull()
    snapshot["upcoming"] = upcoming(snapshot).filter { $0 > now }
    snapshot["occurrences"] = occurrences(snapshot).filter { (int64($0["due"]) ?? 0) > now }
    setJSON(snapshot, forKey: snapshotKey(reminderId))
    return finished
  }

  /// The start of the latest time due at `now` (the snapshot's `pending`
  /// or one of its `occurrences`), unless it was already missed.
  static func dueOccurrenceStart(_ snapshot: [String: Any], at now: Int64) -> Int64? {
    var candidates = occurrences(snapshot)
    if let pending = snapshot["pending"] as? [String: Any] { candidates.append(pending) }
    let latest = candidates
      .filter { (int64($0["due"]) ?? Int64.max) <= now }
      .max { (int64($0["due"]) ?? 0) < (int64($1["due"]) ?? 0) }
    guard let latest else { return nil }
    if let missesAt = int64(latest["missesAt"]), missesAt <= now { return nil }
    return int64(latest["start"])
  }

  private static func occurrences(_ snapshot: [String: Any]) -> [[String: Any]] {
    snapshot["occurrences"] as? [[String: Any]] ?? []
  }

  static func date(fromMillis value: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(value) / 1000)
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  private static func int64(_ value: Any?) -> Int64? {
    (value as? NSNumber)?.int64Value
  }

  private static func json(forKey key: String) -> Any? {
    guard let raw = defaults?.string(forKey: key), let data = raw.data(using: .utf8) else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data)
  }

  private static func setJSON(_ value: Any, forKey key: String) {
    guard
      JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value),
      let raw = String(data: data, encoding: .utf8)
    else { return }
    defaults?.set(raw, forKey: key)
  }
}
