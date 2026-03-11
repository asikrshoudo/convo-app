import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import 'chats/chat_screen.dart';
import 'chats/group_chat_screen.dart';
import 'profile/profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _myUid = auth.currentUser!.uid;

  Future<void> _markAllRead() async {
    final snap = await db.collection('notifications')
      .where('uid', isEqualTo: _myUid)
      .where('read', isEqualTo: false)
      .get();
    final batch = db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _markRead(String docId) async {
    await db.collection('notifications').doc(docId).update({'read': true});
  }

  void _onTap(Map<String, dynamic> data, String docId) {
    _markRead(docId);
    final type = data['data']?['type'] as String? ?? '';
    switch (type) {
      case 'dm':
        final chatId     = data['data']?['chatId'] as String? ?? '';
        final senderId   = data['data']?['senderId'] as String? ?? '';
        final senderName = data['data']?['senderName'] as String? ?? 'User';
        if (chatId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
            otherUid: senderId, otherName: senderName,
            otherAvatar: senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
            chatId: chatId)));
        }
        break;
      case 'group':
        final groupId   = data['data']?['groupId'] as String? ?? '';
        final groupName = data['title'] as String? ?? 'Group';
        if (groupId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (_) =>
            GroupChatScreen(groupId: groupId, groupName: groupName)));
        }
        break;
      case 'friend_request':
      case 'friend_accepted':
      case 'follow':
        final fromUid = data['data']?['fromUid'] as String? ?? '';
        if (fromUid.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (_) =>
            ProfileScreen(uid: fromUid)));
        }
        break;
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'dm':              return Icons.chat_bubble_rounded;
      case 'group':           return Icons.group_rounded;
      case 'friend_request':  return Icons.person_add_rounded;
      case 'friend_accepted': return Icons.people_rounded;
      case 'follow':          return Icons.person_rounded;
      default:                return Icons.notifications_rounded;
    }
  }

  Color _iconColor(String type) {
    switch (type) {
      case 'dm':
      case 'group':           return kGreen;
      case 'friend_request':  return Colors.blue;
      case 'friend_accepted': return Colors.green;
      case 'follow':          return Colors.purple;
      default:                return Colors.grey;
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read', style: TextStyle(color: kGreen, fontSize: 13))),
        ]),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('notifications')
          .where('uid', isEqualTo: _myUid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
        builder: (_, snap) {
          // Error state — likely missing Firestore index
          if (snap.hasError) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              const Text('No notifications yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text("You'll be notified when something happens",
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ]));
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: kGreen));
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.1),
                  shape: BoxShape.circle),
                child: const Icon(Icons.notifications_none_rounded, size: 40, color: kGreen)),
              const SizedBox(height: 20),
              const Text('No notifications yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("You'll be notified when something happens",
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ]));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(height: 0, color: Colors.grey.withOpacity(0.08)),
            itemBuilder: (_, i) {
              final doc  = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final read = data['read'] == true;
              final type = data['data']?['type'] as String? ?? '';
              final ts   = data['createdAt'] as Timestamp?;

              return InkWell(
                onTap: () => _onTap(data, doc.id),
                child: Container(
                  color: read ? Colors.transparent : kGreen.withOpacity(0.06),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: _iconColor(type).withOpacity(0.12),
                        shape: BoxShape.circle),
                      child: Icon(_icon(type), color: _iconColor(type), size: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(data['title'] ?? '',
                        style: TextStyle(
                          fontWeight: read ? FontWeight.normal : FontWeight.bold,
                          fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(data['body'] ?? '',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(_timeAgo(ts),
                        style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    ])),
                    if (!read)
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle)),
                  ])));
            });
        }));
  }
}
