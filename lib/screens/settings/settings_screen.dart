import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../widgets/common_widgets.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';
import 'contact_sync_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool   _suggestions  = true, _friendsPublic = true;
  String _profileMode  = 'friend';
  Map<String, dynamic>? _user;
  final  _myUid = auth.currentUser!.uid;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final doc = await db.collection('users').doc(_myUid).get();
    if (mounted) setState(() {
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

  Future<void> _update(Map<String, dynamic> data) async =>
      db.collection('users').doc(_myUid).update(data);

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final onWaitlist = _user?['verifiedWaitlist'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)), elevation: 0),
      body: StreamBuilder<DocumentSnapshot>(
        stream: db.collection('users').doc(_myUid).snapshots(),
        builder: (_, snap) {
          if (snap.hasData && snap.data!.exists) {
            final d = snap.data!.data() as Map<String, dynamic>;
            if (_user == null || d['name'] != _user!['name'] || d['phone'] != _user!['phone']) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {
                  _user          = d;
                  _suggestions   = d['suggestionsEnabled'] ?? true;
                  _friendsPublic = d['friendsPublic']      ?? true;
                  _profileMode   = d['profileMode']        ?? 'friend';
                });
              });
            }
          }
          final name       = snap.data?.get('name')     as String? ?? _user?['name']     as String? ?? 'User';
          final username   = snap.data?.get('username') as String? ?? _user?['username'] as String? ?? '';
          final phone      = snap.data?.get('phone')    as String? ?? _user?['phone']    as String? ?? '';
          final isVerified = snap.data?.get('verified') == true || (_user?['verified'] == true);

          return ListView(children: [
            // Profile card
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid))),
              child: Container(
                margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [kGreen.withOpacity(0.15), kGreen.withOpacity(0.05)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kGreen.withOpacity(0.3))),
                child: Row(children: [
                  CircleAvatar(radius: 28, backgroundColor: kGreen,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified_rounded, color: kGreen, size: 16)],
                    ]),
                    if (username.isNotEmpty) Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    const Text('View profile', style: TextStyle(color: kGreen, fontSize: 11)),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                ]))),

            _sec('Account'),
            _tile(Icons.person_rounded, 'Edit Profile', 'Name, bio, socials',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid)))),
            _tile(Icons.phone_rounded, 'Phone Number', phone.isNotEmpty ? phone : 'Add phone number',
              () => _addPhone(context)),
            _tile(Icons.contacts_rounded, 'Sync Contacts', 'Find friends from your contacts',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactSyncScreen()))),
            _tile(Icons.lock_rounded, 'Change Password', 'Update your password',
              () => _changePass(context)),
            _tile(Icons.verified_rounded, 'Get Verified',
              isVerified ? 'You are verified!' : (onWaitlist ? 'On waitlist' : 'Join the waitlist'),
              () => _verify(context)),

            _sec('Profile Mode'),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? kCard : Colors.grey[100],
                borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () { setState(() => _profileMode = 'friend'); _update({'profileMode': 'friend'}); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _profileMode == 'friend' ? kGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('Friend Mode',
                      style: TextStyle(color: _profileMode == 'friend' ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.w600, fontSize: 13)))))),
                Expanded(child: GestureDetector(
                  onTap: () { setState(() => _profileMode = 'follow'); _update({'profileMode': 'follow'}); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _profileMode == 'follow' ? kGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('Follow Mode',
                      style: TextStyle(color: _profileMode == 'follow' ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.w600, fontSize: 13)))))),
              ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _profileMode == 'friend'
                  ? 'Others can send you friend requests and message you.'
                  : 'Others can follow you. Use for public/creator profiles.',
                style: TextStyle(color: Colors.grey[500], fontSize: 12))),

            _sec('Privacy'),
            SwitchListTile(
              value: _friendsPublic, onChanged: (v) { setState(() => _friendsPublic = v); _update({'friendsPublic': v}); },
              activeColor: kGreen, secondary: iconBox(Icons.people_rounded),
              title: const Text('Public Friends List', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('Show your friends on your profile', style: TextStyle(color: Colors.grey[500], fontSize: 12))),

            _sec('Discovery'),
            SwitchListTile(
              value: _suggestions, onChanged: (v) { setState(() => _suggestions = v); _update({'suggestionsEnabled': v}); },
              activeColor: kGreen, secondary: iconBox(Icons.person_search_rounded),
              title: const Text('Account Suggestions', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('Suggest your profile to others', style: TextStyle(color: Colors.grey[500], fontSize: 12))),

            _sec('Preferences'),
            _tile(Icons.notifications_rounded, 'Notifications', 'Manage push alerts', () {}),
            _tile(Icons.palette_rounded, 'Appearance', 'Theme and colors', () => _showThemeDialog(context)),
            _tile(Icons.language_rounded, 'Language', 'Bangla / English', () {}),

            _sec('About'),
            _tile(Icons.favorite_rounded, 'Powered by TheKami', 'thekami.tech',
              () => launchUrl(Uri.parse('https://thekami.tech'), mode: LaunchMode.externalApplication)),
            _tile(Icons.info_rounded, 'App Version', 'Convo v1.0.2', () {}),

            const SizedBox(height: 16),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1), elevation: 0,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.logout_rounded, color: Colors.red),
                label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                onPressed: _signOut)),
            const SizedBox(height: 32),
          ]);
        }));
  }

  // ─── Dialogs / sheets ────────────────────────────────────────────────────
  void _showThemeDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Center(child: Text('Appearance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          const SizedBox(height: 20),

          // ── Theme mode ──
          const Text('THEME', style: TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
          const SizedBox(height: 8),
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
                  [ThemeMode.system, ThemeMode.dark, ThemeMode.light].indexOf(mode));
                setSt(() {});
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? accentColorNotifier.value : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? accentColorNotifier.value : Colors.grey.withOpacity(0.3),
                    width: 1.5)),
                child: Column(children: [
                  Icon(icon, color: selected ? Colors.white : Colors.grey, size: 20),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(
                    color: selected ? Colors.white : Colors.grey,
                    fontSize: 11, fontWeight: FontWeight.w600)),
                ]))));
          }).toList()),

          const SizedBox(height: 24),

          // ── Accent color ──
          const Text('ACCENT COLOR', style: TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: kAccentColors.entries.map((e) {
              final selected = accentColorNotifier.value.value == e.value.value;
              return GestureDetector(
                onTap: () async {
                  accentColorNotifier.value = e.value;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('accentColor', e.value.value);
                  setSt(() {});
                  if (mounted) setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: e.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 3),
                    boxShadow: selected ? [BoxShadow(color: e.value.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)] : []),
                  child: selected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                    : null));
            }).toList()),

          const SizedBox(height: 8),
        ]))));
  }

  void _addPhone(BuildContext context) {
    final ctrl = TextEditingController(text: _user?['phone'] ?? '');
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Phone Number'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrl, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '+880 1XXXXXXXXX',
            prefixIcon: Icon(Icons.phone_rounded),
            border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Text('Optional. Used so your contacts can find you on Convo.',
          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final phone      = ctrl.text.trim();
            final normalized = phone.replaceAll(RegExp(r'[\s\-()]'), '');
            await db.collection('users').doc(_myUid).update({'phone': phone, 'phoneNormalized': normalized});
            if (mounted) Navigator.pop(context);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Phone number saved!'), backgroundColor: kGreen));
          },
          child: const Text('Save', style: TextStyle(color: kGreen))),
      ]));
  }

  void _changePass(BuildContext context) {
    final c = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(controller: c, obscureText: true,
        decoration: InputDecoration(hintText: 'New password (min 6)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGreen)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Icon(Icons.verified_rounded, color: kGreen, size: 48),
        const SizedBox(height: 12),
        Text(verified ? 'You are Verified!' : 'Get Verified',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(verified ? 'Your account has a blue badge.'
          : onWaitlist ? 'You are on the waitlist. We will notify you!'
          : 'Join the waitlist to get your blue badge.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400])),
        const SizedBox(height: 24),
        if (!verified && !onWaitlist) primaryButton('Join Waitlist', () async {
          await db.collection('users').doc(_myUid).update({'verifiedWaitlist': true});
          await db.collection('verify_waitlist').doc(_myUid).set({
            'uid': _myUid, 'name': _user?['name'], 'username': _user?['username'],
            'joinedAt': FieldValue.serverTimestamp()});
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Added to waitlist!'), backgroundColor: kGreen));
            _load();
          }
        }),
        if (verified || onWaitlist)
          primaryButton(verified ? 'Awesome!' : 'On Waitlist', () => Navigator.pop(context)),
      ])));
  }

  // ─── Widget helpers ──────────────────────────────────────────────────────
  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t.toUpperCase(),
      style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4)));

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
    leading: iconBox(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(sub, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
    onTap: onTap);
}
