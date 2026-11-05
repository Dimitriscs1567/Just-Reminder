import Foundation

/// Reads and updates what the Flutter app stores for the widgets in the App
/// Group's UserDefaults (written with home_widget), and works out what a
/// reminder shows at a given moment.
///
/// Mirrors lib/src/services/widget_storage_keys.dart and
/// lib/src/services/widget/widget_snapshot.dart (`widgetStatusAt`,
/// `widgetChangeTimes`, `doneWidgetSnapshot`) — change them together.
enum WidgetStore {
  static let appGroup = "group.com.example.justReminder"
  static let indexKey = "jr.reminders"
  static let maxAcknowledgments = 50
  /// How far ahead a snapshot lists times (`widgetSnapshotHorizon`).
  static let horizonDays = 14

  static func snapshotKey(_ reminderId: String) -> String { "jr.reminder.\(reminderId)" }
  static func acknowledgmentsKey(_ reminderId: String) -> String { "jr.acks.\(reminderId)" }

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  struct IndexEntry {
    let id: String
    let name: String
    let displayName: String
    let archived: Bool
  }

  /// What a widget shows for a reminder; `missed` is the day's missed count
  /// (while firing: of the due time's day).
  enum State: Equatable {
    case firing(missed: Int)
    case missed(missed: Int)
    case done(missed: Int)
    case paused(missed: Int)
    case archived
    case deleted

    var missedCount: Int {
      switch self {
      case .firing(let missed), .missed(let missed), .done(let missed), .paused(let missed):
        return missed
      case .archived, .deleted:
        return 0
      }
    }

    var isFiring: Bool {
      if case .firing = self { return true }
      return false
    }

    var isGone: Bool { self == .archived || self == .deleted }
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

  /// What the widget shows at `date`: the snapshot's runtime with the times
  /// due or missed since it was taken; a new day starts clean.
  static func state(of snapshot: [String: Any]?, at date: Date) -> State {
    guard let snapshot else { return .deleted }
    let kind = snapshot["state"] as? String
    switch kind {
    case "deleted": return .deleted
    case "archived": return .archived
    default: break
    }
    let replay = Replay(snapshot, until: millis(date))
    if let pending = replay.pending {
      return .firing(missed: replay.missedOn(pending.date))
    }
    let today = localDate(millis(date))
    let missed = replay.missedOn(today)
    if kind == "paused" { return .paused(missed: missed) }
    return replay.lastDate == today && replay.lastMissed ? .missed(missed: missed) : .done(missed: missed)
  }

  /// When the widget may change without the app: times becoming due or
  /// being missed, and every midnight (a new day starts clean).
  static func changeTimes(of snapshot: [String: Any]) -> [Date] {
    switch snapshot["state"] as? String {
    case "archived", "deleted": return []
    default: break
    }
    let asOf = int64(snapshot["asOf"]) ?? 0
    var times = Set<Int64>()
    func add(_ time: Int64?) {
      if let time, time > asOf { times.insert(time) }
    }
    add(Time(snapshot["pending"])?.missesAt)
    for time in WidgetStore.times(snapshot["occurrences"]) {
      add(time.due)
      add(time.missesAt)
    }
    let startOfDay = calendar.startOfDay(for: date(fromMillis: asOf))
    for days in 1...(horizonDays + 1) {
      if let midnight = calendar.date(byAdding: .day, value: days, to: startOfDay) {
        add(millis(midnight))
      }
    }
    return times.sorted().map(date(fromMillis:))
  }

  /// Marks the reminder done from a widget, like `markDoneInBackground` in
  /// Dart: logs it for the app's next sync and, if a time is due, rewrites
  /// the snapshot with it done (the day's missed count stays). Returns the
  /// start (epoch ms) of the time it finished, for `NotificationCleanup`.
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

    guard var snapshot = loadSnapshot(reminderId), state(of: snapshot, at: date).isFiring else {
      return nil
    }
    var replay = Replay(snapshot, until: now)
    let finished = replay.pending?.start
    replay.done(at: now)
    // Version 1 fields, replaced by the ones below.
    for key in ["pendingAt", "missedCount", "upcoming"] { snapshot.removeValue(forKey: key) }
    snapshot["v"] = 2
    snapshot["asOf"] = now
    for (key, value) in replay.json { snapshot[key] = value }
    snapshot["occurrences"] = times(snapshot["occurrences"]).filter { $0.due > now }.map(\.json)
    setJSON(snapshot, forKey: snapshotKey(reminderId))
    return finished
  }

  // MARK: - Replay

  /// One time of a reminder in a snapshot (epoch ms; date `YYYY-MM-DD`).
  struct Time {
    let date: String
    let start: Int64
    let due: Int64
    let missesAt: Int64?

