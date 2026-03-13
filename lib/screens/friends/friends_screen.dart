import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../chats/chat_screen.dart';
import '../profile/profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  final bool startChat;
  const FriendsScreen({super.key, this.startChat = false});
  @override State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  static const _notifyBase = 'https://convo-notify.onrender.com';

  late TabController _tab;
  final _searchCtrl = TextEditingController();
  final _myUid = auth.currentUser!.uid;
  List<Map<String, dynamic>> _results     = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadSuggestions();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final snap = await db.collection('users')
        .where('suggestionsEnabled', isEqualTo: true)
        .limit(30).get();
      final friends = await db.collection('users')
        .doc(_myUid).collection('friends').get();
      final friendIds = friends.docs.map((d) => d.id).toSet();
      final all = snap.docs
        .where((d) => d.id != _myUid && !friendIds.contains(d.id))
        .map((d) => {...d.data(), 'uid': d.id}).toList();
      all.shuffle();
      if (mounted) setState(() => _suggestions = all.take(10).toList());
    } catch (_) {}
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final qLow = q.trim().toLowerCase();
      final byUsername = await db.collection('users')
        .where('username', isGreaterThanOrEqualTo: qLow)
        .where('username', isLessThan: '${qLow}z').limit(15).get();
      final byName = await db.collection('users')
        .where('nameLower', isGreaterThanOrEqualTo: qLow)
        .where('nameLower', isLessThan: '${qLow}z').limit(15).get();
      final Map<String, Map<String, dynamic>> merged = {};
      for (final doc in [...byUsername.docs, ...byName.docs]) {
        merged[doc.id] = {...doc.data(), 'uid': doc.id};
      }
      merged.remove(_myUid);
      if (mounted) setState(() => _results = merged.values.toList());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(String toUid, String toName,
      String toAvatar) async {
    final fd = await db.collection('users').doc(_myUid)
      .collection('friends').doc(toUid).get();
    if (fd.exists) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already friends!'),
          backgroundColor: kAccent));
      return;
    }
    final targetDoc  = await db.collection('users').doc(toUid).get();
    final targetMode = targetDoc.data()?['profileMode'] ?? 'friend';

    if (targetMode == 'follow') {
      await db.collection('users').doc(_myUid)
        .collection('following').doc(toUid)
        .set({'uid': toUid, 'since': FieldValue.serverTimestamp()});
      await db.collection('users').doc(toUid)
        .collection('followers').doc(_myUid)
        .set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
      await db.collection('users').doc(toUid)
        .update({'followerCount': FieldValue.increment(1)});
      await db.collection('users').doc(_myUid)
        .update({'followingCount': FieldValue.increment(1)});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Now following $toName'),
          backgroundColor: kAccent));
    } else {
      final ex = await db.collection('friend_requests')
        .where('fromUid', isEqualTo: _myUid)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending').get();
      if (ex.docs.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request already sent!')));
        return;
      }
      final my = await db.collection('users').doc(_myUid).get();
      await db.collection('friend_requests').add({
        'fromUid':      _myUid,
        'fromName':     my.data()?['name']     ?? 'User',
        'fromAvatar':   my.data()?['avatar']   ?? 'U',
        'fromUsername': my.data()?['username'] ?? '',
        'toUid':    toUid,
        'toName':   toName,
        'status':   'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      try {
        await http.post(
          Uri.parse('$_notifyBase/notify/friend-request'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'fromUid':  _myUid,
            'fromName': my.data()?['name'] ?? 'User',
            'toUid':    toUid,
          }));
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request sent to $toName'),
          backgroundColor: kAccent));
    }
  }

  Future<void> _accept(String docId, String fromUid) async {
    await db.collection('friend_requests')
      .doc(docId).update({'status': 'accepted'});
    await db.collection('users').doc(_myUid)
      .collection('friends').doc(fromUid)
      .set({'uid': fromUid, 'since': FieldValue.serverTimestamp()});
    await db.collection('users').doc(fromUid)
      .collection('friends').doc(_myUid)
      .set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
    await db.collection('users').doc(_myUid)
      .update({'friendCount': FieldValue.increment(1)});
    await db.collection('users').doc(fromUid)
      .update({'friendCount': FieldValue.increment(1)});
    try {
      final me = await db.collection('users').doc(_myUid).get();
      await http.post(Uri.parse('$_notifyBase/notify/friend-accepted'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fromUid':      fromUid,
          'accepterName': me.data()?['name'] ?? 'Someone',
        }));
    } catch (_) {}
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend added!'),
        backgroundColor: kAccent));
  }

  // ── User card (Instagram-style) ─────────────────────────────────────────
  Widget _userCard(Map<String, dynamic> u) {
    final uid  = u['uid'] as String;
    final name = u['name'] as String? ?? 'User';
    final uname = u['username'] as String? ?? '';
    final avatar = (u['avatar'] as String? ?? name).isNotEmpty
      ? (u['avatar'] as String? ?? name)[0].toUpperCase() : 'U';
    final verified = u['verified'] == true;

    return InkWell(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid))),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? kCard : kLightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? kDivider : kLightDivider, width: 0.5)),
        child: Row(children: [
          // Avatar
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.18),
              shape: BoxShape.circle),
            child: Center(child: Text(avatar,
              style: const TextStyle(color: kAccent,
                fontWeight: FontWeight.bold, fontSize: 20)))),
          const SizedBox(width: 14),

          // Name + username
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15,
                    color: isDark ? kTextPrimary : kLightText),
                  overflow: TextOverflow.ellipsis)),
                if (verified) ...[ const SizedBox(width: 4),
                  const Icon(Icons.verified_rounded,
                    color: kAccent, size: 14)],
              ]),
              const SizedBox(height: 2),
              Text('@$uname',
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub,
                  fontSize: 12)),
            ])),

          // Action button
          const SizedBox(width: 10),
          widget.startChat
            ? _pillBtn('Message', kAccent, () {
                final ids = [_myUid, uid]..sort();
                Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => ChatScreen(
                    otherUid: uid, otherName: name,
                    otherAvatar: avatar, chatId: ids.join('_'))));
              })
            : StreamBuilder<DocumentSnapshot>(
                stream: db.collection('users').doc(_myUid)
                  .collection('friends').doc(uid).snapshots(),
                builder: (_, fSnap) {
                  if (fSnap.data?.exists == true) {
                    return _pillBtn('Friends',
                      isDark ? kDivider : kLightDivider, null,
                      textColor: isDark ? kTextSecondary : kLightTextSub);
                  }
                  return StreamBuilder<QuerySnapshot>(
                    stream: db.collection('friend_requests')
                      .where('fromUid', isEqualTo: _myUid)
                      .where('toUid',   isEqualTo: uid)
                      .where('status',  isEqualTo: 'pending').snapshots(),
                    builder: (_, rSnap) {
                      final sent = rSnap.data?.docs.isNotEmpty == true;
                      final isFollow = u['profileMode'] == 'follow';
                      if (sent) {
                        return _pillBtn('Requested',
                          isDark ? kDivider : kLightDivider, () async {
                            final docId = rSnap.data!.docs.first.id;
                            await db.collection('friend_requests')
                              .doc(docId).delete();
                          },
                          textColor: isDark ? kTextSecondary : kLightTextSub);
                      }
                      return _pillBtn(
                        isFollow ? 'Follow' : 'Add Friend',
                        kAccent,
                        () => _sendRequest(uid, name, avatar));
                    });
                }),
        ])));
  }

  Widget _pillBtn(String label, Color bg, VoidCallback? onTap,
      {Color? textColor}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bg.withOpacity(onTap == null ? 0.12 : 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: bg.withOpacity(0.4), width: 1)),
        child: Text(label,
          style: TextStyle(
            color: textColor ?? bg,
            fontSize: 12.5, fontWeight: FontWeight.w700))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: widget.startChat,
        title: Text(widget.startChat ? 'New Message' : 'Find',
          style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 22,
            color: isDark ? kTextPrimary : kLightText)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: kAccent,
          indicatorWeight: 2.5,
          labelColor: kAccent,
          unselectedLabelColor: isDark ? kTextSecondary : kLightTextSub,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Discover'),
            Tab(text: 'Requests'),
            Tab(text: 'Friends'),
          ])),
      body: TabBarView(
        controller: _tab,
        children: [

          // ── Discover tab ─────────────────────────────────────────────────
          CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? kCard : kLightCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? kDivider : kLightDivider, width: 0.5)),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _search,
                  style: TextStyle(
                    color: isDark ? kTextPrimary : kLightText),
                  decoration: InputDecoration(
                    hintText: 'Search name or username...',
                    hintStyle: TextStyle(
                      color: isDark ? kTextSecondary : kLightTextSub,
                      fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                      color: isDark ? kTextSecondary : kLightTextSub),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, size: 18,
                            color: isDark ? kTextSecondary : kLightTextSub),
                          onPressed: () {
                            _searchCtrl.clear();
                            _search('');
                          })
                      : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 13)))))),

            if (_searching)
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(
                  color: kAccent, strokeWidth: 2))))
            else if (_searchCtrl.text.isNotEmpty && _results.isEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  Icon(Icons.search_off_rounded, size: 52,
                    color: isDark ? kTextSecondary : kLightTextSub),
                  const SizedBox(height: 12),
                  Text('No results for "${_searchCtrl.text}"',
                    style: TextStyle(
                      color: isDark ? kTextSecondary : kLightTextSub),
                    textAlign: TextAlign.center),
                ])))
            else if (_results.isNotEmpty)
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _userCard(_results[i]),
                childCount: _results.length))

            else ...[ 
              if (_suggestions.isNotEmpty)
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                  child: Row(children: [
                    Icon(Icons.auto_awesome_rounded,
                      color: kAccent, size: 15),
                    const SizedBox(width: 6),
                    Text('People you may know',
                      style: TextStyle(
                        color: kAccent, fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _loadSuggestions,
                      child: Icon(Icons.refresh_rounded,
                        color: isDark ? kTextSecondary : kLightTextSub,
                        size: 16)),
                  ]))),
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _userCard(_suggestions[i]),
                childCount: _suggestions.length)),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),

          // ── Requests tab ─────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('friend_requests')
              .where('toUid', isEqualTo: _myUid)
              .where('status', isEqualTo: 'pending').snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return _emptyState(
                  Icons.mark_email_unread_outlined,
                  'No pending requests',
                  'Friend requests will show up here');
              }
              final docs = snap.data!.docs.toList()..sort((a, b) {
                final aTs = (a.data() as Map)['timestamp'];
                final bTs = (b.data() as Map)['timestamp'];
                if (aTs == null && bTs == null) return 0;
                if (aTs == null) return 1; if (bTs == null) return -1;
                return (bTs as dynamic).compareTo(aTs);
              });
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final fromAvatar = (d['fromAvatar'] as String? ?? 'U')
                    .isNotEmpty ? (d['fromAvatar'] as String)[0].toUpperCase()
                    : 'U';
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ProfileScreen(uid: d['fromUid']))),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 5),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? kCard : kLightCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? kDivider : kLightDivider,
                          width: 0.5)),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: kAccent.withOpacity(0.18),
                            shape: BoxShape.circle),
                          child: Center(child: Text(fromAvatar,
                            style: const TextStyle(color: kAccent,
                              fontWeight: FontWeight.bold, fontSize: 20)))),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['fromName'] ?? 'User',
                              style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15,
                                color: isDark ? kTextPrimary : kLightText)),
                            const SizedBox(height: 2),
                            Text('wants to be your friend',
                              style: TextStyle(
                                color: isDark ? kTextSecondary : kLightTextSub,
                                fontSize: 12)),
                          ])),
                        const SizedBox(width: 10),
                        // Decline
                        GestureDetector(
                          onTap: () => db.collection('friend_requests')
                            .doc(docs[i].id)
                            .update({'status': 'declined'}),
                          child: Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: kRed.withOpacity(0.1),
                              shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded,
                              color: kRed, size: 20))),
                        const SizedBox(width: 8),
                        // Accept
                        GestureDetector(
                          onTap: () => _accept(docs[i].id, d['fromUid']),
                          child: Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.15),
                              shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded,
                              color: kAccent, size: 20))),
                      ])));
                });
            }),

          // ── Friends tab ──────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('users').doc(_myUid)
              .collection('friends').snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return _emptyState(
                  Icons.people_outline_rounded,
                  'No friends yet',
                  'Add people to start chatting');
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: snap.data!.docs.length,
                itemBuilder: (_, i) {
                  final friendId = snap.data!.docs[i].id;
                  return StreamBuilder<DocumentSnapshot>(
                    stream: db.collection('users').doc(friendId).snapshots(),
                    builder: (_, uSnap) {
                      final u = uSnap.data?.data()
                        as Map<String, dynamic>? ?? {};
                      final online = u['isOnline'] == true;
                      final name   = u['name'] as String? ?? 'User';
                      final uname  = u['username'] as String? ?? '';
                      final avatar = (u['avatar'] as String? ?? name)
                        .isNotEmpty ? (u['avatar'] as String? ?? name)[0]
                          .toUpperCase() : 'U';
                      final ids    = [_myUid, friendId]..sort();
                      final chatId = ids.join('_');

                      return InkWell(
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) =>
                            ProfileScreen(uid: friendId))),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 5),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? kCard : kLightCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? kDivider : kLightDivider,
                              width: 0.5)),
                          child: Row(children: [
                            Stack(children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: kAccent.withOpacity(0.18),
                                  shape: BoxShape.circle),
                                child: Center(child: Text(avatar,
                                  style: const TextStyle(color: kAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20)))),
                              if (online) Positioned(right: 1, bottom: 1,
                                child: Container(
                                  width: 13, height: 13,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF34C759),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? kDark : kLightBg,
                                      width: 2)))),
                            ]),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15,
                                    color: isDark ? kTextPrimary : kLightText)),
                                const SizedBox(height: 2),
                                Text(
                                  online ? 'Active now' : '@$uname',
                                  style: TextStyle(
                                    color: online
                                      ? const Color(0xFF34C759)
                                      : isDark ? kTextSecondary : kLightTextSub,
                                    fontSize: 12,
                                    fontWeight: online
                                      ? FontWeight.w500 : FontWeight.normal)),
                              ])),
                            // Message button
                            GestureDetector(
                              onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ChatScreen(
                                  otherUid: friendId, otherName: name,
                                  otherAvatar: avatar, chatId: chatId))),
                              child: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: kAccent.withOpacity(0.12),
                                  shape: BoxShape.circle),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: kAccent, size: 18))),
                            const SizedBox(width: 8),
                            // More options
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded,
                                color: isDark ? kTextSecondary : kLightTextSub,
                                size: 20),
                              color: isDark ? kCard2 : kLightCard2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                              onSelected: (v) async {
                                if (v == 'remove') {
                                  await _removeFriend(friendId, u, chatId);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'remove',
                                  child: Row(children: [
                                    const Icon(Icons.person_remove_rounded,
                                      color: kRed, size: 18),
                                    const SizedBox(width: 10),
                                    Text('Remove Friend',
                                      style: TextStyle(
                                        color: kRed, fontSize: 14)),
                                  ])),
                              ]),
                          ])));
                    });
                });
            }),
        ]));
  }

  Widget _emptyState(IconData icon, String title, String sub) =>
    Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 34, color: kAccent)),
        const SizedBox(height: 16),
        Text(title,
          style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold,
            color: isDark ? kTextPrimary : kLightText)),
        const SizedBox(height: 6),
        Text(sub,
          style: TextStyle(
            color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13),
          textAlign: TextAlign.center),
      ]));

  Future<void> _removeFriend(String uid, Map u, String chatId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? kCard : kLightCard,
        title: Text('Remove friend?',
          style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
        content: Text('Remove ${u['name'] ?? 'this user'} from friends?',
          style: TextStyle(
            color: isDark ? kTextSecondary : kLightTextSub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: kRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove')),
        ]));
    if (confirm != true) return;
    await db.collection('users').doc(_myUid)
      .collection('friends').doc(uid).delete();
    await db.collection('users').doc(uid)
      .collection('friends').doc(_myUid).delete();
    await db.collection('users').doc(_myUid)
      .update({'friendCount': FieldValue.increment(-1)});
    await db.collection('users').doc(uid)
      .update({'friendCount': FieldValue.increment(-1)});
    final chatDoc = await db.collection('chats').doc(chatId).get();
    if (chatDoc.exists) {
      final messages = await chatDoc.reference.collection('messages').get();
      final batch = db.batch();
      for (var msg in messages.docs) batch.delete(msg.reference);
      batch.delete(chatDoc.reference);
      await batch.commit();
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${u['name']} removed'),
        backgroundColor: isDark ? kCard2 : kLightCard2));
  }
}


