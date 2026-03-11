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

  Future<void> _load() async {
    final doc = await db.collection('users').doc(widget.uid).get();
    if (mounted) setState(() => _user = doc.data() ?? {});
  }

  Future<void> _block() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Block User?'),
        content: const Text('They won\'t be able to find your profile or message you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block')),
        ]));
    if (confirm != true) return;
    await db.collection('users').doc(_myUid).collection('blocked').doc(widget.uid).set({
      'uid': widget.uid, 'blockedAt': FieldValue.serverTimestamp()});
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User blocked'), backgroundColor: Colors.red));
    }
  }

  Future<void> _mute() async {
    final muteDoc = await db.collection('users').doc(_myUid).collection('muted').doc(widget.uid).get();
    final isMuted = muteDoc.exists;
    if (isMuted) {
      await db.collection('users').doc(_myUid).collection('muted').doc(widget.uid).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unmuted'), backgroundColor: kGreen));
    } else {
      await db.collection('users').doc(_myUid).collection('muted').doc(widget.uid).set({
        'uid': widget.uid, 'mutedAt': FieldValue.serverTimestamp()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Muted'), backgroundColor: kGreen));
    }
  }

  Future<void> _report(BuildContext context) async {
    String? reason;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Report User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...['Spam', 'Harassment', 'Fake Account', 'Inappropriate Content', 'Other'].map((r) =>
            ListTile(
              title: Text(r),
              leading: const Icon(Icons.flag_rounded, color: Colors.red),
              onTap: () { reason = r; Navigator.pop(context); })),
        ])));

    if (reason == null) return;

    // Check if already reported
    final existing = await db.collection('reports')
      .where('reportedUid', isEqualTo: widget.uid)
      .where('reporterUid', isEqualTo: _myUid)
      .get();
    if (existing.docs.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already reported this user')));
      return;
    }

    await db.collection('reports').add({
      'reportedUid': widget.uid,
      'reporterUid': _myUid,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Count total reports — if 10+, suspend account
    final allReports = await db.collection('reports')
      .where('reportedUid', isEqualTo: widget.uid).get();
    if (allReports.docs.length >= 10) {
      await db.collection('users').doc(widget.uid).update({'suspended': true});
    }

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report submitted'), backgroundColor: kGreen));
  }

  Future<void> _unfollow() async {
    await db.collection('users').doc(_myUid).collection('following').doc(widget.uid).delete();
    await db.collection('users').doc(widget.uid).collection('followers').doc(_myUid).delete();
    await db.collection('users').doc(widget.uid).update({'followerCount': FieldValue.increment(-1)});
    await db.collection('users').doc(_myUid).update({'followingCount': FieldValue.increment(-1)});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unfollowed'), backgroundColor: kGreen));
  }

  void _showUserMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.volume_off_rounded),
          title: const Text('Mute'),
          onTap: () { Navigator.pop(context); _mute(); }),
        ListTile(
          leading: const Icon(Icons.block_rounded, color: Colors.red),
          title: const Text('Block', style: TextStyle(color: Colors.red)),
          onTap: () { Navigator.pop(context); _block(); }),
        ListTile(
          leading: const Icon(Icons.flag_rounded, color: Colors.orange),
          title: const Text('Report', style: TextStyle(color: Colors.orange)),
          onTap: () { Navigator.pop(context); _report(context); }),
        const SizedBox(height: 8),
      ])));
  }

  @override void initState() { super.initState(); _load(); }

  final _socialPlatforms = [
    {'key': 'facebook',  'icon': Icons.facebook_rounded,  'color': const Color(0xFF1877F2), 'label': 'Facebook',  'prefix': 'https://facebook.com/'},
    {'key': 'instagram', 'icon': Icons.camera_alt_rounded, 'color': const Color(0xFFE1306C), 'label': 'Instagram', 'prefix': 'https://instagram.com/'},
    {'key': 'github',    'icon': Icons.code_rounded,       'color': const Color(0xFF333333), 'label': 'GitHub',    'prefix': 'https://github.com/'},
    {'key': 'linkedin',  'icon': Icons.work_rounded,       'color': const Color(0xFF0077B5), 'label': 'LinkedIn',  'prefix': 'https://linkedin.com/in/'},
    {'key': 'twitter',   'icon': Icons.alternate_email,    'color': const Color(0xFF1DA1F2), 'label': 'X/Twitter', 'prefix': 'https://twitter.com/'},
  ];

  void _copySocialUsername(String username) {
    Clipboard.setData(ClipboardData(text: username));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Username copied!'), backgroundColor: kGreen),
    );
  }
