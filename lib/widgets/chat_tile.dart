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

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot>(
    stream: db.collection('users').doc(otherUid).snapshots(),
    builder: (_, snap) {
      final u       = snap.data?.data() as Map<String, dynamic>? ?? {};
      final name    = u['name'] as String? ?? 'User';
      final avatar  = u['avatar'] as String? ?? name[0].toUpperCase();
      final online  = u['isOnline'] == true;
      final lastMsg = chatData['lastMessage'] as String? ?? '';
      final lastTs  = chatData['lastTimestamp'] as Timestamp?;
      final unread  = (chatData['unread_$myUid'] ?? 0) as int;
      final isMine  = chatData['lastSender'] == myUid;
      final nickname = chatData['nickname_$myUid'] as String?;
      final displayName = nickname ?? name;

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(children: [
          CircleAvatar(radius: 26, backgroundColor: kGreen,
            child: Text(avatar,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
          if (online) Positioned(right: 0, bottom: 0,
            child: Container(width: 13, height: 13,
              decoration: BoxDecoration(
                color: kGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
        ]),
        title: Row(children: [
          Expanded(child: Text(displayName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          Text(_timeAgo(lastTs),
            style: TextStyle(
              color: unread > 0 ? kGreen : Colors.grey[500],
              fontSize: 12,
              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
        ]),
        subtitle: Row(children: [
          if (isMine) const Icon(Icons.done_all_rounded, size: 14, color: kGreen),
          if (isMine) const SizedBox(width: 4),
          Expanded(child: Text(lastMsg,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unread > 0
                ? Theme.of(context).textTheme.bodyLarge?.color
                : Colors.grey[500],
              fontSize: 13,
              fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal))),
          if (unread > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(10)),
            child: Text('$unread',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatScreen(
            otherUid: otherUid, otherName: name,
            otherAvatar: avatar, chatId: chatId))));
    });
}
