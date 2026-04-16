import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var iosMapsApiKeyStatus = "unknown"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String {
      let trimmedKey = mapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      let looksLikeBuildPlaceholder = trimmedKey.hasPrefix("$(") && trimmedKey.hasSuffix(")")

      if trimmedKey.isEmpty {
        iosMapsApiKeyStatus = "missing"
        NSLog("[WakeMap][iOS] Missing Google Maps API key. Set GMS_API_KEY in ios/Flutter/*.xcconfig.")
      } else if looksLikeBuildPlaceholder {
        iosMapsApiKeyStatus = "placeholder"
        NSLog("[WakeMap][iOS] Google Maps API key still uses unresolved build placeholder: %@", trimmedKey)
      } else {
        let didProvide = GMSServices.provideAPIKey(trimmedKey)
        iosMapsApiKeyStatus = didProvide ? "configured" : "invalid"
        if !didProvide {
          NSLog("[WakeMap][iOS] Invalid Google Maps API key in Info.plist key 'GMSApiKey'.")
        }
      }
    } else {
      iosMapsApiKeyStatus = "missing"
      NSLog("[WakeMap][iOS] Info.plist key 'GMSApiKey' not found.")
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let nativeConfigChannel = FlutterMethodChannel(
        name: "wake_map/native_config",
        binaryMessenger: controller.binaryMessenger
      )

      nativeConfigChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getIosMapsApiKeyStatus" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(self?.iosMapsApiKeyStatus ?? "unknown")
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
