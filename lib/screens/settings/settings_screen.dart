import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../widgets/common_widgets.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';
import 'contact_sync_screen.dart';
import 'app_version_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;


  bool   _suggestions  = true, _friendsPublic = true;
  String _profileMode  = 'friend';
  Map<String, dynamic>? _user;
  final  _myUid = auth.currentUser!.uid;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final doc = await db.collection('users').doc(_myUid).get();
    if (!mounted) return;
    setState(() {
      _user          = doc.data();
      _suggestions   = doc.data()?['suggestionsEnabled'] ?? true;
      _friendsPublic = doc.data()?['friendsPublic']      ?? true;
      _profileMode   = doc.data()?['profileMode']        ?? 'friend';
    });
  }

  Future<void> _signOut() async {
    await db.collection('users').doc(_myUid).update({'isOnline': false});
    await auth.signOut();
    if (mounted) Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _deleteAccount(BuildContext context) async {

    // Step 1: Confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? kCard : kLightCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Account',
          style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
        content: Text(
          'This will permanently delete your account and all your data. This cannot be undone.',
          style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
              style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white))),
        ]));
    if (confirm != true) return;

    // Step 2: Re-authenticate if email user
    final isEmailUser = auth.currentUser?.providerData
        .any((p) => p.providerId == 'password') == true;
    if (isEmailUser) {
      final passCtrl = TextEditingController();
      final reauth = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: isDark ? kCard : kLightCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
          title: Text('Confirm Password',
            style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
          content: _inputField(passCtrl, 'Enter your password',
            icon: Icons.lock_outline_rounded, obscure: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm',
                style: TextStyle(color: Colors.white))),
          ]));
      if (reauth != true) return;
      try {
        final cred = EmailAuthProvider.credential(
          email: auth.currentUser!.email!, password: passCtrl.text);
        await auth.currentUser!.reauthenticateWithCredential(cred);
      } on FirebaseAuthException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Wrong password'),
            backgroundColor: kRed));
        return;
      }
    }

    try {
      // Delete Firestore user data
      await db.collection('users').doc(_myUid).delete();
      // Delete Firebase Auth account
      await auth.currentUser!.delete();
      if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Error deleting account'),
          backgroundColor: kRed));
    }
  }

  Future<void> _update(Map<String, dynamic> data) =>
    db.collection('users').doc(_myUid).update(data);

  @override
  Widget build(BuildContext context) {
    final name       = _user?['name']     as String? ?? 'User';
    final username   = _user?['username'] as String? ?? '';
    final phone      = _user?['phone']    as String? ?? '';
    final phone2     = _user?['phone2']   as String? ?? '';
    final isVerified = _user?['verified'] == true;
    final onWaitlist = _user?['verifiedWaitlist'] == true;
    final currentEmail = auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        elevation: 0, scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text('Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
      body: ListView(children: [

        // ── Profile card ──────────────────────────────────────────────────
        GestureDetector(
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid))),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? kCard : kLightCard,
              borderRadius: BorderRadius.circular(kCardRadius),
              border: Border.all(color: kAccent.withOpacity(0.25))),
            child: Row(children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: kAccent, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: kAccent.withOpacity(0.4), blurRadius: 12)]),
                child: Center(child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.bold)))),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(name,
                    style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText),
                    overflow: TextOverflow.ellipsis)),
                  if (isVerified) ...[ const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded,
                      color: kAccent, size: 16)],
                ]),
                if (username.isNotEmpty)
                  Text('@$username',
                    style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
                const SizedBox(height: 2),
                const Text('View profile',
                  style: TextStyle(color: kAccent, fontSize: 12,
                    fontWeight: FontWeight.w500)),
              ])),
              Icon(Icons.arrow_forward_ios_rounded,
                color: isDark ? kTextSecondary : kLightTextSub, size: 14),
            ]))),

        // ── Account ───────────────────────────────────────────────────────
        _sec('Account'),
        _tile(Icons.person_rounded, 'Edit Profile', 'Name, bio, socials',
          () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid)))),
        _tile(Icons.email_rounded, 'Change Email',
          currentEmail.isNotEmpty ? currentEmail : 'No email',
          () => _changeEmail(context)),
        _tile(Icons.phone_rounded, 'Primary Phone',
          phone.isNotEmpty ? phone : 'Add phone number',
          () => _addPhone(context, primary: true)),
        _tile(Icons.phone_in_talk_rounded, 'Secondary Phone',
          phone2.isNotEmpty ? phone2 : 'Add 2nd phone',
          () => _addPhone(context, primary: false)),
        _tile(Icons.contacts_rounded, 'Sync Contacts',
          'Find friends from your contacts',
          () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ContactSyncScreen()))),
        // Only show Change Password for email/password users (not GitHub/Google)
        if (auth.currentUser?.providerData
            .any((p) => p.providerId == 'password') == true)
          _tile(Icons.lock_rounded, 'Change Password', 'Update your password',
            () => _changePass(context)),
        _tile(Icons.verified_rounded, 'Get Verified',
          isVerified ? 'You are verified ✓'
            : (onWaitlist ? 'On waitlist' : 'Join the waitlist'),
          () => _verify(context)),

        // ── Profile Mode ──────────────────────────────────────────────────
        _sec('Profile Mode'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? kCard : kLightCard, borderRadius: BorderRadius.circular(14)),
          child: Row(children: ['friend', 'follow'].map((mode) {
            final selected = _profileMode == mode;
            final label    = mode == 'friend' ? 'Friend Mode' : 'Follow Mode';
            return Expanded(child: GestureDetector(
              onTap: () {
                setState(() => _profileMode = mode);
                _update({'profileMode': mode});
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? kAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(label, style: TextStyle(
                  color: selected ? Colors.white : isDark ? kTextSecondary : kLightTextSub,
                  fontWeight: FontWeight.w600, fontSize: 13))))));
          }).toList())),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _profileMode == 'friend'
              ? 'Others can send you friend requests and message you.'
              : 'Others can follow you. Use for public/creator profiles.',
            style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12))),

        // ── Privacy ───────────────────────────────────────────────────────
        _sec('Privacy'),
        _switchTile(Icons.people_rounded, 'Public Friends List',
          'Show your friends on your profile',
          _friendsPublic, (v) {
            setState(() => _friendsPublic = v);
            _update({'friendsPublic': v});
          }),
        _tile(Icons.block_rounded, 'Blocked Users',
          'Manage blocked accounts',
          () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BlockedUsersScreen()))),

        // ── Discovery ─────────────────────────────────────────────────────
        _sec('Discovery'),
        _switchTile(Icons.person_search_rounded, 'Account Suggestions',
          'Suggest your profile to others',
          _suggestions, (v) {
            setState(() => _suggestions = v);
            _update({'suggestionsEnabled': v});
          }),

        // ── Preferences ───────────────────────────────────────────────────
        _sec('Preferences'),
        _tile(Icons.palette_rounded, 'Appearance', 'Theme and accent color',
          () => _showThemeDialog(context)),
        _tile(Icons.notifications_rounded, 'Notifications',
          'Manage push alerts', () {}),

        // ── About ─────────────────────────────────────────────────────────
        _sec('About'),
        _tile(Icons.favorite_rounded, 'Powered by TheKami', 'thekami.tech',
          () => launchUrl(Uri.parse('https://thekami.tech'),
            mode: LaunchMode.externalApplication)),
        // ← App Version now opens its own screen
        _tile(Icons.system_update_rounded, 'App Version',
          'Check for updates',
          () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AppVersionScreen()))),

        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _signOut,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kRed.withOpacity(0.3))),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.logout_rounded, color: kRed, size: 20),
                SizedBox(width: 8),
                Text('Sign Out', style: TextStyle(color: kRed,
                  fontWeight: FontWeight.w600, fontSize: 15)),
              ])))),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => _deleteAccount(context),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kRed.withOpacity(0.2))),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.delete_forever_rounded, color: kRed, size: 20),
                SizedBox(width: 8),
                Text('Delete Account', style: TextStyle(color: kRed,
                  fontWeight: FontWeight.w500, fontSize: 15)),
              ])))),
        const SizedBox(height: 40),
      ]));
  }

  // ─── Section header ─────────────────────────────────────────────────────
  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
    child: Text(t.toUpperCase(), style: const TextStyle(
      color: kAccent, fontSize: 11,
      fontWeight: FontWeight.bold, letterSpacing: 1.4)));

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) =>
    ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: iconBox(icon),
      title: Text(title, style: TextStyle(
        fontWeight: FontWeight.w500, color: isDark ? kTextPrimary : kLightText, fontSize: 14)),
      subtitle: Text(sub,
        style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12),
        maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded,
        color: isDark ? kTextSecondary : kLightTextSub, size: 20),
      onTap: onTap);

  Widget _switchTile(IconData icon, String title, String sub,
      bool value, ValueChanged<bool> onChanged) =>
    ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: iconBox(icon),
      title: Text(title, style: TextStyle(
        fontWeight: FontWeight.w500, color: isDark ? kTextPrimary : kLightText, fontSize: 14)),
      subtitle: Text(sub,
        style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
      trailing: Switch.adaptive(
        value: value, onChanged: onChanged, activeColor: kAccent));

  // ─── Email change ──────────────────────────────────────────────────────
  void _changeEmail(BuildContext context) {

    final emailCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    String? _pendingEmail;
    bool _codeSent = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHandle(),
            const SizedBox(height: 20),
            Text('Change Email', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
            const SizedBox(height: 16),
            if (!_codeSent) ...[
              _inputField(emailCtrl, 'New email address',
                icon: Icons.email_outlined,
                type: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _inputField(passCtrl, 'Current password',
                icon: Icons.lock_outline_rounded, obscure: true),
              const SizedBox(height: 16),
              _actionButton('Send Verification Email', () async {
                final newEmail = emailCtrl.text.trim();
                final pass     = passCtrl.text;
                if (newEmail.isEmpty || pass.isEmpty) return;
                try {
                  final cred = EmailAuthProvider.credential(
                    email: auth.currentUser!.email!, password: pass);
                  await auth.currentUser!.reauthenticateWithCredential(cred);
                  _pendingEmail = newEmail;
                  final code = (100000 + Random().nextInt(900000)).toString();
                  await db.collection('users').doc(_myUid).update({
                    'pendingEmail': newEmail,
                    'emailVerifyCode': code,
                    'emailVerifyExpiry': Timestamp.fromDate(
                      DateTime.now().add(const Duration(minutes: 10))),
                  });
                  await auth.currentUser!.verifyBeforeUpdateEmail(newEmail);
                  setSt(() => _codeSent = true);
                } on FirebaseAuthException catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message ?? 'Error'),
                      backgroundColor: kRed));
                }
              }),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kAccent.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.mail_outline_rounded, color: kAccent),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Verification email sent!',
                      style: TextStyle(fontWeight: FontWeight.bold, color: kAccent)),
                    const SizedBox(height: 4),
                    Text('Click the link sent to $_pendingEmail',
                      style: TextStyle(fontSize: 12, color: isDark ? kTextSecondary : kLightTextSub)),
                  ])),
                ])),
              const SizedBox(height: 16),
              _actionButton('I verified my email', () async {
                await auth.currentUser!.reload();
                if (auth.currentUser!.email == _pendingEmail) {
                  await db.collection('users').doc(_myUid).update({
                    'email': _pendingEmail,
                    'pendingEmail': FieldValue.delete(),
                    'emailVerifyCode': FieldValue.delete(),
                    'emailVerifyExpiry': FieldValue.delete(),
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Email updated!'),
                      backgroundColor: kAccent));
                  }
                } else {
                  if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not verified yet.'),
                      backgroundColor: kOrange));
                }
              }),
              Center(child: TextButton(
                onPressed: () => setSt(() => _codeSent = false),
                child: Text('Use a different email',
                  style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)))),
            ],
          ]))));
  }

  void _addPhone(BuildContext context, {required bool primary}) {

    final field   = primary ? 'phone'  : 'phone2';
    final label   = primary ? 'Primary Phone' : 'Secondary Phone';
    final current = primary ? (_user?['phone'] ?? '') : (_user?['phone2'] ?? '');
    final ctrl    = TextEditingController(text: current);

    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: isDark ? kCard : kLightCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(label, style: TextStyle(
        fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
      content: _inputField(ctrl, '+880 1XXXXXXXXX',
        icon: primary ? Icons.phone_rounded : Icons.phone_in_talk_rounded,
        type: TextInputType.phone),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
          onPressed: () async {
            final phone      = ctrl.text.trim();
            final normalized = phone.replaceAll(RegExp(r'[\s\-()]'), '');
            final updateData = {field: phone};
            if (primary) updateData['phoneNormalized'] = normalized;
            await db.collection('users').doc(_myUid).update(updateData);
            if (mounted) { Navigator.pop(context); _load(); }
          },
          child: const Text('Save', style: TextStyle(color: Colors.white))),
      ]));
  }

  void _changePass(BuildContext context) {

    final c = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: isDark ? kCard : kLightCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Change Password',
        style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
      content: _inputField(c, 'New password (min 6)',
        icon: Icons.lock_outline_rounded, obscure: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
          onPressed: () async {
            if (c.text.length >= 6) {
              await auth.currentUser?.updatePassword(c.text);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Update', style: TextStyle(color: Colors.white))),
      ]));
  }

  void _verify(BuildContext context) {

    final onWaitlist = _user?['verifiedWaitlist'] == true;
    final verified   = _user?['verified']         == true;
    showModalBottomSheet(
      context: context, backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetHandle(), const SizedBox(height: 20),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.verified_rounded, color: kAccent, size: 36)),
          const SizedBox(height: 16),
          Text(verified ? 'You are Verified!' : 'Get Verified',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: isDark ? kTextPrimary : kLightText)),
          const SizedBox(height: 8),
          Text(
            verified ? 'Your account has a verified badge.'
              : onWaitlist ? 'You are on the waitlist. We\'ll notify you!'
              : 'Join the waitlist to get your verified badge.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
          const SizedBox(height: 24),
          if (!verified && !onWaitlist)
            _actionButton('Join Waitlist', () async {
              await db.collection('users').doc(_myUid)
                .update({'verifiedWaitlist': true});
              await db.collection('verify_waitlist').doc(_myUid).set({
                'uid': _myUid, 'name': _user?['name'],
                'username': _user?['username'],
                'joinedAt': FieldValue.serverTimestamp()});
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Added to waitlist!'),
                  backgroundColor: kAccent));
                _load();
              }
            }),
          if (verified || onWaitlist)
            _actionButton(
              verified ? 'Awesome!' : 'On Waitlist ✓',
              () => Navigator.pop(context)),
        ])));
  }

  void _showThemeDialog(BuildContext context) {

    showModalBottomSheet(
      context: context, backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: _sheetHandle()),
            const SizedBox(height: 16),
            Center(child: Text('Appearance', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText))),
            const SizedBox(height: 24),
            const Text('THEME', style: TextStyle(color: kAccent, fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 1.4)),
            const SizedBox(height: 10),
            Row(children: [
              [ThemeMode.dark,   Icons.dark_mode_rounded,       'Dark'],
              [ThemeMode.light,  Icons.light_mode_rounded,      'Light'],
              [ThemeMode.system, Icons.brightness_auto_rounded, 'System'],
            ].map((opt) {
              final mode     = opt[0] as ThemeMode;
              final icon     = opt[1] as IconData;
              final label    = opt[2] as String;
              final selected = themeNotifier.value == mode;
              return Expanded(child: GestureDetector(
                onTap: () async {
                  themeNotifier.value = mode;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('themeMode',
                    [ThemeMode.system, ThemeMode.dark, ThemeMode.light]
                      .indexOf(mode));
                  setSt(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? kAccent : isDark ? kCard2 : kLightCard2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? kAccent : isDark ? kDivider : kLightDivider, width: 1.5)),
                  child: Column(children: [
                    Icon(icon,
                      color: selected ? Colors.white : isDark ? kTextSecondary : kLightTextSub,
                      size: 22),
                    const SizedBox(height: 5),
                    Text(label, style: TextStyle(
                      color: selected ? Colors.white : isDark ? kTextSecondary : kLightTextSub,
                      fontSize: 11, fontWeight: FontWeight.w600)),
                  ]))));
            }).toList()),
            const SizedBox(height: 8),
          ]))));
  }

  Widget _sheetHandle() => Container(
    width: 36, height: 4,
    decoration: BoxDecoration(
      color: isDark ? kTextTertiary : kLightTextSub, borderRadius: BorderRadius.circular(2)));

  Widget _inputField(TextEditingController ctrl, String hint, {
    IconData? icon, bool obscure = false, TextInputType? type}) =>
    TextField(
      controller: ctrl, obscureText: obscure, keyboardType: type,
      style: TextStyle(color: isDark ? kTextPrimary : kLightText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? kTextSecondary : kLightTextSub),
        prefixIcon: icon != null
          ? Icon(icon, color: isDark ? kTextSecondary : kLightTextSub, size: 20) : null,
        filled: true, fillColor: isDark ? kCard2 : kLightCard2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAccent))));

  Widget _actionButton(String label, VoidCallback onTap) =>
    SizedBox(width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent, elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14))),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15))));
}

