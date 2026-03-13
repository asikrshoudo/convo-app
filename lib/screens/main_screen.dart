import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/constants.dart';
import '../core/update_service.dart';
import 'chats/chats_screen.dart';
import 'friends/friends_screen.dart';
import 'notifications_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;


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
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? kTextPrimary : kLightText, fontSize: 13)),
                if (n.body != null)
                  Text(n.body!,
                    style: TextStyle(
                        color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
              ])),
          ]),
          backgroundColor: isDark ? kCard2 : kLightCard2,
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
            border: Border.all(color: isDark ? kDark : kLightBg, width: 1.5)))),
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
            border: Border.all(color: isDark ? kDark : kLightBg, width: 1.5)),
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: isDark ? kCard : kLightCard)
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: isDark ? kCard : kLightCard),
      child: Scaffold(
        backgroundColor: isDark ? kDark : kLightBg,
        body: IndexedStack(index: _idx, children: [
          const ChatsScreen(),
          const FriendsScreen(),
        ]),
        bottomNavigationBar: _buildNavBar(uid),
      ));
  }

  Widget _buildNavBar(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('friend_requests')
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots(),
      builder: (_, friendSnap) {
        final hasFriendReq = (friendSnap.data?.docs.length ?? 0) > 0;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? kCard : kLightCard,
            border: Border(
              top: BorderSide(
                color: isDark ? kDivider : kLightDivider,
                width: 0.5))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    activeIcon: Icons.chat_bubble_rounded,
                    label: 'Chats',
                    index: 0,
                    badge: false),
                  _navItem(
                    icon: Icons.search_rounded,
                    activeIcon: Icons.search_rounded,
                    label: 'Find',
                    index: 1,
                    badge: hasFriendReq),
                ]))));
      });
  }

  Widget _navItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required bool badge,
  }) {
    final active = _idx == index;
    final color  = active ? kAccent
      : isDark ? kTextSecondary : kLightTextSub;

    return GestureDetector(
      onTap: () => setState(() => _idx = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kAccent.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(14)),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                active ? activeIcon : icon,
                key: ValueKey(active),
                color: color, size: 24)),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: color, fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2),
              child: Text(label)),
          ]),
          if (badge)
            Positioned(right: -4, top: -2,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: kRed,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? kDark : kLightBg,
                    width: 1.5)))),
        ])));
  }
}
