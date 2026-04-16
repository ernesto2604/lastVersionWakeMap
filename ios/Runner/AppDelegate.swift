import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String {
      let trimmedKey = mapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      let looksLikeBuildPlaceholder = trimmedKey.hasPrefix("$(") && trimmedKey.hasSuffix(")")
      if !trimmedKey.isEmpty && !looksLikeBuildPlaceholder {
        let didProvide = GMSServices.provideAPIKey(trimmedKey)
        if !didProvide {
          NSLog("[WakeMap][iOS] Invalid Google Maps API key in Info.plist key 'GMSApiKey'.")
        }
      } else {
        NSLog("[WakeMap][iOS] Missing Google Maps API key. Set Info.plist key 'GMSApiKey'.")
      }
    } else {
      NSLog("[WakeMap][iOS] Info.plist key 'GMSApiKey' not found.")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
