import Flutter
import UIKit
import XCTest
import SwiftUI
import WidgetKit
@testable import Runner

class RunnerTests: XCTestCase {

  private func task(_ id: String, _ due: Double, priority: Int = 1, status: String = "pending") -> WidgetTask {
    WidgetTask(id: id, title: id, due: due, priority: priority, status: status, smallStep: nil)
  }

  func testWidgetShowsProgressThenOverduePriorityThenNearest() {
    let now = Date(timeIntervalSince1970: 100)
    let snapshot = WidgetSnapshot(tasks: [task("later", 150000), task("overdue-low", 80000), task("overdue-high", 90000, priority: 2), task("progress", 200000, status: "progressing"), task("done", 0, status: "completed")], updatedAt: 0)
    XCTAssertEqual(snapshot.visibleTasks(at: now).map(\.id), ["progress", "overdue-high", "overdue-low"])
  }

  func testWidgetDeduplicatesAndFiltersFinishedTasks() {
    let snapshot = WidgetSnapshot(tasks: [task("one", 1000), task("one", 1000), task("skipped", 0, status: "skipped"), task("done", 0, status: "completed")], updatedAt: 0)
    XCTAssertEqual(snapshot.visibleTasks(at: Date()).map(\.id), ["one"])
    XCTAssertTrue(snapshot.visibleTasks(at: Date(), limit: 0).isEmpty)
  }

  func testWidgetSortReevaluatesWhenFutureTasksBecomeOverdue() {
    let snapshot = WidgetSnapshot(tasks: [task("earlier", 100000), task("priority", 120000, priority: 2)], updatedAt: 0)
    XCTAssertEqual(snapshot.visibleTasks(at: Date(timeIntervalSince1970: 50)).first?.id, "earlier")
    XCTAssertEqual(snapshot.visibleTasks(at: Date(timeIntervalSince1970: 150)).first?.id, "priority")
  }

  func testWidgetLinksPreserveOccurrenceIdentifiersAndRejectUnknownActions() {
    let item = task("series@2026-10-06T19:00:00+09:00", 0)
    let link = item.url(action: "snooze")
    XCTAssertTrue(WidgetLaunch.isValid(link))
    XCTAssertTrue(link.absoluteString.contains("%2B09"))
    XCTAssertEqual(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value, item.id)
    XCTAssertFalse(WidgetLaunch.isValid(URL(string: "hangeoreum://task?id=one&action=delete")!))
    XCTAssertFalse(WidgetLaunch.isValid(URL(string: "https://task?id=one&action=start")!))
    XCTAssertFalse(WidgetLaunch.isValid(URL(string: "hangeoreum://task?action=start")!))
  }

  func testWidgetShowsOnlyNearestOccurrenceOfEachRepeatingTask() {
    let tasks = [
      WidgetTask(id: "repeat@today", title: "매일 운동", due: 100000, priority: 1, status: "pending", smallStep: nil, taskId: "repeat"),
      WidgetTask(id: "repeat@tomorrow", title: "매일 운동", due: 200000, priority: 1, status: "pending", smallStep: nil, taskId: "repeat"),
      task("other", 300000),
    ]
    let snapshot = WidgetSnapshot(tasks: tasks, updatedAt: 0)
    XCTAssertEqual(snapshot.visibleTasks(at: Date(timeIntervalSince1970: 50)).map(\.id), ["repeat@today", "other"])
  }

  func testWidgetExpiredUntouchedRepeatRotatesButPausedAndOneOffRemain() {
    let tasks = [
      WidgetTask(id: "repeat@today", title: "매일 운동", due: 100000, priority: 1, status: "pending", smallStep: nil, taskId: "repeat", expiresAt: 200000),
      WidgetTask(id: "repeat@tomorrow", title: "매일 운동", due: 250000, priority: 1, status: "pending", smallStep: nil, taskId: "repeat", expiresAt: 300000),
      WidgetTask(id: "paused", title: "미룬 청소", due: 50000, priority: 1, status: "paused", smallStep: nil, expiresAt: 200000),
      task("one-off", 75000),
    ]
    let snapshot = WidgetSnapshot(tasks: tasks, updatedAt: 0)
    XCTAssertEqual(snapshot.visibleTasks(at: Date(timeIntervalSince1970: 150), limit: 10).map(\.id), ["paused", "one-off", "repeat@today"])
    XCTAssertEqual(snapshot.visibleTasks(at: Date(timeIntervalSince1970: 200), limit: 10).map(\.id), ["paused", "one-off", "repeat@tomorrow"])
  }

