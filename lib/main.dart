import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants.dart';
import 'app.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage msg) async => await Firebase.initializeApp();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);

  // Restore saved theme
  final prefs      = await SharedPreferences.getInstance();
  final savedTheme = prefs.getInt('themeMode') ?? 1; // 0=system, 1=dark, 2=light
  themeNotifier.value = [ThemeMode.system, ThemeMode.dark, ThemeMode.light][savedTheme.clamp(0, 2)];

  runApp(const ConvoApp());
}
