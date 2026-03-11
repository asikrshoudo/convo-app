import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

class ChatBubble extends StatefulWidget {
  final String msgId, chatId;
  final Map<String, dynamic> data;
  final bool isMe, isFirst, isLast;
  final void Function(String id, String text, String sender) onReply;
  final String myUid;
  final String? otherUid;

  const ChatBubble({
    super.key,
    required this.msgId,
    required this.chatId,
    required this.data,
    required this.isMe,
    required this.isFirst,
    required this.isLast,
    required this.onReply,
    required this.myUid,
    this.otherUid,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool   _replyTriggered = false;
  late final AnimationController _snapCtrl;
  late final Animation<double>   _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _snapAnim = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    _snapCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final deleted = widget.data['deleted'] == true;
    if (deleted) return;

    // My msgs: drag left (negative dx); others' msgs: drag right (positive dx)
    final delta = widget.isMe ? d.delta.dx : -d.delta.dx;
    if (delta > 0) return; // wrong direction — ignore

    setState(() {
      _dragOffset = (_dragOffset + d.delta.dx).clamp(
          widget.isMe ? -72.0 : 0.0,
          widget.isMe ? 0.0  : 72.0);
    });

    if (!_replyTriggered && _dragOffset.abs() >= 52) {
      _replyTriggered = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (_replyTriggered) {
      final text    = widget.data['text'] as String? ?? '';
      final deleted = widget.data['deleted'] == true;
      if (!deleted) {
        widget.onReply(
            widget.msgId, text, widget.data['senderName'] ?? '');
      }
    }
    // Snap back
    final from = _dragOffset;
    _snapAnim =
        Tween<double>(begin: from, end: 0).animate(
            CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    _snapCtrl.forward(from: 0);
    setState(() {
      _dragOffset = 0;
      _replyTriggered = false;
    });
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _showMenu(BuildContext context, bool isDark) {
    final text    = widget.data['text'] as String? ?? '';
    final deleted = widget.data['deleted'] == true;
    if (deleted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),

        // Emoji reactions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['❤️', '😂', '😮', '😢', '👍', '👎'].map((emoji) =>
              GestureDetector(
                onTap: () { Navigator.pop(context); _addReaction(emoji); },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? kCard2 : Colors.grey[100],
                    shape: BoxShape.circle),
                  child: Text(emoji,
                    style: const TextStyle(fontSize: 24))))).toList())),

        const Divider(height: 1),

