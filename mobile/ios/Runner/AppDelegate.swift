import Flutter
import UIKit
import UserNotifications
import WidgetKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var pendingWidgetUri: String?
  private var flutterWidgetReady = false
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    if var documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do { try documents.setResourceValues(values) }
      catch { NSLog("Unable to exclude local task database from backup") }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "com.dabok407.hangeoreum/widget", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    widgetChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
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

private func refreshWidgetSnapshot(_ arguments: Any?, result: @escaping FlutterResult) {
  guard let args = arguments as? [String: Any], let tasks = args["tasks"] as? [[String: Any]] else {
    result(FlutterError(code: "invalid_snapshot", message: "Expected a task list", details: nil))
    return
  }
  do {
    try WidgetSnapshotStore.write(tasks: tasks)
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
    else { result(FlutterMethodNotImplemented) }
  }
}
