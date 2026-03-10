import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

class ChatBubble extends StatelessWidget {
  final String msgId, chatId;
  final Map<String, dynamic> data;
  final bool isMe, isFirst;
  final void Function(String id, String text, String sender) onReply;

  const ChatBubble({
    super.key,
    required this.msgId,
    required this.chatId,
    required this.data,
    required this.isMe,
    required this.isFirst,
    required this.onReply,
  });

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final text     = data['text'] as String? ?? '';
    final deleted  = data['deleted'] == true;
    final reply    = data['reply'] as Map<String, dynamic>?;
    final ts       = data['timestamp'] as Timestamp?;
    final expiresAt = data['expiresAt'] as Timestamp?;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if (!deleted && (d.primaryVelocity ?? 0) < -100) {
          onReply(msgId, text, data['senderName'] ?? '');
        }
      },
      onLongPress: () {
        if (deleted) return;
        showModalBottomSheet(
          context: context,
          backgroundColor: isDark ? kCard : Colors.white,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: kGreen),
              title: const Text('Reply'),
              onTap: () { Navigator.pop(context); onReply(msgId, text, data['senderName'] ?? ''); }),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () { Navigator.pop(context); Clipboard.setData(ClipboardData(text: text)); }),
            if (isMe) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                db.collection('chats').doc(chatId).collection('messages').doc(msgId)
                  .update({'deleted': true, 'text': 'Message deleted'});
              }),
            const SizedBox(height: 12),
          ]));
      },
      child: Padding(
        padding: EdgeInsets.only(
          top: isFirst ? 8 : 2, bottom: 2,
          left: isMe ? 56 : 0, right: isMe ? 0 : 56),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isMe ? kGreen : (isDark ? kCard2 : Colors.white),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))
                  ]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (reply != null) Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(left: BorderSide(color: Colors.white54, width: 3))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(reply['sender'] ?? '',
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text(reply['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ])),
                    Text(text,
                      style: TextStyle(
                        color: deleted
                          ? (isMe ? Colors.white54 : Colors.grey[500])
                          : (isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color),
                        fontSize: 15,
                        fontStyle: deleted ? FontStyle.italic : FontStyle.normal)),
                  ]))),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_fmt(ts), style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                if (expiresAt != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.timer_outlined, size: 10, color: Colors.grey),
                ],
              ]),
            ]))));
  }
}