@override
Widget build(BuildContext context) {
  return StreamBuilder<DocumentSnapshot>(
    stream: db.collection('users').doc(widget.uid).snapshots(),
    builder: (context, snap) {
      if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kGreen)));
      final data = snap.data!.data() as Map<String, dynamic>?;
      if (data == null) return Scaffold(appBar: AppBar(title: const Text('Profile')), body: const Center(child: Text('User not found')));

      if (_user == null || _user != data) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _user = data); });
      }

      final isDark        = Theme.of(context).brightness == Brightness.dark;
      final name          = data['name']        as String? ?? 'User';
      final username      = data['username']    as String? ?? '';
      final bio           = data['bio']         as String? ?? '';
      final city          = data['city']        as String? ?? '';
      final education     = data['education']   as String? ?? '';
      final work          = data['work']        as String? ?? '';
      final hometown      = data['hometown']    as String? ?? '';
      final verified      = data['verified']    == true;
      final online        = data['isOnline']    == true;
      final lastSeen      = data['lastSeen']    as Timestamp?;
      final social        = data['social']      as Map<String, dynamic>? ?? {};
      final friendCount   = data['friendCount']   ?? 0;
      final followerCount = data['followerCount']  ?? 0;
      final followingCount = data['followingCount'] ?? 0;
      final friendsPublic = data['friendsPublic'] != false;
      final profileMode   = data['profileMode']  as String? ?? 'friend';
      final activeSocials = _socialPlatforms.where((p) => (social[p['key']] as String? ?? '').isNotEmpty).toList();

      return Scaffold(
        appBar: AppBar(
          title: Text(_isMe ? 'My Profile' : name, style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_isMe) ...[
              IconButton(
                icon: const Icon(Icons.share_rounded),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share profile link coming soon!'), backgroundColor: kGreen));
                }),
              IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _showEdit(context)),
            ],
            if (!_isMe)
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _showUserMenu(context)),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // ── Header gradient ──
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kGreen.withOpacity(0.25), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    Stack(
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: kGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 20)],
                          ),
                          child: Center(
                            child: Text(
                              name[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        if (online)
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: kGreen,
                                shape: BoxShape.circle,
                                border: Border.all(color: isDark ? kDark : Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        if (verified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: kGreen, size: 20)],
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '@$username'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Username copied!'), backgroundColor: kGreen));
                      },
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                        const SizedBox(width: 4),
                        Icon(Icons.copy_rounded, size: 12, color: Colors.grey[600]),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    activeStatusWidget(online, lastSeen, fontSize: 12),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          bio,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _statBox(followerCount.toString(), 'Followers'),
                        Container(width: 1, height: 36, color: Colors.grey.withOpacity(0.3)),
                        _statBox((friendsPublic || _isMe) ? friendCount.toString() : '—', 'Friends'),
                        Container(width: 1, height: 36, color: Colors.grey.withOpacity(0.3)),
                        _statBox(followingCount.toString(), 'Following'),
                      ],
                    ),

                    // Action buttons (only for other users)
                    if (!_isMe) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: StreamBuilder<DocumentSnapshot>(
                          stream: db.collection('users').doc(auth.currentUser!.uid).collection('friends').doc(widget.uid).snapshots(),
                          builder: (_, friendSnap) {
                            final isFriend = friendSnap.data?.exists == true;
                            final myUid = auth.currentUser!.uid;
                            final ids = [myUid, widget.uid]..sort();
                            final chatId = ids.join('_');

                            if (isFriend) {
                              return primaryButton(
                                'Send Message',
                                () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    otherUid: widget.uid, otherName: name,
                                    otherAvatar: name[0].toUpperCase(), chatId: chatId))),
                              );
                            }
                            return StreamBuilder<QuerySnapshot>(
                              stream: db.collection('friend_requests')
                                .where('from', isEqualTo: myUid)
                                .where('to', isEqualTo: widget.uid)
                                .where('status', isEqualTo: 'pending')
                                .snapshots(),
                              builder: (_, reqSnap) {
                                final requestSent = (reqSnap.data?.docs.isNotEmpty) == true;
                                return StreamBuilder<DocumentSnapshot>(
                                  stream: db.collection('users').doc(myUid)
                                    .collection('following').doc(widget.uid).snapshots(),
                                  builder: (_, followSnap) {
                                    final isFollowing = followSnap.data?.exists == true;
                                    return Row(children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: (isFollowing || requestSent) ? Colors.grey : kGreen),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                          icon: Icon(
                                            isFollowing ? Icons.person_remove_rounded
                                              : requestSent ? Icons.hourglass_top_rounded
                                              : (profileMode == 'follow' ? Icons.person_add_rounded : Icons.person_add_alt_1_rounded),
                                            color: (isFollowing || requestSent) ? Colors.grey : kGreen, size: 18),
                                          label: Text(
                                            isFollowing ? 'Unfollow'
                                              : requestSent ? 'Requested'
                                              : (profileMode == 'follow' ? 'Follow' : 'Add Friend'),
                                            style: TextStyle(
                                              color: (isFollowing || requestSent) ? Colors.grey : kGreen,
                                              fontWeight: FontWeight.bold)),
                                          onPressed: isFollowing
                                            ? _unfollow
                                            : requestSent ? null
                                            : () async {
                                                if (profileMode == 'follow') {
                                                  await db.collection('users').doc(myUid)
                                                    .collection('following').doc(widget.uid)
                                                    .set({'uid': widget.uid, 'since': FieldValue.serverTimestamp()});
                                                  await db.collection('users').doc(widget.uid)
                                                    .collection('followers').doc(myUid)
                                                    .set({'uid': myUid, 'since': FieldValue.serverTimestamp()});
                                                  await db.collection('users').doc(widget.uid)
                                                    .update({'followerCount': FieldValue.increment(1)});
                                                  await db.collection('users').doc(myUid)
                                                    .update({'followingCount': FieldValue.increment(1)});
                                                } else {
                                                  final my = await db.collection('users').doc(myUid).get();
                                                  await db.collection('friend_requests').add({
                                                    'from': myUid,
                                                    'fromName': my.data()?['name'] ?? 'User',
                                                    'fromAvatar': my.data()?['avatar'] ?? 'U',
                                                    'to': widget.uid, 'toName': name,
                                                    'status': 'pending',
                                                    'timestamp': FieldValue.serverTimestamp(),
                                                  });
                                                }
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                    content: Text(profileMode == 'follow' ? 'Following $name' : 'Friend request sent!'),
                                                    backgroundColor: kGreen));
                                                }
                                              })),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kGreen, elevation: 0,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                          icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 18),
                                          label: const Text('Message', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              otherUid: widget.uid, otherName: name,
                                              otherAvatar: name[0].toUpperCase(), chatId: chatId))))),
                                    ]);
                                  });
                              });
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
                              // About section
                if (city.isNotEmpty || hometown.isNotEmpty || education.isNotEmpty || work.isNotEmpty) ...[
                  _secTitle('About'),
                  if (city.isNotEmpty) _infoRow(Icons.location_city_rounded, 'City', city),
                  if (hometown.isNotEmpty) _infoRow(Icons.home_rounded, 'Hometown', hometown),
                  if (education.isNotEmpty) _infoRow(Icons.school_rounded, 'Education', education),
                  if (work.isNotEmpty) _infoRow(Icons.work_rounded, 'Work', work),
                ],

                // Socials section (improved)
                if (activeSocials.isNotEmpty) ...[
                  _secTitle('Socials'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: activeSocials.map((p) {
                        final uname = social[p['key']] as String;
                        return GestureDetector(
                          onTap: () => launchUrl(
                            Uri.parse('${p['prefix']}$uname'),
                            mode: LaunchMode.externalApplication,
                          ),
                          onLongPress: () => _copySocialUsername(uname),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: (p['color'] as Color).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: (p['color'] as Color).withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(p['icon'] as IconData, color: p['color'] as Color, size: 18),
                                const SizedBox(width: 7),
                                Text(
                                  '@$uname',
                                  style: TextStyle(
                                    color: p['color'] as Color,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statBox(String val, String label) => SizedBox(
    width: 90,
    child: Column(
      children: [
        Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    ),
  );

  Widget _secTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(
      children: [
        Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: Colors.grey.withOpacity(0.3))),
      ],
    ),
  );

  Widget _infoRow(IconData icon, String label, String value) => ListTile(
    dense: true,
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: kGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: kGreen, size: 18),
    ),
    title: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
    subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
  );

  void _showEdit(BuildContext context) {
    final nc = TextEditingController(text: _user?['name'] ?? '');
    final bc = TextEditingController(text: _user?['bio'] ?? '');
    final cc = TextEditingController(text: _user?['city'] ?? '');
    final hc = TextEditingController(text: _user?['hometown'] ?? '');
    final ec = TextEditingController(text: _user?['education'] ?? '');
    final wc = TextEditingController(text: _user?['work'] ?? '');
    final social = Map<String, dynamic>.from(_user?['social'] ?? {});
    final socialCtrls = {
      for (final p in _socialPlatforms) p['key'] as String: TextEditingController(text: social[p['key']] ?? '')
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Social Links',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[400]),
                ),
              ),
              const SizedBox(height: 10),
              ...(_socialPlatforms.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: socialCtrls[p['key']],
                  decoration: InputDecoration(
                    hintText: '${p['label']} username',
                    prefixIcon: Icon(p['icon'] as IconData, color: p['color'] as Color, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p['color'] as Color),
                    ),
                  ),
                ),
              )).toList()),
              const SizedBox(height: 16),
              primaryButton('Save Changes', () async {
                final newSocial = {
                  for (final p in _socialPlatforms) p['key'] as String: socialCtrls[p['key']]!.text.trim()
                };
                await db.collection('users').doc(widget.uid).update({
                  'name': nc.text.trim(),
                  'bio': bc.text.trim(),
                  'city': cc.text.trim(),
                  'hometown': hc.text.trim(),
                  'education': ec.text.trim(),
                  'work': wc.text.trim(),
                  'social': newSocial,
                  'avatar': nc.text.trim().isNotEmpty ? nc.text.trim()[0].toUpperCase() : 'U',
                });
                await auth.currentUser?.updateDisplayName(nc.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  _load();
                }
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ef(String label, TextEditingController ctrl, {int lines = 1}) => TextField(
    controller: ctrl,
    maxLines: lines,
    decoration: InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGreen),
      ),
    ),
  );
}