        ListTile(
          leading: const Icon(Icons.reply_rounded, color: kGreen),
          title: const Text('Reply'),
          onTap: () {
            Navigator.pop(context);
            widget.onReply(widget.msgId, text, widget.data['senderName'] ?? '');
          }),
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy'),
          onTap: () {
            Navigator.pop(context);
            Clipboard.setData(ClipboardData(text: text));
          }),

        if (widget.isMe) ...[
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.orange),
            title: const Text('Delete for me', style: TextStyle(color: Colors.orange)),
            onTap: () {
              Navigator.pop(context);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .update({'deletedFor': FieldValue.arrayUnion([widget.myUid])});
            }),
          ListTile(
            leading: const Icon(Icons.undo_rounded, color: Colors.red),
            title: const Text('Unsend', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Remove for everyone', style: TextStyle(fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              // Delete the message document entirely so bubble disappears
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .delete();
            }),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.orange),
            title: const Text('Delete for me', style: TextStyle(color: Colors.orange)),
            onTap: () {
              Navigator.pop(context);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .update({'deletedFor': FieldValue.arrayUnion([widget.myUid])});
            }),
          if (widget.otherUid != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.volume_off_rounded, color: Colors.grey),
              title: const Text('Mute notifications'),
              onTap: () {
                Navigator.pop(context);
                _muteUser(context);
              }),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: Colors.red),
              title: const Text('Block user', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _blockUser(context);
              }),
            ListTile(
              leading: const Icon(Icons.flag_rounded, color: Colors.orange),
              title: const Text('Report', style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.pop(context);
                _reportUser(context, text);
              }),
          ],
        ],
        const SizedBox(height: 12),
      ]));
  }

  Future<void> _addReaction(String emoji) async {
    final reactions = Map<String, dynamic>.from(widget.data['reactions'] ?? {});
    if (reactions[widget.myUid] == emoji) {
      reactions.remove(widget.myUid);
    } else {
      reactions[widget.myUid] = emoji;
    }
    await db.collection('chats').doc(widget.chatId)
      .collection('messages').doc(widget.msgId)
      .update({'reactions': reactions});
  }

  Future<void> _muteUser(BuildContext context) async {
    await db.collection('users').doc(widget.myUid)
      .collection('muted').doc(widget.otherUid).set({
        'mutedAt': FieldValue.serverTimestamp(),
      });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications muted'),
          backgroundColor: Colors.grey));
    }
  }

  Future<void> _blockUser(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Block user?'),
        content: const Text('They won\'t be able to message you. You can unblock from their profile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block', style: TextStyle(color: Colors.red))),
        ]));
    if (confirm != true) return;
    await db.collection('users').doc(widget.myUid)
      .collection('blocked').doc(widget.otherUid).set({
        'blockedAt': FieldValue.serverTimestamp(),
      });
    if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/main');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User blocked'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _reportUser(BuildContext context, String msgText) async {
    String? reason;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report user'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Why are you reporting this user?',
            style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          ...['Spam', 'Harassment', 'Inappropriate content', 'Fake account', 'Other']
            .map((r) => ListTile(
              dense: true,
              title: Text(r),
              leading: Radio<String>(
                value: r, groupValue: reason,
                activeColor: kGreen,
                onChanged: (v) { reason = v; Navigator.pop(context); }),
            )),
        ])));

    if (reason == null) return;

    // Write report
    await db.collection('reports').add({
      'reporterUid': widget.myUid,
      'reportedUid': widget.otherUid,
      'reason': reason,
      'msgText': msgText,
      'chatId': widget.chatId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Check report count → suspend if >= 10
    final reports = await db.collection('reports')
      .where('reportedUid', isEqualTo: widget.otherUid)
      .get();
    if (reports.docs.length >= 10) {
      await db.collection('users').doc(widget.otherUid)
        .update({'suspended': true});
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted. Thank you.'),
          backgroundColor: Colors.orange));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final text      = widget.data['text'] as String? ?? '';
    final deleted   = widget.data['deleted'] == true;
    final deletedFor = List<String>.from(widget.data['deletedFor'] ?? []);
    final reply     = widget.data['reply'] as Map<String, dynamic>?;
    final ts        = widget.data['timestamp'] as Timestamp?;
    final expiresAt = widget.data['expiresAt'] as Timestamp?;
    final seen      = widget.data['seen'] == true;
    final reactions = Map<String, dynamic>.from(widget.data['reactions'] ?? {});

    if (deletedFor.contains(widget.myUid)) return const SizedBox.shrink();

    final reactionCounts = <String, int>{};
    for (final e in reactions.values) {
      reactionCounts[e as String] = (reactionCounts[e] ?? 0) + 1;
    }

    // Unsent — fully gone (SizedBox.shrink handled by parent via delete())
    // But for safety if unsent flag still exists:
    if (widget.data['unsent'] == true) return const SizedBox.shrink();

    // Current offset including snap animation
    final offset = _snapCtrl.isAnimating ? _snapAnim.value : _dragOffset;
    // Reply arrow icon opacity
    final arrowOpacity = (_dragOffset.abs() / 52).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onDoubleTap: () { if (!deleted) _addReaction('❤️'); },
      onLongPress: () => _showMenu(context, isDark),
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.isFirst ? 8 : 2, bottom: 2,
          left: widget.isMe ? 56 : 0, right: widget.isMe ? 0 : 56),
        child: Align(
          alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: widget.isMe
                ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Reply arrow indicator
                  Positioned(
                    left:  widget.isMe ? null : (arrowOpacity > 0 ? 4 : -30),
                    right: widget.isMe ? (arrowOpacity > 0 ? 4 : -30) : null,
                    top: 0, bottom: 0,
                    child: Opacity(
                      opacity: arrowOpacity,
                      child: Center(
                        child: Icon(
                          widget.isMe
                            ? Icons.reply_rounded
                            : Icons.reply_rounded,
                          color: kGreen.withOpacity(0.8), size: 20)))),

                  // Bubble with slide
                  Transform.translate(
                    offset: Offset(offset, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isMe
                          ? kGreen
                          : (isDark ? kCard2 : Colors.white),
                        borderRadius: BorderRadius.only(
                          topLeft:     const Radius.circular(18),
                          topRight:    const Radius.circular(18),
                          bottomLeft:  Radius.circular(widget.isMe ? 18 : 4),
                          bottomRight: Radius.circular(widget.isMe ? 4 : 18)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 4, offset: const Offset(0, 2))
                        ]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Reply quote
                            if (reply != null) Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: const Border(
                                  left: BorderSide(color: Colors.white54, width: 3))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(reply['sender'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                                  Text(reply['text'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                                ])),

                            // Message text
                            Text(
                              deleted ? (widget.isMe ? 'You deleted this message' : 'This message was deleted') : text,
                              style: TextStyle(
                                color: deleted
                                  ? (widget.isMe ? Colors.white54 : Colors.grey[500])
                                  : (widget.isMe
                                    ? Colors.white
                                    : Theme.of(context).textTheme.bodyLarge?.color),
                                fontSize: 15,
                                fontStyle: deleted ? FontStyle.italic : FontStyle.normal)),
                          ]))),
                  ),

                  // Reaction chips
                  if (reactionCounts.isNotEmpty)
                    Positioned(
                      bottom: -14,
                      right: widget.isMe ? null : 8,
                      left:  widget.isMe ? 8 : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? kCard : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4)]),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: reactionCounts.entries.map((e) =>
                            Text(
                              '${e.key}${e.value > 1 ? e.value.toString() : ''}',
                              style: const TextStyle(fontSize: 12)))
                            .toList()))),
                ],
              ),

              // Timestamp + seen
              if (widget.isLast) ...[
                SizedBox(height: reactionCounts.isNotEmpty ? 16.0 : 4.0),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_fmt(ts),
                    style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                  if (expiresAt != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.timer_outlined,
                        size: 10, color: Colors.grey),
                  ],
                  if (widget.isMe) ...[
                    const SizedBox(width: 3),
                    ts == null
                      ? const Icon(Icons.access_time_rounded,
                          size: 11, color: Colors.grey)
                      : seen
                        ? const Icon(Icons.done_all_rounded,
                            size: 13, color: kGreen)
                        : Icon(Icons.done_all_rounded,
                            size: 13, color: Colors.grey[500]),
                  ],
                ]),
              ] else
                const SizedBox(height: 2),
            ]))));
  }
}
