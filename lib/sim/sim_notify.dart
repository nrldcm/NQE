// Android system notifications for sandbox trade events (fills, stop-loss,
// take-profit, liquidation). The in-app banner still shows; this ALSO emits a
// real heads-up notification so it surfaces even when the app isn't focused.
// No-op off Android.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SimNotify {
  SimNotify._();
  static final SimNotify instance = SimNotify._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 1;

  Future<void> _ensure() async {
    // TODO(web): no system notifications on web (Platform is dart:io). No-op.
    if (kIsWeb || _ready || !Platform.isAndroid) return;
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(init);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'nqe_trades',
      'Trade alerts',
      description: 'Fills, stop-loss, take-profit and liquidations',
      importance: Importance.high,
    ));
    _ready = true;
  }

  /// Fire-and-forget: post a system notification (Android only).
  Future<void> show(String title, String body) async {
    // TODO(web): no system notifications on web. In-app banners still show.
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _ensure();
      await _plugin.show(
        _id++ & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'nqe_trades',
            'Trade alerts',
            channelDescription:
                'Fills, stop-loss, take-profit and liquidations',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (_) {
      // Best-effort — never let a notification failure break trading.
    }
  }
}
