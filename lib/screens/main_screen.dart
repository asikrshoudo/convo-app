import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/constants.dart';
import '../core/update_service.dart';
import 'chats/chats_screen.dart';
import 'friends/friends_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart';
import 'notifications_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver {
  int _idx = 0;
  bool _hasUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    _setupFCM();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final hasUpdate = await UpdateService.hasUpdate();
      if (mounted) setState(() => _hasUpdate = hasUpdate);
      if (hasUpdate) UpdateService.checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnline(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _setOnline(true);
    } else if (s == AppLifecycleState.paused ||
               s == AppLifecycleState.inactive ||
               s == AppLifecycleState.detached) {
      _setOnline(false);
    }
  }

  Future<void> _setOnline(bool v) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    await db.collection('users').doc(uid).update({
      'isOnline': v,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _setupFCM() async {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    final uid   = auth.currentUser?.uid;
    if (uid != null && token != null) {
      await db.collection('users').doc(uid)
          .update({'fcmToken': token});
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final u = auth.currentUser?.uid;
      if (u != null) {
        db.collection('users').doc(u)
            .update({'fcmToken': newToken});
      }
    });
    FirebaseMessaging.onMessage.listen((msg) {
      if (!mounted) return;
      final n = msg.notification;
      if (n != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: kAccent.withOpacity(0.15),
                shape: BoxShape.circle),
              child: const Icon(Icons.notifications_rounded,
                  color: kAccent, size: 16)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary, fontSize: 13)),
                if (n.body != null)
                  Text(n.body!,
                    style: const TextStyle(
                        color: kTextSecondary, fontSize: 12)),
              ])),
          ]),
          backgroundColor: kCard2,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14))));
      }
    });
  }

  // ── Badge helpers ─────────────────────────────────────────────────────────
  // Simple dot badge (for Friends, Settings)
  Widget _badge(Widget icon, {bool show = false}) {
    if (!show) return icon;
    return Stack(clipBehavior: Clip.none, children: [
      icon,
      Positioned(
        right: -3, top: -3,
        child: Container(
          width: 9, height: 9,
          decoration: BoxDecoration(
            color: kRed,
            shape: BoxShape.circle,
            border: Border.all(color: kDark, width: 1.5)))),
    ]);
  }

  // Count badge (for Chats — shows number up to 9+)
  Widget _countBadge(Widget icon, int count) {
    if (count <= 0) return icon;
    final label = count > 9 ? '9+' : count.toString();
    return Stack(clipBehavior: Clip.none, children: [
      icon,
      Positioned(
        right: -6, top: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: kRed,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kDark, width: 1.5)),
          child: Text(label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold)))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;
    return Scaffold(
      backgroundColor: kDark,
      appBar: _idx == 0
        ? AppBar(
            backgroundColor: kDark,
            elevation: 0,
            centerTitle: false,
            title: const Text('Convo',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                letterSpacing: -0.5,
                color: kTextPrimary)),
            actions: [
              // Notification bell
              StreamBuilder<QuerySnapshot>(
                stream: db.collection('notifications')
                  .where('uid', isEqualTo: uid)
                  .where('read', isEqualTo: false)
                  .snapshots(),
                builder: (_, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  return Stack(children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const NotificationsScreen()))),
                    if (count > 0)
                      Positioned(
                        right: 8, top: 8,
                        child: Container(
                          width: 16, height: 16,
                          decoration: const BoxDecoration(
                              color: kRed, shape: BoxShape.circle),
                          child: Center(
                            child: Text(
                              count > 9 ? '9+' : count.toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight:
                                      FontWeight.bold))))),
                  ]);
                }),
            ])
        : null,

      body: IndexedStack(index: _idx, children: [
        const ChatsScreen(),
        const FriendsScreen(),
        ProfileScreen(uid: uid),
        const SettingsScreen(),
      ]),

      bottomNavigationBar: StreamBuilder<QuerySnapshot>(
        // Unread messages badge for Chats tab
        stream: db.collection('notifications')
          .where('uid', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .where('data.type', whereIn: ['dm', 'group'])
          .snapshots(),
        builder: (_, chatSnap) {
          final hasUnreadChat = (chatSnap.data?.docs.length ?? 0) > 0;
          return StreamBuilder<QuerySnapshot>(
            // Pending friend requests badge for Friends tab
            stream: db.collection('friendRequests')
              .where('toUid', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
            builder: (_, friendSnap) {
              final hasFriendReq = (friendSnap.data?.docs.length ?? 0) > 0;
              return Container(
                decoration: const BoxDecoration(
                  color: kCard,
                  border: Border(top: BorderSide(color: kDivider, width: 0.5)),
                ),
                child: NavigationBar(
                  selectedIndex: _idx,
                  onDestinationSelected: (i) => setState(() => _idx = i),
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  indicatorColor: kAccent.withOpacity(0.15),
                  height: 64,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    NavigationDestination(
                      icon: _countBadge(
                        const Icon(Icons.chat_bubble_outline_rounded,
                          color: kTextSecondary),
                        hasUnreadChat ? (chatSnap.data?.docs.length ?? 0) : 0),
                      selectedIcon: _countBadge(
                        const Icon(Icons.chat_bubble_rounded, color: kAccent),
                        hasUnreadChat ? (chatSnap.data?.docs.length ?? 0) : 0),
                      label: 'Chats'),
                    NavigationDestination(
                      icon: _badge(
                        const Icon(Icons.people_outline_rounded,
                          color: kTextSecondary),
                        show: hasFriendReq),
                      selectedIcon: _badge(
                        const Icon(Icons.people_rounded, color: kAccent),
                        show: hasFriendReq),
                      label: 'Friends'),
                    const NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded,
                        color: kTextSecondary),
                      selectedIcon: Icon(Icons.person_rounded, color: kAccent),
                      label: 'Profile'),
                    NavigationDestination(
                      icon: _badge(
                        const Icon(Icons.settings_outlined,
                          color: kTextSecondary),
                        show: _hasUpdate),
                      selectedIcon: _badge(
                        const Icon(Icons.settings_rounded, color: kAccent),
                        show: _hasUpdate),
                      label: 'Settings'),
                  ]));
            });
        }),
    );
  }
}
