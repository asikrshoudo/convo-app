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
);

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage msg) async {
  await Firebase.initializeApp();
}

/// Save FCM token to Firestore for the current user
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

    // Refresh token when it changes
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

  // Request notification permission
  await FirebaseMessaging.instance.requestPermission(
    alert: true, badge: true, sound: true);

  // Create notification channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Set foreground notification options
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true, badge: true, sound: true);

  // Save FCM token if already logged in
  await saveFcmToken();

  // Also save token whenever auth state changes (login/register)
  auth.authStateChanges().listen((user) {
    if (user != null) saveFcmToken();
  });

  // Restore saved theme
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getInt('themeMode') ?? 1;
  themeNotifier.value = [ThemeMode.system, ThemeMode.dark, ThemeMode.light][savedTheme.clamp(0, 2)];

  // Restore saved accent color
  final savedColor = prefs.getInt('accentColor');
  if (savedColor != null) accentColorNotifier.value = Color(savedColor);

  runApp(const ConvoApp());
}
