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
  static const _notifyBase = 'https://convo-notify.onrender.com';

  late TabController _tab;
  final _searchCtrl = TextEditingController();
  final _myUid = auth.currentUser!.uid;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final snap = await db
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q.toLowerCase())
          .where('username', isLessThan: '${q.toLowerCase()}z')
          .limit(20)
          .get();
      setState(() =>
          _results = snap.docs.map((d) => {...d.data(), 'uid': d.id}).toList());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(String toUid, String toName, String toAvatar) async {
    final fd = await db
        .collection('users')
        .doc(_myUid)
        .collection('friends')
        .doc(toUid)
        .get();
    if (fd.exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Already friends!'),
            backgroundColor: kGreen,
          ),
        );
      }
      return;
    }
    final targetDoc = await db.collection('users').doc(toUid).get();
    final targetMode = targetDoc.data()?['profileMode'] ?? 'friend';

    if (targetMode == 'follow') {
      await db
          .collection('users')
          .doc(_myUid)
          .collection('following')
          .doc(toUid)
          .set({'uid': toUid, 'since': FieldValue.serverTimestamp()});
      await db
          .collection('users')
          .doc(toUid)
          .collection('followers')
          .doc(_myUid)
          .set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
      await db
          .collection('users')
          .doc(toUid)
          .update({'followerCount': FieldValue.increment(1)});
      await db
          .collection('users')
          .doc(_myUid)
          .update({'followingCount': FieldValue.increment(1)});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Now following $toName'),
            backgroundColor: kGreen,
          ),
        );
      }
    } else {
      final ex = await db
          .collection('friend_requests')
          .where('from', isEqualTo: _myUid)
          .where('to', isEqualTo: toUid)
          .where('status', isEqualTo: 'pending')
          .get();
      if (ex.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request already sent!')),
          );
        }
        return;
      }
      final my = await db.collection('users').doc(_myUid).get();
      await db.collection('friend_requests').add({
        'from': _myUid,
        'fromName': my.data()?['name'] ?? 'User',
        'fromAvatar': my.data()?['avatar'] ?? 'U',
        'to': toUid,
        'toName': toName,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      // Notify receiver
      try {
        final my2 = await db.collection('users').doc(_myUid).get();
        await http.post(
          Uri.parse('$_notifyBase/notify/friend-request'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fromUid': _myUid, 'fromName': my2.data()?['name'] ?? 'User', 'toUid': toUid}),
        );
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request sent to $toName'),
            backgroundColor: kGreen,
          ),
        );
      }
    }
  }
Future<void> _accept(String docId, String fromUid) async {
  await db.collection('friend_requests').doc(docId).update({'status': 'accepted'});
  await db
      .collection('users')
      .doc(_myUid)
      .collection('friends')
      .doc(fromUid)
      .set({'uid': fromUid, 'since': FieldValue.serverTimestamp()});
  await db
      .collection('users')
      .doc(fromUid)
      .collection('friends')
      .doc(_myUid)
      .set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
  await db
      .collection('users')
      .doc(_myUid)
      .update({'friendCount': FieldValue.increment(1)});
  await db
      .collection('users')
      .doc(fromUid)
      .update({'friendCount': FieldValue.increment(1)});
  // Notify the original sender that request was accepted
  try {
    final me = await db.collection('users').doc(_myUid).get();
    await http.post(
      Uri.parse('$_notifyBase/notify/friend-accepted'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fromUid': fromUid, 'accepterName': me.data()?['name'] ?? 'Someone'}),
    );
  } catch (_) {}
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend added!'), backgroundColor: kGreen),
    );
  }
}

