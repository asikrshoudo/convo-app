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
      .where('read', isEqualTo: false).get();
    final batch = db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _markRead(String docId) async =>
    db.collection('notifications').doc(docId).update({'read': true});

  void _onTap(Map<String, dynamic> data, String docId) {
    _markRead(docId);
    final type = data['data']?['type'] as String? ?? '';
    switch (type) {
      case 'dm':
        final chatId     = data['data']?['chatId']     as String? ?? '';
        final senderId   = data['data']?['senderId']   as String? ?? '';
        final senderName = data['data']?['senderName'] as String? ?? 'User';
        if (chatId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(
              otherUid: senderId, otherName: senderName,
              otherAvatar: senderName.isNotEmpty
                ? senderName[0].toUpperCase() : 'U',
              chatId: chatId)));
        }
        break;
      case 'group':
        final groupId   = data['data']?['groupId']   as String? ?? '';
        final groupName = data['title']               as String? ?? 'Group';
        if (groupId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => GroupChatScreen(
              groupId: groupId, groupName: groupName)));
        }
        break;
      case 'friend_request':
      case 'friend_accepted':
      case 'follow':
        final fromUid = data['data']?['fromUid'] as String? ?? '';
        if (fromUid.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ProfileScreen(uid: fromUid)));
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
      case 'group':           return kAccent;
      case 'friend_request':  return const Color(0xFF2C7BE5);
      case 'friend_accepted': return const Color(0xFF34C759);
      case 'follow':          return const Color(0xFF7C3AED);
      default:                return kTextSecondary;
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60)  return 'just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    if (diff.inDays    < 7)   return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      appBar: AppBar(
        backgroundColor: kDark,
        title: const Text('Notifications',
          style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read',
              style: TextStyle(color: kAccent, fontSize: 13))),
        ]),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('notifications')
          .where('uid', isEqualTo: _myUid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
        builder: (_, snap) {
          if (snap.hasError) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_none_rounded,
                  size: 36, color: kAccent)),
              const SizedBox(height: 20),
              const Text('No notifications yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                  color: kTextPrimary)),
              const SizedBox(height: 8),
              const Text("You'll be notified when something happens",
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
            ]));
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(
              color: kAccent, strokeWidth: 2));
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_none_rounded,
                  size: 36, color: kAccent)),
              const SizedBox(height: 20),
              const Text('No notifications yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                  color: kTextPrimary)),
              const SizedBox(height: 8),
              const Text("You'll be notified when something happens",
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
            ]));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
              Divider(height: 0, color: kDivider.withOpacity(0.5)),
            itemBuilder: (_, i) {
              final doc  = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final read = data['read'] == true;
              final type = data['data']?['type'] as String? ?? '';
              final ts   = data['createdAt'] as Timestamp?;
              final color = _iconColor(type);

              return InkWell(
                onTap: () => _onTap(data, doc.id),
                child: Container(
                  color: read ? Colors.transparent : kAccent.withOpacity(0.06),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.13),
                        shape: BoxShape.circle),
                      child: Icon(_icon(type), color: color, size: 22)),
                    const SizedBox(width: 13),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(data['title'] ?? '',
                        style: TextStyle(
                          fontWeight: read
                            ? FontWeight.normal : FontWeight.bold,
                          fontSize: 14, color: kTextPrimary)),
                      const SizedBox(height: 2),
                      Text(data['body'] ?? '',
                        style: const TextStyle(
                          color: kTextSecondary, fontSize: 13),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(_timeAgo(ts),
                        style: const TextStyle(
                          color: kTextTertiary, fontSize: 11)),
                    ])),
                    if (!read) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: kAccent, shape: BoxShape.circle)),
                    ],
                  ])));
            });
        }));
  }
}
