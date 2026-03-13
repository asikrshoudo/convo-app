import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants.dart';
import '../profile/profile_screen.dart';

class ContactSyncScreen extends StatefulWidget {
  const ContactSyncScreen({super.key});
  @override State<ContactSyncScreen> createState() => _ContactSyncScreenState();
}

class _ContactSyncScreenState extends State<ContactSyncScreen> {
  final _myUid = auth.currentUser!.uid;
  bool _loading = false, _permissionDenied = false, _synced = false;
  List<_ContactResult> _results = [];

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('880') && digits.length == 13) return '+$digits';
    if (digits.startsWith('0')   && digits.length == 11) return '+88$digits';
    if (digits.length == 10)  return '+880$digits';
    if (digits.length > 7)    return '+$digits';
    return '';
  }

  Future<void> _sync() async {
    setState(() { _loading = true; _permissionDenied = false; });
    try {
      final status = await Permission.contacts.request();
      if (!status.isGranted) {
        setState(() { _permissionDenied = true; _loading = false; }); return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final Map<String, String> phoneToName = {};
      for (final c in contacts) {
        for (final p in c.phones) {
          final norm = _normalizePhone(p.number);
          if (norm.isNotEmpty) phoneToName[norm] = c.displayName;
        }
      }
      final List<_ContactResult> found = [];
      if (phoneToName.isNotEmpty) {
        final keys = phoneToName.keys.toList();
        for (int i = 0; i < keys.length; i += 10) {
          final batch = keys.sublist(i, (i + 10).clamp(0, keys.length));
          final snap  = await db.collection('users').where('phoneNormalized', whereIn: batch).get();
          for (final doc in snap.docs) {
            if (doc.id == _myUid) continue;
            final d = doc.data();
            found.add(_ContactResult(
              uid: doc.id,
              name: d['name'] ?? 'User',
              username: d['username'] ?? '',
              avatar: d['avatar'] ?? '?',
              contactName: phoneToName[d['phoneNormalized'] ?? ''] ?? '',
              isOnline: d['isOnline'] == true));
          }
        }
      }
      setState(() { _results = found; _synced = true; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _addFriend(String uid, String name) async {
    final fd = await db.collection('users').doc(_myUid).collection('friends').doc(uid).get();
    if (fd.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already friends!'), backgroundColor: kGreen));
      return;
    }
    final ex = await db.collection('friend_requests')
      .where('from', isEqualTo: _myUid).where('to', isEqualTo: uid).where('status', isEqualTo: 'pending').get();
    if (ex.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request already sent!')));
      return;
    }
    final my = await db.collection('users').doc(_myUid).get();
    await db.collection('friend_requests').add({
      'from': _myUid, 'fromName': my.data()?['name'] ?? 'User', 'fromAvatar': my.data()?['avatar'] ?? 'U',
      'to': uid, 'toName': name, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Friend request sent to $name ✅'), backgroundColor: kGreen));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        elevation: 0, scrolledUnderElevation: 0,
        title: Text('Sync Contacts', style: TextStyle(
          fontWeight: FontWeight.bold, fontSize: 20,
          color: isDark ? kTextPrimary : kLightText))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // ── Info + sync card ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF34C759).withOpacity(0.14),
                  const Color(0xFF34C759).withOpacity(0.04)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF34C759).withOpacity(0.25))),
            child: Column(children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withOpacity(0.15),
                  shape: BoxShape.circle),
                child: const Icon(Icons.contacts_rounded,
                  color: Color(0xFF34C759), size: 32)),
              const SizedBox(height: 14),
              Text('Find Friends from Contacts',
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold,
                  color: isDark ? kTextPrimary : kLightText)),
              const SizedBox(height: 8),
              Text(
                'Convo checks which contacts use the app.\nYour contacts are never uploaded or stored.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub,
                  fontSize: 13, height: 1.5)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34C759),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
                  icon: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.sync_rounded,
                        color: Colors.white, size: 20),
                  label: Text(
                    _loading ? 'Scanning...'
                      : (_synced ? 'Sync Again' : 'Sync Contacts'),
                    style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: _loading ? null : _sync)),
            ])),

          const SizedBox(height: 14),

          // ── Permission denied ──────────────────────────────────────────
          if (_permissionDenied)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kRed.withOpacity(0.25))),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: kRed.withOpacity(0.12),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.block_rounded,
                    color: kRed, size: 18)),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  'Permission denied. Go to:\nSettings → Apps → Convo → Permissions → Contacts',
                  style: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 12, height: 1.5))),
              ])),

          // ── Results header ─────────────────────────────────────────────
          if (_synced && !_loading) ...[
            const SizedBox(height: 12),
            Row(children: [
              Text(
                _results.isEmpty
                  ? 'No contacts found on Convo'
                  : '${_results.length} contact${_results.length == 1 ? '' : 's'} on Convo',
                style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14,
                  color: isDark ? kTextPrimary : kLightText)),
            ]),
            const SizedBox(height: 8),
          ],

          // ── List ──────────────────────────────────────────────────────
          Expanded(child: _results.isEmpty && _synced && !_loading
            ? Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: isDark ? kCard : kLightCard,
                      shape: BoxShape.circle),
                    child: Icon(Icons.person_search_rounded,
                      size: 36,
                      color: isDark ? kTextSecondary : kLightTextSub)),
                  const SizedBox(height: 16),
                  Text('None of your contacts\nare on Convo yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? kTextSecondary : kLightTextSub,
                      fontSize: 15)),
                  const SizedBox(height: 8),
                  const Text('Invite them!',
                    style: TextStyle(
                      color: Color(0xFF34C759),
                      fontSize: 13, fontWeight: FontWeight.w600)),
                ]))
            : ListView.separated(
                padding: const EdgeInsets.only(top: 4),
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(
                  height: 0, indent: 72,
                  color: isDark ? kDivider : kLightDivider),
                itemBuilder: (_, i) {
                  final r = _results[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 4),
                    leading: Stack(children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: kAccent.withOpacity(0.18),
                        child: Text(r.avatar,
                          style: const TextStyle(color: kAccent,
                            fontWeight: FontWeight.bold, fontSize: 16))),
                      Positioned(right: 0, bottom: 0,
                        child: Container(
                          width: 13, height: 13,
                          decoration: BoxDecoration(
                            color: r.isOnline
                              ? const Color(0xFF34C759)
                              : isDark ? kCard2 : kLightCard2,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? kDark : kLightBg,
                              width: 2)))),
                    ]),
                    title: Text(r.name, style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14,
                      color: isDark ? kTextPrimary : kLightText)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${r.username}', style: TextStyle(
                          color: isDark ? kTextSecondary : kLightTextSub,
                          fontSize: 12)),
                        if (r.contactName.isNotEmpty)
                          Text('Saved as: ${r.contactName}',
                            style: const TextStyle(
                              color: Color(0xFF34C759),
                              fontSize: 11, fontWeight: FontWeight.w500)),
                      ]),
                    trailing: StreamBuilder<DocumentSnapshot>(
                      stream: db.collection('users').doc(_myUid)
                        .collection('friends').doc(r.uid).snapshots(),
                      builder: (_, snap) {
                        if (snap.data?.exists == true) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF34C759).withOpacity(0.3))),
                            child: const Text('Friends',
                              style: TextStyle(
                                color: Color(0xFF34C759),
                                fontSize: 12, fontWeight: FontWeight.w700)));
                        }
                        return GestureDetector(
                          onTap: () => _addFriend(r.uid, r.name),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: kAccent.withOpacity(0.3))),
                            child: const Text('Add',
                              style: TextStyle(color: kAccent,
                                fontWeight: FontWeight.w700,
                                fontSize: 12))));
                      }),
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(uid: r.uid))));
                })),
        ])));
  }
}
      body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        // Info card + sync button
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kGreen.withOpacity(0.15), kGreen.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kGreen.withOpacity(0.2))),
          child: Column(children: [
            const Icon(Icons.contacts_rounded, color: kGreen, size: 44),
            const SizedBox(height: 12),
            const Text('Find Friends from Contacts',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Convo checks which contacts are on the app. Your contact list is never uploaded or stored.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sync_rounded, color: Colors.white),
                label: Text(_loading ? 'Scanning...' : (_synced ? 'Sync Again' : 'Sync Contacts'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: _loading ? null : _sync)),
          ])),
        const SizedBox(height: 16),

        if (_permissionDenied) Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.block_rounded, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text(
              'Permission denied. Go to Settings → Apps → Convo → Permissions → Contacts → Allow',
              style: TextStyle(color: Colors.grey[400], fontSize: 12))),
          ])),

        if (_synced && !_loading) ...[
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: Text(
            _results.isEmpty
              ? 'None of your contacts are on Convo yet'
              : '${_results.length} contact${_results.length == 1 ? '' : 's'} found on Convo',
            style: TextStyle(color: Colors.grey[400], fontSize: 13))),
          const SizedBox(height: 8),
        ],

        Expanded(child: _results.isEmpty && _synced && !_loading
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.person_search_rounded, size: 64, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text('None of your contacts are on Convo yet',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 8),
              const Text('Invite them! 🚀', style: TextStyle(color: kGreen, fontSize: 13)),
            ]))
          : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => Divider(height: 0, color: Colors.grey.withOpacity(0.08), indent: 72),
              itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  leading: Stack(children: [
                    CircleAvatar(radius: 24, backgroundColor: kGreen,
                      child: Text(r.avatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                    Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: r.isOnline ? kGreen : Colors.grey[600],
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? kDark : Colors.white, width: 2)))),
                  ]),
                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('@${r.username}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    if (r.contactName.isNotEmpty)
                      Text('Saved as: ${r.contactName}', style: const TextStyle(color: kGreen, fontSize: 11)),
                  ]),
                  trailing: StreamBuilder<DocumentSnapshot>(
                    stream: db.collection('users').doc(_myUid).collection('friends').doc(r.uid).snapshots(),
                    builder: (_, snap) {
                      if (snap.data?.exists == true) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: const Text('Friends', style: TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w600)));
                      }
                      return TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: kGreen.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        onPressed: () => _addFriend(r.uid, r.name),
                        child: const Text('Add', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)));
                    }),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: r.uid))));
              })),
      ])));
  }
}

class _ContactResult {
  final String uid, name, username, avatar, contactName;
  final bool   isOnline;
  const _ContactResult({
    required this.uid, required this.name, required this.username,
    required this.avatar, required this.contactName, required this.isOnline});
}
