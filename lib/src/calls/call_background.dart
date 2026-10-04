import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_background/flutter_background.dart';

/// Starts/stops the Android microphone foreground service so calls survive
/// screen-off / background. No-op on iOS (audio background mode) and web.
Future<void> frontFaceKeepCallAliveInBackground(bool on) async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (on) {
    final ready = await FlutterBackground.initialize(
      androidConfig: const FlutterBackgroundAndroidConfig(
        notificationTitle: 'Call with support',
        notificationText: 'Tap to return to your call',
        notificationImportance: AndroidNotificationImportance.normal,
        shouldRequestBatteryOptimizationsOff: false,
      ),
    );
    if (ready && !FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.enableBackgroundExecution();
    }
  } else if (FlutterBackground.isBackgroundExecutionEnabled) {
    await FlutterBackground.disableBackgroundExecution();
  }
}
