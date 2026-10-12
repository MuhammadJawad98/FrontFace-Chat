import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Same key as AndroidManifest `com.google.android.geo.API_KEY` and the
    // example "Google Maps API key" field (Places + Geocoding + Maps SDK).
    GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Inbound VoIP (when you add PushKit + flutter_callkit_incoming):
  // After building FlutterCallkitIncomingFlutterPayload / CallkitIncomingAppData,
  // set data.iconName = "CallKitLogo" before showCallkitIncoming(..., fromPushKit: true).
  // Asset: Assets.xcassets/CallKitLogo.imageset (template / silhouette).
  // See CALLS_INTEGRATION.md §4.3.1 — Dart-only iconName is not enough when killed.
}
