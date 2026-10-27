import Flutter
import UIKit
import UserNotifications
import WidgetKit
import workmanager_apple
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var subscriptions: SubscriptionBridge?
  private var backupFiles: BackupDocumentBridge?
  private var pendingWidgetUri: String?
  private var flutterWidgetReady = false
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if targetEnvironment(simulator)
    // CI clears previously delivered banners before testing a fresh local alert.
    // This hook is absent from physical-device / App Store builds.
    if ProcessInfo.processInfo.arguments.contains("--clear-delivered-notifications") {
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    #endif
    #if DEBUG
    NSLog("HANGEOREUM_START: application launch")
    #endif
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      if let registrar = registry.registrar(forPlugin: "HangeoreumWidgetSnapshot") {
        BackgroundWidgetSnapshotPlugin.register(with: registrar)
      }
    }
    // Register the known refresh handler before UIKit finishes launching. The
    // first Dart submission must already have a native handler, not only the
    // handlers restored from a previous launch's persisted task registrations.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.dabok407.hangeoreum.refresh",
      earliestBeginInSeconds: NSNumber(value: 6 * 60 * 60)
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    #if DEBUG
    NSLog("HANGEOREUM_START: background handlers registered")
    #endif
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    if var documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do { try documents.setResourceValues(values) }
      catch { NSLog("Unable to exclude local task database from backup") }
    }
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    #if DEBUG
    NSLog("HANGEOREUM_START: application launch finished")
    #endif
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    #if DEBUG
    NSLog("HANGEOREUM_START: implicit Flutter engine initialized")
    #endif
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    subscriptions = SubscriptionBridge(messenger: engineBridge.applicationRegistrar.messenger())
    backupFiles = BackupDocumentBridge(messenger: engineBridge.applicationRegistrar.messenger())
    let channel = FlutterMethodChannel(name: "com.dabok407.hangeoreum/widget", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    widgetChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getCalendarPreferences":
        result(calendarPreferences())
      case "update":
        refreshWidgetSnapshot(call.arguments, result: result)
      case "getLaunchUri":
        self.flutterWidgetReady = true
        let uri = self.pendingWidgetUri
        self.pendingWidgetUri = nil
        result(uri)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @discardableResult
  func handleWidgetURL(_ url: URL) -> Bool {
    guard WidgetLaunch.isValid(url) else { return false }
    if flutterWidgetReady, let channel = widgetChannel {
      channel.invokeMethod("launchUri", arguments: url.absoluteString)
    } else {
      pendingWidgetUri = url.absoluteString
    }
    return true
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if handleWidgetURL(url) { return true }
    return super.application(app, open: url, options: options)
  }
}

/// Explicit user-initiated import/export. Weekly backups use Dart file I/O in
/// the existing backup-excluded local database directory, with no network API.
private final class BackupDocumentBridge: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel
  private var pendingResult: FlutterResult?
  private var pendingRequestID: UUID?
  private var exportFile: URL?
  private var exporting = false
  private let maximumBytes = 20 * 1024 * 1024

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.dabok407.hangeoreum/backup", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { self.handle(call, result: result) }
      return
    }
    guard call.method == "export" || call.method == "import" else {
      result(FlutterMethodNotImplemented); return
    }
    guard pendingResult == nil else {
      result(FlutterError(code: "backup_busy", message: "A file picker is already open.", details: nil)); return
    }
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    guard var presenter = windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "backup_unavailable", message: "The app is not visible.", details: nil)); return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    do {
      let picker: UIDocumentPickerViewController
      exporting = call.method == "export"
      if exporting {
        guard let args = call.arguments as? [String: Any],
              let contents = args["contents"] as? String,
              let data = contents.data(using: .utf8), data.count <= maximumBytes else {
          throw NSError(domain: "TodoniqBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid backup data."])
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("todoniq-export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Todoniq-backup.json")
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        exportFile = file
        picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      } else {
        // Read the picker's local copy, never a provider's original document.
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data], asCopy: true)
        picker.allowsMultipleSelection = false
      }
      pendingResult = result
      pendingRequestID = UUID()
      picker.delegate = self
      presenter.present(picker, animated: true)
    } catch {
      if let file = exportFile { try? FileManager.default.removeItem(at: file) }
      exportFile = nil
      result(FlutterError(code: "backup_file", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(exporting ? false : nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if exporting { finish(true); return }
    guard let url = urls.first else { finish(nil); return }
    guard let requestID = pendingRequestID else { return }
    // Even a valid 20 MiB backup must not block UIKit while reading/decoding.
    // Keep pendingResult set until completion so another picker cannot open.
    DispatchQueue.global(qos: .userInitiated).async {
      let granted = url.startAccessingSecurityScopedResource()
      defer { if granted { url.stopAccessingSecurityScopedResource() } }
      do {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if values.isRegularFile == false || (values.fileSize ?? 0) > self.maximumBytes {
          throw NSError(domain: "TodoniqBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid backup file size."])
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: self.maximumBytes + 1) ?? Data()
        guard data.count <= self.maximumBytes, let text = String(data: data, encoding: .utf8) else {
          throw NSError(domain: "TodoniqBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "The backup is not a valid UTF-8 file."])
        }
        self.finish(text, requestID: requestID)
      } catch {
        self.finish(FlutterError(code: "backup_file", message: error.localizedDescription, details: nil), requestID: requestID)
      }
    }
  }

  private func finish(_ value: Any?, requestID: UUID? = nil) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { self.finish(value, requestID: requestID) }
      return
    }
    // Ignore an old read if its picker was cancelled before a newer request.
    if let requestID = requestID, requestID != pendingRequestID { return }
    let result = pendingResult
    pendingResult = nil
    pendingRequestID = nil
    if let file = exportFile { try? FileManager.default.removeItem(at: file) }
    exportFile = nil
    result?(value)
  }
}

private func calendarPreferences() -> [String: Any] {
  // System region and calendar preferences stay independent of the app language.
  // Foundation reads local settings without a location or network permission.
  return [
    "regionCode": Locale.autoupdatingCurrent.regionCode ?? "",
    "firstDayOfWeek": Calendar.autoupdatingCurrent.firstWeekday - 1,
  ]
}

private func refreshWidgetSnapshot(_ arguments: Any?, result: @escaping FlutterResult) {
  guard let args = arguments as? [String: Any], let tasks = args["tasks"] as? [[String: Any]] else {
    result(FlutterError(code: "invalid_snapshot", message: "Expected a task list", details: nil))
    return
  }
  do {
    try WidgetSnapshotStore.write(tasks: tasks, languageCode: args["languageCode"] as? String ?? "ko", languagePreference: args["languagePreference"] as? String)
    WidgetCenter.shared.reloadTimelines(ofKind: "HangeoreumTasksWidget")
    result(nil)
  } catch {
    result(FlutterError(code: "widget_storage", message: error.localizedDescription, details: nil))
  }
}

/// Register the same read-only snapshot channel on Workmanager's independent engine.
private final class BackgroundWidgetSnapshotPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.dabok407.hangeoreum/widget", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(BackgroundWidgetSnapshotPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "update" { refreshWidgetSnapshot(call.arguments, result: result) }
    else if call.method == "getLaunchUri" { result(nil) }
    else if call.method == "getCalendarPreferences" { result(calendarPreferences()) }
    else { result(FlutterMethodNotImplemented) }
  }
}
