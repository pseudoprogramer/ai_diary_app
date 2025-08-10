import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'navigation_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings init = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (response) async {
        // Navigate to history screen route when tapped
        final nav = NavigationService.navigatorKey.currentState;
        if (nav != null) {
          nav.pushNamed('/history');
        }
      },
    );
    _initialized = true;
  }

  static Future<void> showDailyResult({required String title, required String body}) async {
    await initialize();
    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'ai_diary_daily',
      'AI Diary Daily',
      channelDescription: '자정에 생성된 일기 결과를 알려드립니다',
      importance: Importance.high,
      priority: Priority.high,
    );
    const DarwinNotificationDetails ios = DarwinNotificationDetails();
    const NotificationDetails details = NotificationDetails(android: android, iOS: ios);
    await _plugin.show(1001, title, body, details);
  }
}