  func testWidgetDecodesDartNullSmallStepAndMillisecondDates() throws {
    let data = Data("{\"tasks\":[{\"id\":\"one\",\"title\":\"청소\",\"due\":100000,\"priority\":2,\"status\":\"paused\",\"smallStep\":null}],\"updatedAt\":0}".utf8)
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    XCTAssertEqual(snapshot.tasks.first?.dueDate.timeIntervalSince1970, 100)
    XCTAssertNil(snapshot.tasks.first?.smallStep)
    XCTAssertNil(snapshot.languageCode, "Existing snapshots remain readable before language preferences are saved")
  }

  func testWidgetLanguageIsSnapshotMetadataAndDoesNotChangeUserTitle() throws {
    let snapshot = WidgetSnapshot(tasks: [WidgetTask(id: "one", title: "필터 청소", due: 100000, priority: 1, status: "pending", smallStep: nil)], updatedAt: 0, languageCode: "en")
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
    XCTAssertEqual(decoded.resolvedLanguageCode, "en")
    XCTAssertEqual(decoded.tasks.first?.title, "필터 청소")
  }

  func testSystemWidgetLanguageFollowsDeviceWithoutRewritingSnapshot() throws {
    let saved = WidgetSnapshot(tasks: [task("one", 100000)], updatedAt: 0, languageCode: "ko", languagePreference: "system")
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(saved))
    XCTAssertEqual(snapshot.languagePreference, "system")
    XCTAssertEqual(snapshot.resolveLanguage(systemLocale: Locale(identifier: "ko_KR")), "ko")
    XCTAssertEqual(snapshot.resolveLanguage(systemLocale: Locale(identifier: "en_US")), "en")
    XCTAssertEqual(snapshot.resolveLanguage(systemLocale: Locale(identifier: "fr_FR")), "en")
  }

  func testExplicitAndLegacyWidgetLanguagesRemainStable() throws {
    for language in ["ko", "en"] {
      let snapshot = WidgetSnapshot(tasks: [], updatedAt: 0, languageCode: language == "ko" ? "en" : "ko", languagePreference: language)
      XCTAssertEqual(snapshot.resolveLanguage(systemLocale: Locale(identifier: "ko_KR")), language)
      XCTAssertEqual(snapshot.resolveLanguage(systemLocale: Locale(identifier: "en_US")), language)
      let legacyData = Data("{\"tasks\":[],\"updatedAt\":0,\"languageCode\":\"\(language)\"}".utf8)
      let legacy = try JSONDecoder().decode(WidgetSnapshot.self, from: legacyData)
      XCTAssertNil(legacy.languagePreference)
      XCTAssertEqual(legacy.resolveLanguage(systemLocale: Locale(identifier: "fr_FR")), language)
    }
    let oldest = WidgetSnapshot(tasks: [], updatedAt: 0)
    XCTAssertEqual(oldest.resolveLanguage(systemLocale: Locale(identifier: "ko_KR")), "ko")
    XCTAssertEqual(oldest.resolveLanguage(systemLocale: Locale(identifier: "en_US")), "en")
    let invalid = WidgetSnapshot(tasks: [], updatedAt: 0, languageCode: "xx", languagePreference: "xx")
    XCTAssertEqual(invalid.resolveLanguage(systemLocale: Locale(identifier: "ko_KR")), "ko")
  }

  func testSmallWidgetRendersActualSwiftUIView() {
    verifyWidgetRendering(family: .systemSmall, size: CGSize(width: 158, height: 158), name: "ios-widget-small")
  }

  func testMediumWidgetRendersActualSwiftUIView() {
    verifyWidgetRendering(family: .systemMedium, size: CGSize(width: 338, height: 158), name: "ios-widget-medium")
  }

  func testSmallEnglishWidgetRendersActualSwiftUIView() {
    verifyWidgetRendering(family: .systemSmall, size: CGSize(width: 158, height: 158), name: "ios-widget-small-en", languageCode: "en")
  }

  func testMediumEnglishWidgetRendersActualSwiftUIView() {
    verifyWidgetRendering(family: .systemMedium, size: CGSize(width: 338, height: 158), name: "ios-widget-medium-en", languageCode: "en")
  }

  private func verifyWidgetRendering(family: WidgetFamily, size: CGSize, name: String, languageCode: String = "ko") {
    let rendered = expectation(description: "Render \(name)")
    DispatchQueue.main.async {
      let date = Date(timeIntervalSince1970: 1791273600)
      let entry = HangeoreumEntry(date: date, tasks: [
        WidgetTask(id: "clean", title: "안방 대청소", due: date.timeIntervalSince1970 * 1000, priority: 2, status: "pending", smallStep: "바닥부터 5분", taskId: "clean"),
        WidgetTask(id: "walk", title: "동네 한 바퀴 걷기", due: date.addingTimeInterval(1800).timeIntervalSince1970 * 1000, priority: 1, status: "progressing", smallStep: nil, taskId: "walk"),
        WidgetTask(id: "read", title: "책 읽기", due: date.addingTimeInterval(3600).timeIntervalSince1970 * 1000, priority: 0, status: "paused", smallStep: nil, taskId: "read"),
      ], languageCode: languageCode)
      let view = HangeoreumWidgetView(entry: entry, familyOverride: family, isWidgetContext: false)
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
      let hosting = UIHostingController(rootView: view)
      let root = UIViewController()
      let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
      let previousKeyWindow = scene?.windows.first(where: { $0.isKeyWindow })
      let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(origin: .zero, size: size))
      window.rootViewController = root
      window.makeKeyAndVisible()
      root.addChild(hosting)
      root.view.addSubview(hosting.view)
      hosting.view.frame = CGRect(origin: .zero, size: size)
      hosting.didMove(toParent: root)
      hosting.view.setNeedsLayout()
      hosting.view.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))

      let format = UIGraphicsImageRendererFormat()
      format.scale = 2
      format.opaque = true
      format.preferredRange = .standard
      let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        XCTAssertTrue(hosting.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true))
      }
      XCTAssertEqual(image.cgImage?.width, Int(size.width * 2))
      XCTAssertEqual(image.cgImage?.height, Int(size.height * 2))
      if let cgImage = image.cgImage, let data = cgImage.dataProvider?.data,
         let bytes = CFDataGetBytePtr(data), cgImage.bitsPerPixel == 32 {
        var darkPixels = 0
        for row in 0..<cgImage.height {
          for column in 0..<cgImage.width {
            let offset = row * cgImage.bytesPerRow + column * 4
            if bytes[offset] < 140 && bytes[offset + 1] < 140 && bytes[offset + 2] < 140 { darkPixels += 1 }
          }
        }
        XCTAssertGreaterThan(darkPixels, 300, "The widget should contain visible text and controls, rather than a blank image")
      } else {
        XCTFail("Widget rendering did not produce an inspectable RGBA image")
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = name
      attachment.lifetime = .keepAlways
      self.add(attachment)
      do {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hangeoreum-widget-tests")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.pngData()?.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
      } catch { XCTFail("Unable to save the widget screenshot: \(error)") }
      hosting.willMove(toParent: nil)
      hosting.view.removeFromSuperview()
      hosting.removeFromParent()
      window.isHidden = true
      previousKeyWindow?.makeKeyAndVisible()
      rendered.fulfill()
    }
    wait(for: [rendered], timeout: 15)
  }

}
