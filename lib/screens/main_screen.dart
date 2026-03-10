import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/constants.dart';
import 'chats/chats_screen.dart';
import 'friends/friends_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    _setupFCM();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnline(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) =>
      _setOnline(s == AppLifecycleState.resumed);

  Future<void> _setOnline(bool v) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    await db.collection('users').doc(uid).update({
      'isOnline': v, 'lastSeen': FieldValue.serverTimestamp()
    });
  }

  Future<void> _setupFCM() async {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    final uid   = auth.currentUser?.uid;
    if (uid != null && token != null) {
      await db.collection('users').doc(uid).update({'fcmToken': token});
    }
    FirebaseMessaging.onMessage.listen((msg) {
      if (!mounted) return;
      final n = msg.notification;
      if (n != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.notifications_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
              if (n.body != null)
                Text(n.body!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
          ]),
          backgroundColor: kGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;
    return Scaffold(
      body: IndexedStack(index: _idx, children: [
        const ChatsScreen(),
        const FriendsScreen(),
        ProfileScreen(uid: uid),
        const SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        indicatorColor: kGreen.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded, color: kGreen),
            label: 'Chats'),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded, color: kGreen),
            label: 'Friends'),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: kGreen),
            label: 'Profile'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded, color: kGreen),
            label: 'Settings'),
        ]));
  }
}
