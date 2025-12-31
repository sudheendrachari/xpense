import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundService {
  static bool _isInitialized = false;

  static Future<void> init() async {
    if (_isInitialized) return;
    
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'finance_sync_channel',
        channelName: 'SMS Sync Service',
        channelDescription: 'Processing bank SMS messages',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    
    _isInitialized = true;
  }

  static Future<void> startService({
    required String title,
    required String message,
  }) async {
    await init();
    
    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: message,
    );
    debugPrint('BACKGROUND_SERVICE: Started - $title');
  }

  static Future<void> updateNotification({
    required String title,
    required String message,
  }) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: message,
    );
  }

  static Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
    debugPrint('BACKGROUND_SERVICE: Stopped');
  }

  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}