// ─────────────────────────────────────────────────────────────────────────────
// Blocked Users Screen
// ─────────────────────────────────────────────────────────────────────────────
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        title: const Text('Blocked Users',
          style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('users').doc(myUid)
          .collection('blocked').snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(
              color: kAccent, strokeWidth: 2));
          }
          if (snap.data!.docs.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: isDark ? kCard : kLightCard, shape: BoxShape.circle),
                child: Icon(Icons.block_rounded,
                  color: isDark ? kTextSecondary : kLightTextSub, size: 32)),
              const SizedBox(height: 16),
              Text('No blocked users',
                style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 16, color: isDark ? kTextPrimary : kLightText)),
              const SizedBox(height: 6),
              Text('Users you block won\'t find your profile',
                style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
            ]));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: snap.data!.docs.length,
            separatorBuilder: (_, __) =>
              Divider(height: 0, color: isDark ? kDivider : kLightDivider, indent: 72),
            itemBuilder: (_, i) {
              final doc      = snap.data!.docs[i];
              final blockedUid = doc.id;

              return FutureBuilder<DocumentSnapshot>(
                future: db.collection('users').doc(blockedUid).get(),
                builder: (_, uSnap) {
                  final u = uSnap.data?.data() as Map<String, dynamic>? ?? {};
                  final name     = u['name']     as String? ?? 'User';
                  final username = u['username'] as String? ?? '';
                  final avatar   = u['avatar']   as String? ?? '?';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? kCard2 : kLightCard2, shape: BoxShape.circle),
                      child: Center(child: Text(avatar,
                        style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub,
                          fontWeight: FontWeight.bold, fontSize: 16)))),
                    title: Text(name, style: TextStyle(
                      fontWeight: FontWeight.w600, color: isDark ? kTextPrimary : kLightText)),
                    subtitle: username.isNotEmpty
                      ? Text('@$username',
                          style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub,
                            fontSize: 12))
                      : null,
                    trailing: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: kAccent.withOpacity(0.6)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: isDark ? kCard : kLightCard,
                            title: Text('Unblock user?',
                              style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
                            content: Text('Unblock $name?',
                              style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kAccent),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Unblock',
                                  style: TextStyle(color: Colors.white))),
                            ]));
                        if (confirm == true) {
                          await db.collection('users').doc(myUid)
                            .collection('blocked').doc(blockedUid).delete();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$name unblocked'),
                                backgroundColor: kAccent));
                          }
                        }
                      },
                      child: const Text('Unblock',
                        style: TextStyle(color: kAccent, fontSize: 13))));
                });
            });
        }));
  }
}
