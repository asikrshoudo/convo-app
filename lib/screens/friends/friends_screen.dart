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
  List<Map<String, dynamic>> _results    = [];
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

  // ── Suggestions: random users with suggestionsEnabled = true ──────────────
  Future<void> _loadSuggestions() async {
    try {
      final snap = await db.collection('users')
        .where('suggestionsEnabled', isEqualTo: true)
        .limit(30)
        .get();

      final friends = await db.collection('users')
        .doc(_myUid).collection('friends').get();
      final friendIds = friends.docs.map((d) => d.id).toSet();

      final all = snap.docs
        .where((d) => d.id != _myUid && !friendIds.contains(d.id))
        .map((d) => {...d.data(), 'uid': d.id})
        .toList();
      all.shuffle();

      if (mounted) setState(() => _suggestions = all.take(10).toList());
    } catch (_) {}
  }

  // ── Search: matches username OR name prefix on every character ────────────
  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final qLow = q.trim().toLowerCase();

      // Query by username prefix
      final byUsername = await db.collection('users')
        .where('username', isGreaterThanOrEqualTo: qLow)
        .where('username', isLessThan: '${qLow}z')
        .limit(15).get();

      // Query by name prefix (case-insensitive via lowercase name field)
      final byName = await db.collection('users')
        .where('nameLower', isGreaterThanOrEqualTo: qLow)
        .where('nameLower', isLessThan: '${qLow}z')
        .limit(15).get();

      // Merge and deduplicate
      final Map<String, Map<String, dynamic>> merged = {};
      for (final doc in [...byUsername.docs, ...byName.docs]) {
        merged[doc.id] = {...doc.data(), 'uid': doc.id};
      }
      merged.remove(_myUid);

      if (mounted) setState(() { _results = merged.values.toList(); });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(String toUid, String toName, String toAvatar) async {
    final fd = await db.collection('users').doc(_myUid)
      .collection('friends').doc(toUid).get();
    if (fd.exists) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already friends!'), backgroundColor: kAccent));
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
        'fromUid': _myUid,
        'fromName': my.data()?['name'] ?? 'User',
        'fromAvatar': my.data()?['avatar'] ?? 'U',
        'fromUsername': (await db.collection('users').doc(_myUid).get()).data()?['username'] ?? '',
        'toUid': toUid, 'toName': toName,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      try {
        await http.post(
          Uri.parse('$_notifyBase/notify/friend-request'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fromUid': _myUid,
            'fromName': my.data()?['name'] ?? 'User', 'toUid': toUid}));
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request sent to $toName'),
          backgroundColor: kAccent));
    }
  }

  Future<void> _accept(String docId, String fromUid) async {
    await db.collection('friend_requests').doc(docId).update({'status': 'accepted'});
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
        body: jsonEncode({'fromUid': fromUid,
          'accepterName': me.data()?['name'] ?? 'Someone'}));
    } catch (_) {}
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend added! 🎉'),
        backgroundColor: kAccent));
  }

  // ─── User tile ─────────────────────────────────────────────────────────────
  Widget _userTile(Map<String, dynamic> u) {
    final uid = u['uid'] as String;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: kAccent.withOpacity(0.18), shape: BoxShape.circle),
        child: Center(child: Text(u['avatar'] ?? '?',
          style: const TextStyle(color: kAccent,
            fontWeight: FontWeight.bold, fontSize: 16)))),
      title: Text(u['name'] ?? '',
        style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? kTextPrimary : kLightText)),
      subtitle: Text('@${u['username']}',
        style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
      trailing: widget.startChat
        ? FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              final ids = [_myUid, uid]..sort();
              final chatId = ids.join('_');
              Navigator.pushReplacement(context, MaterialPageRoute(
                builder: (_) => ChatScreen(
                  otherUid: uid, otherName: u['name'] ?? 'User',
                  otherAvatar: u['avatar'] ?? '?', chatId: chatId)));
            },
            child: const Text('Message'))
        : StreamBuilder<DocumentSnapshot>(
            stream: db.collection('users').doc(_myUid)
              .collection('friends').doc(uid).snapshots(),
            builder: (_, fSnap) {
              if (fSnap.data?.exists == true) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Text('Friends',
                    style: TextStyle(color: kAccent,
                      fontWeight: FontWeight.bold, fontSize: 12)));
              }
              return StreamBuilder<QuerySnapshot>(
                stream: db.collection('friend_requests')
                  .where('fromUid', isEqualTo: _myUid)
                  .where('toUid', isEqualTo: uid)
                  .where('status', isEqualTo: 'pending').snapshots(),
                builder: (_, rSnap) {
                  final sent = (rSnap.data?.docs.isNotEmpty) == true;
                  return OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: sent ? isDark ? kDivider : kLightDivider : kAccent),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                    onPressed: sent ? null : () => _sendRequest(
                      uid, u['name'] ?? 'User', u['avatar'] ?? 'U'),
                    child: Text(
                      sent ? 'Requested'
                        : (u['profileMode'] == 'follow' ? 'Follow' : 'Add'),
                      style: TextStyle(
                        color: sent ? isDark ? kTextSecondary : kLightTextSub : kAccent,
                        fontSize: 12)));
                });
            }),
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        title: Text(widget.startChat ? 'New Message' : 'Friends',
          style: const TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: kAccent,
          labelColor: kAccent,
          unselectedLabelColor: isDark ? kTextSecondary : kLightTextSub,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(icon: Icon(Icons.search_rounded, size: 20), text: 'Search'),
            Tab(icon: Icon(Icons.notifications_outlined, size: 20), text: 'Requests'),
            Tab(icon: Icon(Icons.people_rounded, size: 20), text: 'Friends'),
          ])),
      body: TabBarView(
        controller: _tab,
        children: [

          // ── Search tab ─────────────────────────────────────────────────────
          CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _search,
                style: TextStyle(color: isDark ? kTextPrimary : kLightText),
                decoration: InputDecoration(
                  hintText: 'Search by name or username...',
                  prefixIcon: Icon(Icons.search_rounded,
                    color: isDark ? kTextSecondary : kLightTextSub),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                          color: isDark ? kTextSecondary : kLightTextSub, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search('');
                        })
                    : null)))),

            // Search results
            if (_searching)
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(
                  color: kAccent, strokeWidth: 2))))
            else if (_searchCtrl.text.isNotEmpty && _results.isEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  Icon(Icons.search_off_rounded,
                    size: 48, color: isDark ? kTextSecondary : kLightTextSub),
                  const SizedBox(height: 12),
                  Text('No users found for "${_searchCtrl.text}"',
                    style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub),
                    textAlign: TextAlign.center),
                ])))
            else if (_results.isNotEmpty)
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _userTile(_results[i]),
                childCount: _results.length)),

            // Divider between results and suggestions
            if (_searchCtrl.text.isEmpty || _results.isEmpty)
              SliverToBoxAdapter(child: Column(children: [
                if (_suggestions.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(children: [
                      const Icon(Icons.auto_awesome_rounded,
                        color: kAccent, size: 16),
                      const SizedBox(width: 6),
                      const Text('People you may know',
                        style: TextStyle(
                          color: kAccent, fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                    ])),
                ],
              ])),

            // Suggestions list
            if (_searchCtrl.text.isEmpty && _suggestions.isNotEmpty)
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  if (i < _suggestions.length) {
                    return _userTile(_suggestions[i]);
                  }
                  if (i == _suggestions.length) {
                    return TextButton(
                      onPressed: _loadSuggestions,
                      child: Text('Refresh suggestions',
                        style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)));
                  }
                  return null;
                },
                childCount: _suggestions.length + 1)),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),

          // ── Requests tab ───────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('friend_requests')
              .where('toUid', isEqualTo: _myUid)
              .where('status', isEqualTo: 'pending').snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.inbox_rounded,
                      size: 32, color: kAccent)),
                  const SizedBox(height: 12),
                  Text('No pending requests',
                    style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
                ]));
              }
              final docs = snap.data!.docs.toList()..sort((a, b) {
                final aTs = (a.data() as Map)['timestamp'];
                final bTs = (b.data() as Map)['timestamp'];
                if (aTs == null && bTs == null) return 0;
                if (aTs == null) return 1;
                if (bTs == null) return -1;
                return (bTs as dynamic).compareTo(aTs);
              });
              return ListView(
                children: docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: kAccent.withOpacity(0.18),
                        shape: BoxShape.circle),
                      child: Center(child: Text(d['fromAvatar'] ?? 'U',
                        style: const TextStyle(color: kAccent,
                          fontWeight: FontWeight.bold, fontSize: 16)))),
                    title: Text(d['fromName'] ?? 'User',
                      style: TextStyle(fontWeight: FontWeight.w600,
                        color: isDark ? kTextPrimary : kLightText)),
                    subtitle: Text('Sent you a friend request',
                      style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      GestureDetector(
                        onTap: () => _accept(doc.id, d['fromUid']),
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: kAccent.withOpacity(0.15),
                            shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                            color: kAccent, size: 22))),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => db.collection('friend_requests')
                          .doc(doc.id).update({'status': 'declined'}),
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: kRed.withOpacity(0.12),
                            shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded,
                            color: kRed, size: 22))),
                    ]),
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProfileScreen(uid: d['fromUid']))));
                }).toList());
            }),

          // ── My Friends tab ─────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('users').doc(_myUid)
              .collection('friends').snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.people_outline_rounded,
                      size: 32, color: kAccent)),
                  const SizedBox(height: 12),
                  Text('No friends yet',
                    style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
                ]));
              }
              return ListView(
                children: snap.data!.docs.map((doc) {
                  return StreamBuilder<DocumentSnapshot>(
                    stream: db.collection('users').doc(doc.id).snapshots(),
                    builder: (_, uSnap) {
                      final u = uSnap.data?.data() as Map<String, dynamic>? ?? {};
                      final online = u['isOnline'] == true;
                      final ids = [_myUid, doc.id]..sort();
                      final chatId = ids.join('_');

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                        leading: Stack(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.18),
                              shape: BoxShape.circle),
                            child: Center(child: Text(u['avatar'] ?? '?',
                              style: const TextStyle(color: kAccent,
                                fontWeight: FontWeight.bold, fontSize: 16)))),
                          if (online) Positioned(right: 0, bottom: 0,
                            child: Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759),
                                shape: BoxShape.circle,
                                border: Border.all(color: isDark ? kDark : kLightBg, width: 2)))),
                        ]),
                        title: Text(u['name'] ?? 'User',
                          style: TextStyle(fontWeight: FontWeight.w600,
                            color: isDark ? kTextPrimary : kLightText)),
                        subtitle: Text(
                          online ? 'Online' : '@${u['username'] ?? ''}',
                          style: TextStyle(
                            color: online ? const Color(0xFF34C759) : isDark ? kTextSecondary : kLightTextSub,
                            fontSize: 12)),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded,
                            color: isDark ? kTextSecondary : kLightTextSub),
                          color: isDark ? kCard2 : kLightCard2,
                          onSelected: (v) async {
                            if (v == 'remove') await _removeFriend(doc.id, u, chatId);
                            if (v == 'message') {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  otherUid: doc.id,
                                  otherName: u['name'] ?? 'User',
                                  otherAvatar: u['avatar'] ?? '?',
                                  chatId: chatId)));
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'message',
                              child: Row(children: [
                                Icon(Icons.chat_bubble_outline_rounded,
                                  color: kAccent, size: 20),
                                SizedBox(width: 8),
                                Text('Message'),
                              ])),
                            const PopupMenuItem(value: 'remove',
                              child: Row(children: [
                                Icon(Icons.person_remove_rounded,
                                  color: kRed, size: 20),
                                SizedBox(width: 8),
                                Text('Remove friend',
                                  style: TextStyle(color: kRed)),
                              ])),
                          ]),
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(uid: doc.id))));
                    });
                }).toList());
            }),
        ]));
  }

  Future<void> _removeFriend(String uid, Map u, String chatId) async {

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? kCard : kLightCard,
        title: Text('Remove friend?',
          style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
        content: Text('Remove ${u['name'] ?? 'this user'} from friends?',
          style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
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
