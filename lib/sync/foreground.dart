// Foreground-service helpers for the LAN sync server.
//
// The sync server (see sync_server.dart) is a plain Dart HttpServer/WebSocket
// listener. On Android that isolate is killed when the screen locks or the app
// is backgrounded unless it is tied to a foreground service with an ongoing
// notification. These thin wrappers start/stop such a service so the mobile —
// the source of truth — stays reachable for the desktop client.
//
// Everything here is best-effort: if the plugin isn't available (e.g. running
// on a platform without it, or init fails) the helpers no-op so the server can
// still run in the foreground while the app is visible.
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

const _channelId = 'nqe_sync_server';
const _channelName = 'NQE Sync Server';
const _channelDescription =
    'Keeps the local-network sync server alive while paired with the desktop.';

bool _initialised = false;

void _ensureInitialised() {
  if (_initialised) return;
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: _channelId,
      channelName: _channelName,
      channelDescription: _channelDescription,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
  _initialised = true;
}

/// Ask for the permissions the background sync server needs so Android doesn't
/// kill it when the screen locks: the ongoing-notification permission (13+) and
/// — crucially — an exemption from battery optimisation (Doze). Without the
/// exemption the OS puts the app under "power restriction" and suspends the
/// server in the background. Best-effort and safe to call repeatedly.
Future<void> requestBackgroundPermissions() async {
  try {
    _ensureInitialised();
    // Ongoing-notification permission (Android 13+).
    final np = await FlutterForegroundTask.checkNotificationPermission();
    if (np != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    // Battery-optimisation exemption → "No restrictions" power setting, so the
    // server keeps running locked/backgrounded while on Wi-Fi.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  } catch (e) {
    debugPrint('requestBackgroundPermissions failed (continuing): $e');
  }
}

/// True when the app is exempt from battery optimisation (power = "No
/// restrictions"). Lets the UI show/prompt if it still needs granting.
Future<bool> isBatteryUnrestricted() async {
  try {
    _ensureInitialised();
    return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
  } catch (_) {
    return false;
  }
}

/// Open the system battery-optimisation settings for this app.
Future<void> openBatterySettings() async {
  try {
    _ensureInitialised();
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  } catch (_) {/* ignore */}
}

/// Start (or update) the persistent foreground notification. Safe to call more
/// than once — an already-running service just has its text refreshed.
Future<void> startForeground(String text) async {
  try {
    _ensureInitialised();
    // Make sure we're allowed to post the ongoing notification + excluded from
    // battery optimisation before the service starts.
    await requestBackgroundPermissions();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'NQE sync server running',
        notificationText: text,
      );
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'NQE sync server running',
        notificationText: text,
      );
    }
  } catch (e) {
    // Best-effort: the server can still run while the app is foregrounded.
    debugPrint('startForeground failed (continuing without service): $e');
  }
}

/// Stop the foreground service and clear its notification. Never throws.
Future<void> stopForeground() async {
  try {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  } catch (e) {
    debugPrint('stopForeground failed: $e');
  }
}
