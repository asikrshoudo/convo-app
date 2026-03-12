import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/active_status.dart';
import '../../widgets/common_widgets.dart';
import '../chats/chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String uid;
  const ProfileScreen({super.key, required this.uid});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool get _isMe => widget.uid == auth.currentUser?.uid;
  final _myUid = auth.currentUser!.uid;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final doc = await db.collection('users').doc(widget.uid).get();
    if (mounted) setState(() => _user = doc.data() ?? {});
  }

  final _socialPlatforms = const [
    {'key': 'facebook',  'icon': Icons.facebook_rounded,   'color': Color(0xFF1877F2), 'label': 'Facebook',  'prefix': 'https://facebook.com/'},
    {'key': 'instagram', 'icon': Icons.camera_alt_rounded,  'color': Color(0xFFE1306C), 'label': 'Instagram', 'prefix': 'https://instagram.com/'},
    {'key': 'github',    'icon': Icons.code_rounded,        'color': Color(0xFFE6EDF3), 'label': 'GitHub',    'prefix': 'https://github.com/'},
    {'key': 'linkedin',  'icon': Icons.work_rounded,        'color': Color(0xFF0077B5), 'label': 'LinkedIn',  'prefix': 'https://linkedin.com/in/'},
    {'key': 'twitter',   'icon': Icons.alternate_email,     'color': Color(0xFF1DA1F2), 'label': 'X/Twitter', 'prefix': 'https://twitter.com/'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection('users').doc(widget.uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(
          backgroundColor: isDark ? kDark : kLightBg,
          body: Center(child: CircularProgressIndicator(
            color: kAccent, strokeWidth: 2)));

        final data = snap.data!.data() as Map<String, dynamic>?;
        if (data == null) return Scaffold(
          backgroundColor: isDark ? kDark : kLightBg,
          appBar: AppBar(title: const Text('Profile')),
          body: const Center(child: Text('User not found')));

        final name          = data['name']         as String? ?? 'User';
        final username      = data['username']     as String? ?? '';
        final bio           = data['bio']          as String? ?? '';
        final city          = data['city']         as String? ?? '';
        final education     = data['education']    as String? ?? '';
        final work          = data['work']         as String? ?? '';
        final hometown      = data['hometown']     as String? ?? '';
        final verified      = data['verified']     == true;
        final online        = data['isOnline']     == true;
        final lastSeen      = data['lastSeen']     as Timestamp?;
        final social        = data['social']       as Map<String, dynamic>? ?? {};
        final friendCount   = data['friendCount']  ?? 0;
        final followerCount = data['followerCount'] ?? 0;
        final followingCount = data['followingCount'] ?? 0;
        final friendsPublic  = data['friendsPublic'] != false;
        final profileMode    = data['profileMode']  as String? ?? 'friend';
        final activeSocials  = _socialPlatforms
          .where((p) => (social[p['key']] as String? ?? '').isNotEmpty)
          .toList();

        return Scaffold(
          backgroundColor: isDark ? kDark : kLightBg,
          appBar: AppBar(
            backgroundColor: isDark ? kDark : kLightBg,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(_isMe ? 'My Profile' : name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            actions: [
              if (_isMe) ...[
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 22),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Share profile coming soon!'),
                      backgroundColor: isDark ? kCard2 : kLightCard2))),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 22),
                  onPressed: () => _showEdit(context)),
              ],
              if (!_isMe)
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => _showUserMenu(context)),
            ]),
          body: SingleChildScrollView(child: Column(children: [

            // ── Hero header ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kAccent.withOpacity(0.2), Colors.transparent],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
              child: Column(children: [
                // Avatar
                Stack(children: [
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      color: kAccent, shape: BoxShape.circle,
                      border: Border.all(color: isDark ? kDark : kLightBg, width: 3),
                      boxShadow: [BoxShadow(
                        color: kAccent.withOpacity(0.35), blurRadius: 20)]),
                    child: Center(child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 36,
                        fontWeight: FontWeight.bold)))),
                  if (online) Positioned(right: 2, bottom: 2,
                    child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759),
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? kDark : kLightBg, width: 2.5)))),
                ]),
                const SizedBox(height: 14),

                // Name
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(name, style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold,
                    color: isDark ? kTextPrimary : kLightText)),
                  if (verified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_rounded,
                      color: kAccent, size: 20)],
                ]),

                // Username (tap to copy)
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '@$username'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Username copied!'),
                      backgroundColor: isDark ? kCard2 : kLightCard2, duration: Duration(seconds: 1)));
                  },
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Text('@$username', style: TextStyle(
                      color: isDark ? kTextSecondary : kLightTextSub, fontSize: 14)),
                    const SizedBox(width: 5),
                    const Icon(Icons.copy_rounded, size: 12,
                      color: isDark ? kTextSecondary : kLightTextSub),
                  ])),

                // Status
                const SizedBox(height: 6),
                activeStatusWidget(online, lastSeen, fontSize: 12),

                // Bio
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(bio,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13, height: 1.5)),
                ],
                const SizedBox(height: 20),

                // Stats row
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? kCard : kLightCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? kDivider : kLightDivider, width: 0.5)),
                  child: Row(children: [
                    _statBox(followerCount.toString(), 'Followers'),
                    _divider(),
                    _statBox(
                      (friendsPublic || _isMe) ? friendCount.toString() : '—',
                      'Friends'),
                    _divider(),
                    _statBox(followingCount.toString(), 'Following'),
                  ])),

                // Action buttons (others only)
                if (!_isMe) ...[
                  const SizedBox(height: 16),
                  StreamBuilder<DocumentSnapshot>(
                    stream: db.collection('users')
                      .doc(auth.currentUser!.uid)
                      .collection('friends').doc(widget.uid).snapshots(),
                    builder: (_, friendSnap) {
                      final isFriend = friendSnap.data?.exists == true;
                      final ids = [_myUid, widget.uid]..sort();
                      final chatId = ids.join('_');

                      if (isFriend) {
                        return _actionBtn(
                          Icons.chat_bubble_rounded, 'Send Message', kAccent,
                          () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              otherUid: widget.uid, otherName: name,
                              otherAvatar: name[0].toUpperCase(),
                              chatId: chatId))));
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: db.collection('friend_requests')
                          .where('from', isEqualTo: _myUid)
                          .where('to', isEqualTo: widget.uid)
                          .where('status', isEqualTo: 'pending').snapshots(),
                        builder: (_, reqSnap) {
                          final requestSent =
                            (reqSnap.data?.docs.isNotEmpty) == true;
                          return StreamBuilder<DocumentSnapshot>(
                            stream: db.collection('users').doc(_myUid)
                              .collection('following').doc(widget.uid).snapshots(),
                            builder: (_, followSnap) {
                              final isFollowing =
                                followSnap.data?.exists == true;
                              return Row(children: [
                                Expanded(child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: (isFollowing || requestSent)
                                        ? isDark ? kDivider : kLightDivider : kAccent),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14))),
                                  icon: Icon(
                                    isFollowing
                                      ? Icons.person_remove_rounded
                                      : requestSent
                                        ? Icons.hourglass_top_rounded
                                        : Icons.person_add_alt_1_rounded,
                                    color: (isFollowing || requestSent)
                                      ? isDark ? kTextSecondary : kLightTextSub : kAccent, size: 18),
                                  label: Text(
                                    isFollowing ? 'Unfollow'
                                      : requestSent ? 'Requested'
                                      : (profileMode == 'follow'
                                          ? 'Follow' : 'Add Friend'),
                                    style: TextStyle(
                                      color: (isFollowing || requestSent)
                                        ? isDark ? kTextSecondary : kLightTextSub : kAccent,
                                      fontWeight: FontWeight.bold)),
                                  onPressed: isFollowing
                                    ? _unfollow : requestSent ? null
                                    : () => _sendRequest(
                                        context, profileMode, name))),
                                const SizedBox(width: 10),
                                Expanded(child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAccent, elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14))),
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: Colors.white, size: 18),
                                  label: const Text('Message',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                                  onPressed: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => ChatScreen(
                                      otherUid: widget.uid, otherName: name,
                                      otherAvatar: name[0].toUpperCase(),
                                      chatId: chatId))))),
                              ]);
                            });
                        });
                    }),
                ],
              ])),

            // ── About ─────────────────────────────────────────────────────
            if (city.isNotEmpty || hometown.isNotEmpty ||
                education.isNotEmpty || work.isNotEmpty) ...[
              _secTitle('About'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? kCard : kLightCard,
                  borderRadius: BorderRadius.circular(kCardRadius),
                  border: Border.all(color: isDark ? kDivider : kLightDivider, width: 0.5)),
                child: Column(children: [
                  if (city.isNotEmpty)
                    _infoRow(Icons.location_city_rounded, 'City', city,
                      isLast: !hometown.isNotEmpty && !education.isNotEmpty && !work.isNotEmpty),
                  if (hometown.isNotEmpty)
                    _infoRow(Icons.home_rounded, 'Hometown', hometown,
                      isLast: !education.isNotEmpty && !work.isNotEmpty),
                  if (education.isNotEmpty)
                    _infoRow(Icons.school_rounded, 'Education', education,
                      isLast: !work.isNotEmpty),
                  if (work.isNotEmpty)
                    _infoRow(Icons.work_rounded, 'Work', work, isLast: true),
                ])),
            ],

            // ── Socials ───────────────────────────────────────────────────
            if (activeSocials.isNotEmpty) ...[
              _secTitle('Socials'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 10, runSpacing: 10,
                  children: activeSocials.map((p) {
                    final uname = social[p['key']] as String;
                    final color = p['color'] as Color;
                    return GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('${p['prefix']}$uname'),
                        mode: LaunchMode.externalApplication),
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: uname));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied!'),
                            duration: Duration(seconds: 1)));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withOpacity(0.3))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(p['icon'] as IconData, color: color, size: 16),
                          const SizedBox(width: 7),
                          Text('@$uname',
                            style: TextStyle(
                              color: color, fontWeight: FontWeight.w600,
                              fontSize: 12)),
                        ])));
                  }).toList())),
            ],

            const SizedBox(height: 40),
          ])));
      });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Widget _statBox(String val, String label) => Expanded(child: Column(children: [
    Text(val, style: TextStyle(
      fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
  ]));

  Widget _divider() => Container(
    width: 1, height: 36,
    color: isDark ? kDivider : kLightDivider);

  Widget _secTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
    child: Row(children: [
      Text(t, style: TextStyle(
        fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? kTextPrimary : kLightText)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 0.5, color: isDark ? kDivider : kLightDivider)),
    ]));

  Widget _infoRow(IconData icon, String label, String value,
      {bool isLast = false}) =>
    Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: kAccent, size: 18)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              color: isDark ? kTextSecondary : kLightTextSub, fontSize: 11)),
            const SizedBox(height: 1),
            Text(value, style: TextStyle(
              color: isDark ? kTextPrimary : kLightText, fontWeight: FontWeight.w500, fontSize: 14)),
          ]),
        ])),
      if (!isLast) const Divider(height: 0, indent: 66, color: isDark ? kDivider : kLightDivider),
    ]);

  Widget _actionBtn(IconData icon, String label, Color color,
      VoidCallback onTap) =>
    SizedBox(width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14))),
        icon: Icon(icon, color: Colors.white, size: 18),
        label: Text(label, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: onTap));

  // ─── Actions ──────────────────────────────────────────────────────────────
  Future<void> _sendRequest(BuildContext context, String profileMode,
      String name) async {
    if (profileMode == 'follow') {
      await db.collection('users').doc(_myUid)
        .collection('following').doc(widget.uid)
        .set({'uid': widget.uid, 'since': FieldValue.serverTimestamp()});
      await db.collection('users').doc(widget.uid)
        .collection('followers').doc(_myUid)
        .set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
      await db.collection('users').doc(widget.uid)
        .update({'followerCount': FieldValue.increment(1)});
      await db.collection('users').doc(_myUid)
        .update({'followingCount': FieldValue.increment(1)});
    } else {
      final my = await db.collection('users').doc(_myUid).get();
      await db.collection('friend_requests').add({
        'from': _myUid,
        'fromName': my.data()?['name'] ?? 'User',
        'fromAvatar': my.data()?['avatar'] ?? 'U',
        'to': widget.uid, 'toName': name,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(profileMode == 'follow'
        ? 'Following $name' : 'Friend request sent!'),
      backgroundColor: kAccent));
  }

  Future<void> _unfollow() async {
    await db.collection('users').doc(_myUid)
      .collection('following').doc(widget.uid).delete();
    await db.collection('users').doc(widget.uid)
      .collection('followers').doc(_myUid).delete();
    await db.collection('users').doc(widget.uid)
      .update({'followerCount': FieldValue.increment(-1)});
    await db.collection('users').doc(_myUid)
      .update({'followingCount': FieldValue.increment(-1)});
  }

  Future<void> _block() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? kCard : kLightCard,
        title: Text('Block User?', style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
        content: Text('They won\'t be able to find your profile.',
          style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: kRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block')),
        ]));
    if (confirm != true) return;
    await db.collection('users').doc(_myUid)
      .collection('blocked').doc(widget.uid)
      .set({'uid': widget.uid, 'blockedAt': FieldValue.serverTimestamp()});
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User blocked'), backgroundColor: kRed));
    }
  }

  Future<void> _mute() async {
    final muteDoc = await db.collection('users').doc(_myUid)
      .collection('muted').doc(widget.uid).get();
    if (muteDoc.exists) {
      await muteDoc.reference.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unmuted')));
    } else {
      await db.collection('users').doc(_myUid)
        .collection('muted').doc(widget.uid)
        .set({'uid': widget.uid, 'mutedAt': FieldValue.serverTimestamp()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Muted')));
    }
  }

  Future<void> _report(BuildContext context) async {
    String? reason;
    await showModalBottomSheet(
      context: context, backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(
            color: isDark ? kTextTertiary : kLightTextSub, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Report User', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
          const SizedBox(height: 12),
          ...['Spam', 'Harassment', 'Fake Account',
              'Inappropriate Content', 'Other'].map((r) =>
            ListTile(
              leading: const Icon(Icons.flag_rounded, color: kRed),
              title: Text(r, style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
              onTap: () { reason = r; Navigator.pop(context); })),
        ])));

    if (reason == null) return;
    final existing = await db.collection('reports')
      .where('reportedUid', isEqualTo: widget.uid)
      .where('reporterUid', isEqualTo: _myUid).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already reported')));
      return;
    }
    await db.collection('reports').add({
      'reportedUid': widget.uid, 'reporterUid': _myUid,
      'reason': reason, 'timestamp': FieldValue.serverTimestamp()});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report submitted')));
  }

  void _showUserMenu(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(
          color: isDark ? kTextTertiary : kLightTextSub, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.volume_off_rounded, color: isDark ? kTextSecondary : kLightTextSub),
          title: Text('Mute', style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
          onTap: () { Navigator.pop(context); _mute(); }),
        ListTile(
          leading: const Icon(Icons.block_rounded, color: kRed),
          title: const Text('Block', style: TextStyle(color: kRed)),
          onTap: () { Navigator.pop(context); _block(); }),
        ListTile(
          leading: const Icon(Icons.flag_rounded, color: kOrange),
          title: const Text('Report', style: TextStyle(color: kOrange)),
          onTap: () { Navigator.pop(context); _report(context); }),
        const SizedBox(height: 8),
      ])));
  }

  void _showEdit(BuildContext context) {
    final nc = TextEditingController(text: _user?['name']     ?? '');
    final bc = TextEditingController(text: _user?['bio']      ?? '');
    final cc = TextEditingController(text: _user?['city']     ?? '');
    final hc = TextEditingController(text: _user?['hometown'] ?? '');
    final ec = TextEditingController(text: _user?['education'] ?? '');
    final wc = TextEditingController(text: _user?['work']     ?? '');
    final social = Map<String, dynamic>.from(_user?['social'] ?? {});
    final socialCtrls = {
      for (final p in _socialPlatforms)
        p['key'] as String: TextEditingController(text: social[p['key']] ?? '')
    };

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(
            color: isDark ? kTextTertiary : kLightTextSub, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Edit Profile', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? kTextPrimary : kLightText)),
          const SizedBox(height: 20),
          _ef('Name', nc),
          const SizedBox(height: 10),
          _ef('Bio', bc, lines: 3),
          const SizedBox(height: 10),
          _ef('City', cc),
          const SizedBox(height: 10),
          _ef('Hometown', hc),
          const SizedBox(height: 10),
          _ef('Education', ec),
          const SizedBox(height: 10),
          _ef('Work', wc),
          const SizedBox(height: 20),
          Align(alignment: Alignment.centerLeft,
            child: Text('Social Links', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13,
              color: isDark ? kTextSecondary : kLightTextSub))),
          const SizedBox(height: 10),
          ...(_socialPlatforms.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: socialCtrls[p['key']],
              style: TextStyle(color: isDark ? kTextPrimary : kLightText),
              decoration: InputDecoration(
                hintText: '${p['label']} username',
                hintStyle: TextStyle(color: isDark ? kTextSecondary : kLightTextSub),
                prefixIcon: Icon(p['icon'] as IconData,
                  color: p['color'] as Color, size: 20),
                filled: true, fillColor: isDark ? kCard2 : kLightCard2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p['color'] as Color))))))),
          const SizedBox(height: 16),
          primaryButton('Save Changes', () async {
            final newSocial = {
              for (final p in _socialPlatforms)
                p['key'] as String: socialCtrls[p['key']]!.text.trim()
            };
            await db.collection('users').doc(widget.uid).update({
              'name': nc.text.trim(), 'bio': bc.text.trim(),
              'city': cc.text.trim(), 'hometown': hc.text.trim(),
              'education': ec.text.trim(), 'work': wc.text.trim(),
              'social': newSocial,
              'avatar': nc.text.trim().isNotEmpty
                ? nc.text.trim()[0].toUpperCase() : 'U',
            });
            await auth.currentUser?.updateDisplayName(nc.text.trim());
            if (mounted) { Navigator.pop(context); _load(); }
          }),
        ]))));
  }

  Widget _ef(String label, TextEditingController ctrl, {int lines = 1}) =>
    TextField(
      controller: ctrl, maxLines: lines,
      style: TextStyle(color: isDark ? kTextPrimary : kLightText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? kTextSecondary : kLightTextSub),
        filled: true, fillColor: isDark ? kCard2 : kLightCard2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAccent))));
}