    init?(_ json: Any?) {
      guard
        let json = json as? [String: Any],
        let start = WidgetStore.int64(json["start"]),
        let due = WidgetStore.int64(json["due"])
      else { return nil }
      self.start = start
      self.due = due
      missesAt = WidgetStore.int64(json["missesAt"])
      // Version 1 snapshots have no dates: a time belongs to the day it
      // starts on.
      let date = json["date"] as? String ?? ""
      self.date = date.isEmpty ? WidgetStore.localDate(start) : date
    }

    var json: [String: Any] {
      [
        "date": date,
        "start": NSNumber(value: start),
        "due": NSNumber(value: due),
        "missesAt": missesAt.map { NSNumber(value: $0) as Any } ?? NSNull(),
      ]
    }
  }

  static func times(_ json: Any?) -> [Time] {
    (json as? [Any] ?? []).compactMap { Time($0) }
  }

  /// The snapshot's runtime brought forward to `until`: times becoming due,
  /// misses at their `missesAt`, in time order (a miss first at the same
  /// instant); a due time replacing a still pending one misses that one.
  /// Each miss counts for the day its time belongs to.
  struct Replay {
    var pending: Time?
    var missedDate: String?
    var missedCount = 0
    var lastDate: String?
    var lastStart: Int64?
    var lastMissed = false
    var lastAt: Int64?

    init(_ snapshot: [String: Any], until: Int64) {
      pending = Time(snapshot["pending"])
      if let missed = snapshot["missed"] as? [String: Any], let date = missed["date"] as? String {
        missedDate = date
        missedCount = Int(WidgetStore.int64(missed["count"]) ?? 0)
      }
      if let last = snapshot["last"] as? [String: Any] {
        lastDate = last["date"] as? String
        lastStart = WidgetStore.int64(last["start"])
        lastMissed = last["status"] as? String == "missed"
        lastAt = WidgetStore.int64(last["at"])
      }

      let asOf = WidgetStore.int64(snapshot["asOf"]) ?? 0
      // (instant, 0 = missed / 1 = due, time)
      var events: [(at: Int64, kind: Int, time: Time)] = []
      if let due = pending, let missesAt = due.missesAt, missesAt <= until {
        events.append((missesAt, 0, due))
      }
      for time in WidgetStore.times(snapshot["occurrences"]) where time.due > asOf && time.due <= until {
        events.append((time.due, 1, time))
        if let missesAt = time.missesAt, missesAt <= until {
          events.append((missesAt, 0, time))
        }
      }
      let ordered = events.enumerated().sorted { a, b in
        (a.element.at, a.element.kind, a.offset) < (b.element.at, b.element.kind, b.offset)
      }
      for (_, event) in ordered {
        if event.kind == 0 {
          if pending?.start == event.time.start { miss(at: event.at) }
        } else {
          if pending != nil { miss(at: event.at) }
          pending = event.time
        }
      }
    }

    func missedOn(_ date: String) -> Int { missedDate == date ? missedCount : 0 }

    mutating func miss(at instant: Int64) {
      guard let missed = pending else { return }
      if let counted = missedDate {
        if counted == missed.date {
          missedCount += 1
        } else if missed.date > counted {
          missedDate = missed.date
          missedCount = 1
        }
      } else {
        missedDate = missed.date
        missedCount = 1
      }
      finish(missed, missed: true, at: instant)
    }

    /// Done at `instant`: finishes the due time, if any.
    mutating func done(at instant: Int64) {
      guard let due = pending, due.due <= instant else { return }
      finish(due, missed: false, at: instant)
    }

    private mutating func finish(_ time: Time, missed: Bool, at instant: Int64) {
      lastDate = time.date
      lastStart = time.start
      lastMissed = missed
      lastAt = instant
      pending = nil
    }

    var json: [String: Any] {
      var missed: Any = NSNull()
      if let missedDate, missedCount > 0 {
        missed = ["date": missedDate, "count": missedCount] as [String: Any]
      }
      var last: Any = NSNull()
      if let lastDate {
        last = [
          "date": lastDate,
          "start": lastStart.map { NSNumber(value: $0) as Any } ?? NSNull(),
          "status": lastMissed ? "missed" : "done",
          "at": lastAt.map { NSNumber(value: $0) as Any } ?? NSNull(),
        ] as [String: Any]
      }
      return ["pending": pending?.json ?? NSNull(), "missed": missed, "last": last]
    }
  }

  // MARK: - Helpers

  /// Gregorian in the device's time zone, like Dart's `DateTime`.
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  /// The local date of `millis` as `YYYY-MM-DD` (Dart's `LocalDate.toIso`).
  static func localDate(_ millis: Int64) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date(fromMillis: millis))
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static func date(fromMillis value: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(value) / 1000)
  }

  static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  static func int64(_ value: Any?) -> Int64? {
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
