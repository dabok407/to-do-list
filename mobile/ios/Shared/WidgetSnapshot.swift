import Foundation

/// A read-only projection of the local database. The widget never changes the database.
struct WidgetTask: Codable, Equatable, Identifiable {
  let id: String
  let title: String
  let due: Double
  let priority: Int
  let status: String
  let smallStep: String?
  let taskId: String?
  let expiresAt: Double?

  init(id: String, title: String, due: Double, priority: Int, status: String, smallStep: String?, taskId: String? = nil, expiresAt: Double? = nil) {
    self.id = id
    self.title = title
    self.due = due
    self.priority = priority
    self.status = status
    self.smallStep = smallStep
    self.taskId = taskId
    self.expiresAt = expiresAt
  }

  var dueDate: Date { Date(timeIntervalSince1970: due / 1000) }
  var isActive: Bool { ["pending", "paused", "progressing"].contains(status) }

  func isVisible(at now: Date) -> Bool {
    guard isActive else { return false }
    if status == "pending", let expiry = expiresAt {
      return now.timeIntervalSince1970 * 1000 < expiry
    }
    return true
  }

  func url(action: String = "open") -> URL {
    var components = URLComponents()
    components.scheme = "hangeoreum"
    components.host = "task"
    components.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "action", value: action)]
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url!
  }
}

struct WidgetSnapshot: Codable {
  let tasks: [WidgetTask]
  let updatedAt: Double

  static let empty = WidgetSnapshot(tasks: [], updatedAt: 0)

  /// Keep in-progress work visible, then overdue priority, then the closest upcoming task.
  func visibleTasks(at now: Date, limit: Int = 3) -> [WidgetTask] {
    let unique = tasks.reduce(into: [String: WidgetTask]()) { result, task in
      if task.isVisible(at: now) { result[task.id] = task }
    }
    let sorted = unique.values.sorted { left, right in
      if (left.status == "progressing") != (right.status == "progressing") {
        return left.status == "progressing"
      }
      let leftOverdue = left.dueDate <= now
      let rightOverdue = right.dueDate <= now
      if leftOverdue != rightOverdue { return leftOverdue }
      if leftOverdue && left.priority != right.priority { return left.priority > right.priority }
      if left.due != right.due { return left.due < right.due }
      if left.priority != right.priority { return left.priority > right.priority }
      return left.id < right.id
    }
    var seenTaskIds = Set<String>()
    return Array(sorted.filter { seenTaskIds.insert($0.taskId ?? $0.id).inserted }.prefix(max(0, limit)))
  }
}

enum WidgetSnapshotStore {
  static let appGroup = "group.com.dabok407.hangeoreum"
  static let key = "widget_snapshot_v1"

  static func read() -> WidgetSnapshot {
    guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
          let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
    return snapshot
  }

  static func write(tasks: [[String: Any]]) throws {
    let json: [String: Any] = ["tasks": tasks, "updatedAt": Date().timeIntervalSince1970 * 1000]
    let data = try JSONSerialization.data(withJSONObject: json)
    // Reject incompatible snapshots instead of making the widget silently empty.
    _ = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      throw NSError(domain: "WidgetSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group storage is unavailable"])
    }
    defaults.set(data, forKey: key)
    if var container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? container.setResourceValues(values)
    }
  }
}

enum WidgetLaunch {
  static func isValid(_ url: URL) -> Bool {
    guard url.scheme == "hangeoreum", url.host == "task",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
          !id.isEmpty else { return false }
    let action = components.queryItems?.first(where: { $0.name == "action" })?.value ?? "open"
    return ["open", "start", "snooze"].contains(action)
  }
}
