import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/constants.dart';
import 'app.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'convo_default',
  'Convo Notifications',
  description: 'Notifications from Convo app',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage msg) async {
  await Firebase.initializeApp();
  await _saveNotificationToFirestore(msg);
}

/// Save incoming FCM notification to Firestore so NotificationsScreen can show it
Future<void> _saveNotificationToFirestore(RemoteMessage msg) async {
  try {
    final data    = msg.data;
    final toUid   = data['toUid'] as String?;
    if (toUid == null || toUid.isEmpty) return;

    await FirebaseFirestore.instance.collection('notifications').add({
      'uid':       toUid,
      'title':     msg.notification?.title ?? data['title'] ?? '',
      'body':      msg.notification?.body  ?? data['body']  ?? '',
      'data':      data,
      'read':      false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

Future<void> saveFcmToken() async {
  final user = auth.currentUser;
  if (user == null) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({'fcmToken': token});

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fcmToken': newToken});
    });
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);

  // Init local notifications
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: android),
    onDidReceiveNotificationResponse: (details) {
      // tap handled via navigatorKey
    });

  // Request permission
  await FirebaseMessaging.instance.requestPermission(
    alert: true, badge: true, sound: true);

  // Create notification channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true, badge: true, sound: true);

  // ── Foreground notification handler ────────────────────────────────────────
  FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
    final notification = msg.notification;
    final android      = msg.notification?.android;

    // Show local notification popup
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id, channel.name,
            channelDescription: channel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
          )),
      );
    }

    // Save to Firestore so notifications screen updates
    await _saveNotificationToFirestore(msg);
  });

  // Handle notification tap when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
    // The app opens; navigation is handled by notifications screen tap
  });

  // Save FCM token
  await saveFcmToken();
  auth.authStateChanges().listen((user) {
    if (user != null) saveFcmToken();
  });

  // Restore theme
  final prefs      = await SharedPreferences.getInstance();
  final savedTheme = prefs.getInt('themeMode') ?? 1;
  themeNotifier.value =
    [ThemeMode.system, ThemeMode.dark, ThemeMode.light][savedTheme.clamp(0, 2)];

  // Restore accent
  final savedColor = prefs.getInt('accentColor');
  if (savedColor != null) accentColorNotifier.value = Color(savedColor);

  runApp(const ConvoApp());
}
