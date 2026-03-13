// lib/screens/auth/username_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../main_screen.dart';

/// Shown after Google / GitHub / Phone login for brand-new users.
/// Saves photoURL from OAuth provider (Google profile pic / GitHub avatar)
/// as avatarUrl in Firestore — zero storage cost.
class UsernameSetupScreen extends StatefulWidget {
  final User user;
  const UsernameSetupScreen({super.key, required this.user});
  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  bool _retrying = false;

  @override
  void initState() { super.initState(); _autoSetup(); }

  String _generateUsername(String name, String uid) {
    final base = name.trim().toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .substring(0, name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
            .length.clamp(0, 12));
    final suffix = uid.substring(uid.length - 5);
    return '${base}_$suffix';
  }

  Future<void> _autoSetup() async {
    if (mounted) setState(() => _retrying = false);
    try {
      final u        = widget.user;
      final name     = u.displayName ?? u.email?.split('@').first
          ?? u.phoneNumber ?? 'User';
      final username = _generateUsername(name, u.uid);

      // Google/GitHub automatically provide photoURL — use it as profile pic.
      // This is just a URL string stored in Firestore, zero storage cost.
      final photoUrl = u.photoURL; // null for email/phone users

      await db.collection('users').doc(u.uid).set({
        'uid':         u.uid,
        'name':        name,
        'nameLower':   name.toLowerCase(),
        'username':    username,
        'email':       u.email ?? '',
        'phone':       u.phoneNumber ?? '',
        'phoneNormalized': '',
        // avatarUrl = OAuth photo URL (Google pic / GitHub avatar)
        // avatar    = fallback letter (used when avatarUrl is null)
        'avatarUrl':   photoUrl ?? '',
        'avatar':      name[0].toUpperCase(),
        'gender':      '',
        'verified':    false,
        'verifiedWaitlist': false,
        'suggestionsEnabled': true,
        'friendsPublic':      true,
        'profileMode':        'friend',
        'bio':         '',
        'city':        '',
        'education':   '',
        'work':        '',
        'hometown':    '',
        'social': {
          'facebook':  '',
          'instagram': '',
          'github':    '',
          'linkedin':  '',
          'twitter':   '',
        },
        'followerCount':  0,
        'followingCount': 0,
        'friendCount':    0,
        'fcmToken':    '',
        'isOnline':    true,
        'lastSeen':    FieldValue.serverTimestamp(),
        'createdAt':   FieldValue.serverTimestamp(),
      });

      FirebaseMessaging.instance.getToken().then((fcm) {
        if (fcm != null) {
          db.collection('users').doc(u.uid).update({'fcmToken': fcm});
        }
      });

      if (mounted) Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));

    } catch (_) {
      if (mounted) setState(() => _retrying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        if (!_retrying) ...[
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.15), shape: BoxShape.circle),
            child: const Center(
              child: CircularProgressIndicator(
                  color: kAccent, strokeWidth: 2.5))),
          const SizedBox(height: 24),
          Text('Setting up your account...',
              style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub,
                  fontSize: 14)),
        ] else ...[
          Icon(Icons.wifi_off_rounded,
              color: isDark ? kTextSecondary : kLightTextSub, size: 48),
          const SizedBox(height: 16),
          Text('Connection error',
              style: TextStyle(
                  color: isDark ? kTextPrimary : kLightText,
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Could not create your account.\nCheck your connection.',
              style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub,
                  fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            onPressed: _autoSetup,
            child: const Text('Retry',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ])),
    );
  }
}
