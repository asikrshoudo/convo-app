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

    if (type == 'dm') {
      final chatId     = data['data']?['chatId']     as String? ?? '';
      final senderId   = data['data']?['senderId']   as String? ?? '';
      final senderName = data['data']?['senderName'] as String? ?? 'User';
      if (chatId.isEmpty || senderId.isEmpty) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUid:    senderId,
          otherName:   senderName,
          otherAvatar: senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
          chatId:      chatId)));
    } else if (type == 'group') {
      final groupId   = data['data']?['groupId'] as String? ?? '';
      final groupName = data['title']             as String? ?? 'Group';
      if (groupId.isEmpty) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          groupId: groupId, groupName: groupName)));
    } else if (type == 'friend_request' ||
               type == 'friend_accepted' ||
               type == 'follow') {
      final fromUid = data['data']?['fromUid'] as String? ?? '';
      if (fromUid.isEmpty) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProfileScreen(uid: fromUid)));
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
      default:                return isDark ? kTextSecondary : kLightTextSub;
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

  Widget _emptyState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
      child: const Icon(Icons.notifications_none_rounded,
        size: 36, color: kAccent)),
    const SizedBox(height: 20),
    Text('No notifications yet',
      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
        color: isDark ? kTextPrimary : kLightText)),
    const SizedBox(height: 8),
    Text("You'll be notified when something happens",
      style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
  ]));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        title: const Text('Notifications',
          style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read',
              style: TextStyle(color: kAccent, fontSize: 13))),
        ]),
      // ── No orderBy to avoid composite index requirement ────────────────
      // Sort client-side instead
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('notifications')
          .where('uid', isEqualTo: _myUid)
          .limit(50)
          .snapshots(),
        builder: (_, snap) {
          if (snap.hasError)  return _emptyState();
          if (!snap.hasData)  return const Center(
            child: CircularProgressIndicator(color: kAccent, strokeWidth: 2));

          // Sort by createdAt descending on client
          final docs = [...snap.data!.docs];
          docs.sort((a, b) {
            final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
            final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

          if (docs.isEmpty) return _emptyState();

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
              Divider(height: 0, color: isDark ? kDivider : kLightDivider.withOpacity(0.5)),
            itemBuilder: (_, i) {
              final doc   = docs[i];
              final data  = doc.data() as Map<String, dynamic>;
              final read  = data['read'] == true;
              final type  = data['data']?['type'] as String? ?? '';
              final ts    = data['createdAt'] as Timestamp?;
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
                          fontWeight: read ? FontWeight.normal : FontWeight.bold,
                          fontSize: 14, color: isDark ? kTextPrimary : kLightText)),
                      const SizedBox(height: 2),
                      Text(data['body'] ?? '',
                        style: TextStyle(
                          color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(_timeAgo(ts),
                        style: TextStyle(
                          color: isDark ? kTextTertiary : kLightTextSub, fontSize: 11)),
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
