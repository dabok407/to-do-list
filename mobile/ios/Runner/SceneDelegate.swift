import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    #if DEBUG
    NSLog("HANGEOREUM_START: scene connecting")
    #endif
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    #if DEBUG
    NSLog("HANGEOREUM_START: scene connected")
    #endif
    for context in connectionOptions.urlContexts {
      (UIApplication.shared.delegate as? AppDelegate)?.handleWidgetURL(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      (UIApplication.shared.delegate as? AppDelegate)?.handleWidgetURL(context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
