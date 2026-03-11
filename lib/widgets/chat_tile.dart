import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import '../screens/chats/chat_screen.dart';

class ChatTile extends StatelessWidget {
  final Map<String, dynamic> chatData;
  final String otherUid, myUid, chatId;

  const ChatTile({
    super.key,
    required this.chatData,
    required this.otherUid,
    required this.myUid,
    required this.chatId,
  });

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1)  return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24)   return '${d.inHours}h';
    if (d.inDays < 7)     return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  Future<void> _deleteChat(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('This will delete the conversation for you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: kRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete')),
        ]));
    if (confirm != true) return;

    final messages =
        await db.collection('chats').doc(chatId).collection('messages').get();
    final batch = db.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(db.collection('chats').doc(chatId));
    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted'), backgroundColor: kCard2));
    }
  }

  Future<void> _markUnread() async {
    await db.collection('chats').doc(chatId).set(
      {'unread_$myUid': 1},
      SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection('users').doc(otherUid).snapshots(),
      builder: (_, snap) {
        final u = snap.data?.data() as Map<String, dynamic>? ?? {};
        final name        = u['name'] as String? ?? 'User';
        final avatar      = u['avatar'] as String? ?? name[0].toUpperCase();
        final online      = u['isOnline'] == true;
        final lastMsg     = chatData['lastMessage'] as String? ?? '';
        final lastTs      = chatData['lastTimestamp'] as Timestamp?;
        final unread      = (chatData['unread_$myUid'] ?? 0) as int;
        final isMine      = chatData['lastSender'] == myUid;
        final nickname    = chatData['nickname_$myUid'] as String?;
        final displayName = nickname ?? name;

        return GestureDetector(
          onLongPress: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: kCard,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(kSheetRadius))),
              builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 10),
                Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: kTextTertiary,
                    borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.mark_chat_unread_rounded,
                    color: kAccent),
                  title: const Text('Mark as unread'),
                  onTap: () {
                    Navigator.pop(context);
                    _markUnread();
                  }),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                    color: kRed),
                  title: const Text('Delete chat',
                    style: TextStyle(color: kRed)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteChat(context);
                  }),
                const SizedBox(height: 12),
              ]));
          },
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Stack(children: [
              // iMessage-style tinted avatar
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.18),
                  shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    avatar,
                    style: const TextStyle(
                      color: kAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 20)))),
              if (online)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 13, height: 13,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759),
                      shape: BoxShape.circle,
                      border: Border.all(color: kDark, width: 2)))),
            ]),
            title: Row(children: [
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 15,
                    color: kTextPrimary),
                  overflow: TextOverflow.ellipsis)),
              Text(
                _timeAgo(lastTs),
                style: TextStyle(
                  color: unread > 0 ? kAccent : kTextSecondary,
                  fontSize: 12,
                  fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
            ]),
            subtitle: Row(children: [
              if (isMine)
                const Icon(Icons.done_all_rounded, size: 14, color: kAccent),
              if (isMine) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  lastMsg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unread > 0 ? kTextPrimary : kTextSecondary,
                    fontSize: 13,
                    fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal))),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: kAccent,
                    borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.bold))),
            ]),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  otherUid: otherUid,
                  otherName: name,
                  otherAvatar: avatar,
                  chatId: chatId)))));
      });
  }
}
