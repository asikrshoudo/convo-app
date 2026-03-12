import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import 'main_screen.dart';
import 'auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    _init();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getInt('themeMode');
    if (savedTheme != null) {
      themeNotifier.value = [
        ThemeMode.system, ThemeMode.dark, ThemeMode.light][savedTheme];
    }
    final savedAccent = prefs.getInt('accentColor');
    if (savedAccent != null) {
      accentColorNotifier.value = Color(savedAccent);
    }

    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    final user = auth.currentUser;
    if (user == null) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    try {
      await db.collection('users').doc(user.uid).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (mounted) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const MainScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/white_logo.png',
                  width: 90,
                  height: 90,
                  errorBuilder: (_, __, ___) => Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kAccent.withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 2),
                      ]),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: kAccent,
                      size: 44)),
                ),
                const SizedBox(height: 20),
                Text(
                  'Convo',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDark ? kTextPrimary : kLightText,
                    letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text(
                  'Connect with friends',
                  style: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 14,
                    letterSpacing: 0.2)),
                const SizedBox(height: 48),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: kAccent.withOpacity(0.7),
                    strokeWidth: 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
