import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var _window: UIWindow?

  /// Under UIScene the AppDelegate no longer owns a window, so
  /// `UIApplication.shared.delegate?.window` is `nil`. Plugins written before
  /// the scene migration (e.g. `fluttercontactpicker`) find the view
  /// controller to present from through that path and silently no-op when it's
  /// nil — which is why the contact picker never appeared and the pick hung
  /// until timeout. Surface the active scene's key window. Safe here because
  /// this is a single-scene app, so the key window is unambiguous.
  override var window: UIWindow? {
    get {
      if let stored = _window { return stored }
      let scenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
      return scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        ?? scenes.flatMap { $0.windows }.first
    }
    set { _window = newValue }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
