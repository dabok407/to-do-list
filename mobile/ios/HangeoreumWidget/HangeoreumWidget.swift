import SwiftUI
import WidgetKit

struct HangeoreumProvider: TimelineProvider {
  func placeholder(in context: Context) -> HangeoreumEntry {
    let snapshot = WidgetSnapshotStore.read()
    let language = snapshot.resolvedLanguageCode
    return HangeoreumEntry(date: Date(), tasks: [WidgetTask(id: "preview", title: language == "en" ? "Take a small step" : "가볍게 한 걸음", due: Date().timeIntervalSince1970 * 1000, priority: 1, status: "pending", smallStep: language == "en" ? "Start for 5 minutes" : "5분만 시작하기")], languageCode: language, languagePreference: snapshot.languagePreference)
  }

  func getSnapshot(in context: Context, completion: @escaping (HangeoreumEntry) -> Void) {
    let now = Date()
    let snapshot = WidgetSnapshotStore.read()
    completion(context.isPreview ? placeholder(in: context) : HangeoreumEntry(date: now, tasks: snapshot.visibleTasks(at: now), languageCode: snapshot.resolvedLanguageCode, languagePreference: snapshot.languagePreference))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<HangeoreumEntry>) -> Void) {
    let now = Date()
    let snapshot = WidgetSnapshotStore.read()
    // Supply transitions ahead of time; refresh requests are subject to the OS widget budget.
    var dates = [now]
    for minute in [15, 30, 60, 120, 240, 480, 720, 1440] {
      dates.append(now.addingTimeInterval(Double(minute * 60)))
    }
    dates.append(contentsOf: snapshot.tasks.map(\.dueDate).filter { $0 > now && $0 < now.addingTimeInterval(86400) }.sorted().prefix(24))
    dates.append(contentsOf: snapshot.tasks.compactMap(\.expiresAt).map { Date(timeIntervalSince1970: $0 / 1000) }.filter { $0 > now && $0 < now.addingTimeInterval(86400) }.sorted().prefix(24))
    // Midnight entries keep daily repetition moving through the saved horizon even
    // when the operating system postpones a provider refresh for several days.
    let startOfToday = Calendar.current.startOfDay(for: now)
    for day in 1...90 {
      if let midnight = Calendar.current.date(byAdding: .day, value: day, to: startOfToday) {
        dates.append(midnight)
      }
    }
    let entries = Array(Set(dates)).sorted().map { HangeoreumEntry(date: $0, tasks: snapshot.visibleTasks(at: $0), languageCode: snapshot.resolvedLanguageCode, languagePreference: snapshot.languagePreference) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
  }
}

@main
struct HangeoreumWidget: Widget {
  let kind = "HangeoreumTasksWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: HangeoreumProvider()) { entry in
      HangeoreumWidgetView(entry: entry)
    }
    .configurationDisplayName(Text(WidgetSnapshotStore.read().resolvedLanguageCode == "en" ? "Todoniq · Up next" : "투두닉 · 다음 할 일"))
    .description(Text(WidgetSnapshotStore.read().resolvedLanguageCode == "en" ? "See upcoming tasks and work in progress, and start right away." : "가까운 할 일과 진행 중인 일을 보고 바로 시작하세요."))
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
