import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';

/// Starts/stops the Android microphone foreground service so calls survive
/// screen-off / background. No-op on iOS (audio background mode) and web.
///
/// After **app-killed** Accept, call this only once a [BuildContext] / Activity
/// exists (see [frontFaceWaitForNavigatorContext]) — starting the FGS too early
/// fails on Android.
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

/// Polls until [navigatorKey] has a mounted context, or [timeout] elapses.
///
/// Use after cold-start CallKit Accept: the OS may deliver Accept before the
/// first Flutter frame, so `Navigator` / GetX context is still null. Wait here
/// before `answer()`, Android FGS, and pushing [FrontFaceCallScreen].
Future<BuildContext?> frontFaceWaitForNavigatorContext(
  GlobalKey<NavigatorState> navigatorKey, {
  Duration timeout = const Duration(seconds: 8),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) return ctx;
    await Future<void>.delayed(pollInterval);
  }
  final ctx = navigatorKey.currentContext;
  return (ctx != null && ctx.mounted) ? ctx : null;
}