@override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark ? kCard : Colors.grey[100]!;

  return Scaffold(
    appBar: AppBar(
      title: Text(
        widget.startChat ? 'New Message' : 'Friends',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      bottom: TabBar(
        controller: _tab,
        indicatorColor: kGreen,
        labelColor: kGreen,
        unselectedLabelColor: Colors.grey,
        tabs: const [
          Tab(icon: Icon(Icons.search_rounded), text: 'Search'),
          Tab(icon: Icon(Icons.notifications_outlined), text: 'Requests'),
          Tab(icon: Icon(Icons.people_rounded), text: 'Friends'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tab,
      children: [
        // ── Search tab ───────────────────────────────────────────────────
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _search,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Search by username...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                  filled: true,
                  fillColor: bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: kGreen),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final u = _results[i];
                    if (u['uid'] == _myUid) return const SizedBox();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kGreen,
                        child: Text(
                          u['avatar'] ?? '?',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        u['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '@${u['username']}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                      trailing: widget.startChat
                          ? FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: kGreen,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                final ids = [_myUid, u['uid'] as String]..sort();
                                final chatId = ids.join('_');
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      otherUid: u['uid'],
                                      otherName: u['name'] ?? 'User',
                                      otherAvatar: u['avatar'] ?? '?',
                                      chatId: chatId,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Message'),
                            )
                          : StreamBuilder<DocumentSnapshot>(
                              stream: db
                                  .collection('users')
                                  .doc(_myUid)
                                  .collection('friends')
                                  .doc(u['uid'] as String)
                                  .snapshots(),
                              builder: (_, fSnap) {
                                if (fSnap.data?.exists == true) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: kGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Friends',
                                      style: TextStyle(
                                          color: kGreen,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  );
                                }
                                return OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: kGreen),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _sendRequest(
                                      u['uid'], u['name'] ?? 'User', u['avatar'] ?? 'U'),
                                  child: Text(
                                    u['profileMode'] == 'follow' ? 'Follow' : 'Add',
                                    style: const TextStyle(color: kGreen),
                                  ),
                                );
                              },
                            ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ProfileScreen(uid: u['uid'])),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),

        // ── Requests tab ─────────────────────────────────────────────────
        StreamBuilder<QuerySnapshot>(
          stream: db
              .collection('friend_requests')
              .where('to', isEqualTo: _myUid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_rounded, size: 48, color: Colors.grey[600]),
                    const SizedBox(height: 12),
                    Text(
                      'No pending requests',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: kGreen,
                    child: Text(
                      d['fromAvatar'] ?? 'U',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    d['fromName'] ?? 'User',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Sent you a friend request',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _accept(doc.id, d['from']),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: kGreen.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: kGreen, size: 22),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => db
                            .collection('friend_requests')
                            .doc(doc.id)
                            .update({'status': 'declined'}),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.red, size: 22),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProfileScreen(uid: d['from'])),
                  ),
                );
              }).toList(),
            );
          },
        ),
        
                  // ── My Friends tab ───────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('users')
                .doc(_myUid)
                .collection('friends')
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      Text(
                        'No friends yet',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
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

                      Future<void> _removeFriend() async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Remove friend?'),
                            content: Text(
                                'Are you sure you want to remove ${u['name'] ?? 'this user'} from your friends?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;

                        // Remove from both friends subcollections
                        await db
                            .collection('users')
                            .doc(_myUid)
                            .collection('friends')
                            .doc(doc.id)
                            .delete();
                        await db
                            .collection('users')
                            .doc(doc.id)
                            .collection('friends')
                            .doc(_myUid)
                            .delete();

                        // Decrement friend counts
                        await db
                            .collection('users')
                            .doc(_myUid)
                            .update({'friendCount': FieldValue.increment(-1)});
                        await db
                            .collection('users')
                            .doc(doc.id)
                            .update({'friendCount': FieldValue.increment(-1)});

                        // Optionally delete the chat
                        final chatDoc =
                            await db.collection('chats').doc(chatId).get();
                        if (chatDoc.exists) {
                          final messages = await chatDoc.reference
                              .collection('messages')
                              .get();
                          final batch = db.batch();
                          for (var msg in messages.docs) {
                            batch.delete(msg.reference);
                          }
                          batch.delete(chatDoc.reference);
                          await batch.commit();
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${u['name']} removed'),
                              backgroundColor: kGreen,
                            ),
                          );
                        }
                      }

                      return ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: kGreen,
                              child: Text(
                                u['avatar'] ?? '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (online)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: kGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          u['name'] ?? 'User',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          online ? 'Online' : '@${u['username'] ?? ''}',
                          style: TextStyle(
                            color: online ? kGreen : Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (value) {
                            if (value == 'remove') _removeFriend();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'remove',
                              child: Row(
                                children: [
                                  Icon(Icons.person_remove_rounded,
                                      color: Colors.red, size: 20),
                                  SizedBox(width: 8),
                                  Text('Remove friend',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProfileScreen(uid: doc.id)),
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}