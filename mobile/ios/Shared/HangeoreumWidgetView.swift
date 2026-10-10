import SwiftUI
import WidgetKit

struct HangeoreumEntry: TimelineEntry {
  let date: Date
  let tasks: [WidgetTask]
  var languageCode: String = "ko"
  var languagePreference: String? = nil
}

struct HangeoreumWidgetView: View {
  @Environment(\.widgetFamily) private var environmentFamily
  @Environment(\.locale) private var environmentLocale
  let entry: HangeoreumEntry
  private let familyOverride: WidgetFamily?
  private let isWidgetContext: Bool
  private let ink = Color(red: 0.15, green: 0.16, blue: 0.16)
  private let red = Color(red: 0.56, green: 0.19, blue: 0.23)
  private let paper = Color(red: 0.98, green: 0.97, blue: 0.95)

  init(entry: HangeoreumEntry, familyOverride: WidgetFamily? = nil, isWidgetContext: Bool = true) {
    self.entry = entry
    self.familyOverride = familyOverride
    self.isWidgetContext = isWidgetContext
  }

  private var family: WidgetFamily { familyOverride ?? environmentFamily }
  private var english: Bool {
    WidgetSnapshot.resolveLanguage(preference: entry.languagePreference, legacyLanguageCode: entry.languageCode, systemLocale: environmentLocale) == "en"
  }
  private func text(_ korean: String, _ englishText: String) -> String { english ? englishText : korean }

  var body: some View {
    content
      .widgetURL(entry.tasks.first?.url() ?? URL(string: "hangeoreum://home"))
      .modifier(WidgetPaperBackground(paper: paper, isWidgetContext: isWidgetContext))
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 9 : 8) {
      HStack {
        Text("첫칸").font(.system(size: 12, weight: .semibold))
        Spacer()
        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
      }.foregroundColor(ink.opacity(0.62))
      if let first = entry.tasks.first {
        if family == .systemSmall {
          Text(status(first)).font(.system(size: 11, weight: .medium)).foregroundColor(first.priority == 2 ? red : ink.opacity(0.6))
          Text(first.title).font(.system(size: 18, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.85).foregroundColor(ink)
          Spacer(minLength: 0)
          HStack {
            Text(time(first)).font(.system(size: 12, weight: .medium)).foregroundColor(ink.opacity(0.65))
            Spacer()
            Image(systemName: "play.circle.fill").foregroundColor(ink)
          }
        } else {
          ForEach(entry.tasks.prefix(3)) { task in
            Link(destination: task.url()) {
              HStack(spacing: 8) {
                Capsule().fill(task.priority == 2 ? red : ink.opacity(0.35)).frame(width: 3, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                  Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundColor(ink)
                  Text("\(time(task)) · \(status(task))").font(.system(size: 10)).foregroundColor(ink.opacity(0.6))
                }
                Spacer(minLength: 0)
              }
            }
          }
          Spacer(minLength: 0)
          HStack(spacing: 12) {
            Link(destination: first.url(action: "start")) {
              Label(text("지금 시작", "Start now"), systemImage: "play.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(ink)
            }
            Link(destination: first.url(action: "snooze")) {
              Text(text("10분 뒤", "In 10 min")).font(.system(size: 11, weight: .medium)).foregroundColor(ink.opacity(0.65))
            }
            Spacer(minLength: 0)
          }
        }
      } else {
        Spacer(minLength: 0)
        Text(text("다가오는 할 일이\n없어요", "No upcoming\ntasks")).font(.system(size: 17, weight: .semibold)).foregroundColor(ink)
        Text(text("앱에서 다음 할 일을 정해보세요.", "Add your next task in the app.")).font(.system(size: 11)).foregroundColor(ink.opacity(0.6))
        Spacer(minLength: 0)
      }
    }
    .padding(contentPadding)
    .accessibilityElement(children: .contain)
  }

  private var contentPadding: CGFloat {
    if !isWidgetContext { return 16 }
    if #available(iOS 17.0, *) { return 0 }
    return family == .systemSmall ? 14 : 12
  }

  private func status(_ task: WidgetTask) -> String {
    if task.status == "progressing" { return text("진행 중", "In progress") }
    if task.status == "paused" { return text("잠시 미뤘어요", "Snoozed") }
    return task.dueDate < entry.date ? text("다시 시작해볼까요", "Ready to restart?") : text("다음 할 일", "Up next")
  }

  private func time(_ task: WidgetTask) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: english ? "en_US" : "ko_KR")
    formatter.dateFormat = Calendar.current.isDate(task.dueDate, inSameDayAs: entry.date)
      ? (english ? "h:mm a" : "HH:mm") : (english ? "MMM d h:mm a" : "M/d HH:mm")
    return formatter.string(from: task.dueDate)
  }
}

private struct WidgetPaperBackground: ViewModifier {
  let paper: Color
  let isWidgetContext: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 17.0, *), isWidgetContext {
      content.containerBackground(paper, for: .widget)
    } else {
      content.background(paper)
    }
  }
}

