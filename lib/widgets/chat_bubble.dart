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
  late       Animation<double>   _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
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
    if (widget.data['deleted'] == true) return;
    final delta = widget.isMe ? d.delta.dx : -d.delta.dx;
    if (delta > 0) return;
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
      if (widget.data['deleted'] != true) {
        widget.onReply(widget.msgId, text, widget.data['senderName'] ?? '');
      }
    }
    final from = _dragOffset;
    _snapAnim = Tween<double>(begin: from, end: 0).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    _snapCtrl.forward(from: 0);
    setState(() { _dragOffset = 0; _replyTriggered = false; });
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _showMenu(BuildContext context) {
    final text    = widget.data['text'] as String? ?? '';
    final deleted = widget.data['deleted'] == true;
    if (deleted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(
              color: kTextTertiary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),

        // Emoji reactions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['❤️', '😂', '😮', '😢', '👍', '👎'].map((emoji) =>
              GestureDetector(
                onTap: () { Navigator.pop(context); _addReaction(emoji); },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kCard2, shape: BoxShape.circle),
                  child: Text(emoji,
                    style: const TextStyle(fontSize: 22))))).toList())),

        const Divider(height: 1, color: kDivider),

        ListTile(
          leading: const Icon(Icons.reply_rounded, color: kAccent),
          title: const Text('Reply'),
          onTap: () {
            Navigator.pop(context);
            widget.onReply(widget.msgId, text, widget.data['senderName'] ?? '');
          }),
        ListTile(
          leading: const Icon(Icons.copy_rounded, color: kTextSecondary),
          title: const Text('Copy'),
          onTap: () {
            Navigator.pop(context);
            Clipboard.setData(ClipboardData(text: text));
          }),

        if (widget.isMe) ...[
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: kOrange),
            title: const Text('Delete for me',
                style: TextStyle(color: kOrange)),
            onTap: () {
              Navigator.pop(context);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .update({'deletedFor': FieldValue.arrayUnion([widget.myUid])});
            }),
          ListTile(
            leading: const Icon(Icons.undo_rounded, color: kRed),
            title: const Text('Unsend', style: TextStyle(color: kRed)),
            subtitle: const Text('Remove for everyone',
                style: TextStyle(fontSize: 11, color: kTextSecondary)),
            onTap: () {
              Navigator.pop(context);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .delete();
            }),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: kOrange),
            title: const Text('Delete for me',
                style: TextStyle(color: kOrange)),
            onTap: () {
              Navigator.pop(context);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .update({'deletedFor': FieldValue.arrayUnion([widget.myUid])});
            }),
          if (widget.otherUid != null) ...[
            const Divider(height: 1, color: kDivider),
            ListTile(
              leading: const Icon(Icons.volume_off_rounded,
                  color: kTextSecondary),
              title: const Text('Mute notifications'),
              onTap: () { Navigator.pop(context); _muteUser(context); }),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: kRed),
              title: const Text('Block user',
                  style: TextStyle(color: kRed)),
              onTap: () { Navigator.pop(context); _blockUser(context); }),
            ListTile(
              leading: const Icon(Icons.flag_rounded, color: kOrange),
              title: const Text('Report',
                  style: TextStyle(color: kOrange)),
              onTap: () { Navigator.pop(context); _reportUser(context, text); }),
          ],
        ],
        const SizedBox(height: 16),
      ]));
  }

  Future<void> _addReaction(String emoji) async {
    final reactions = Map<String, dynamic>.from(
        widget.data['reactions'] ?? {});
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
          backgroundColor: kCard2));
    }
  }

  Future<void> _blockUser(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Block user?'),
        content: const Text(
            'They won\'t be able to message you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block',
                style: TextStyle(color: kRed))),
        ]));
    if (confirm != true) return;
    await db.collection('users').doc(widget.myUid)
      .collection('blocked').doc(widget.otherUid).set({
        'blockedAt': FieldValue.serverTimestamp(),
      });
    if (context.mounted) {
      Navigator.of(context).popUntil(
          (r) => r.isFirst || r.settings.name == '/main');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User blocked'),
          backgroundColor: kRed));
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
            style: TextStyle(fontSize: 13, color: kTextSecondary)),
          const SizedBox(height: 12),
          ...['Spam', 'Harassment', 'Inappropriate content',
               'Fake account', 'Other']
            .map((r) => ListTile(
              dense: true,
              title: Text(r),
              leading: Radio<String>(
                value: r, groupValue: reason,
                activeColor: kAccent,
                onChanged: (v) {
                  reason = v;
                  Navigator.pop(context);
                }),
            )),
        ])));

    if (reason == null) return;

    await db.collection('reports').add({
      'reporterUid': widget.myUid,
      'reportedUid': widget.otherUid,
      'reason': reason,
      'msgText': msgText,
      'chatId': widget.chatId,
      'createdAt': FieldValue.serverTimestamp(),
    });

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
          backgroundColor: kOrange));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text       = widget.data['text'] as String? ?? '';
    final deleted    = widget.data['deleted'] == true;
    final deletedFor = List<String>.from(widget.data['deletedFor'] ?? []);
    final reply      = widget.data['reply'] as Map<String, dynamic>?;
    final ts         = widget.data['timestamp'] as Timestamp?;
    final expiresAt  = widget.data['expiresAt'] as Timestamp?;
    final seen       = widget.data['seen'] == true;
    final reactions  = Map<String, dynamic>.from(
        widget.data['reactions'] ?? {});

    if (deletedFor.contains(widget.myUid)) return const SizedBox.shrink();
    if (widget.data['unsent'] == true) return const SizedBox.shrink();

    final reactionCounts = <String, int>{};
    for (final e in reactions.values) {
      reactionCounts[e as String] = (reactionCounts[e] ?? 0) + 1;
    }

    final offset       = _snapCtrl.isAnimating ? _snapAnim.value : _dragOffset;
    final arrowOpacity = (_dragOffset.abs() / 52).clamp(0.0, 1.0);

    // iMessage tail: only last bubble in a group gets the pointy corner
    final radius = BorderRadius.only(
      topLeft:     const Radius.circular(kBubbleRadius),
      topRight:    const Radius.circular(kBubbleRadius),
      bottomLeft:  Radius.circular(
          widget.isMe ? kBubbleRadius : (widget.isLast ? 4 : kBubbleRadius)),
      bottomRight: Radius.circular(
          widget.isMe ? (widget.isLast ? 4 : kBubbleRadius) : kBubbleRadius),
    );

    final bubbleColor = widget.isMe ? kBubbleMe : kBubbleOther;
    final textColor   = widget.isMe ? Colors.white : kTextPrimary;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd:    _onDragEnd,
      onDoubleTap: () { if (!deleted) _addReaction('❤️'); },
      onLongPress: () => _showMenu(context),
      child: Padding(
        padding: EdgeInsets.only(
          top:    widget.isFirst ? 10 : 1,
          bottom: 1,
          left:   widget.isMe ? 64 : 8,
          right:  widget.isMe ? 8  : 64,
        ),
        child: Align(
          alignment: widget.isMe
              ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: widget.isMe
                ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Swipe-to-reply arrow badge ──────────────────────
                  Positioned(
                    left:  widget.isMe ? null : (arrowOpacity > 0 ? 0 : -36),
                    right: widget.isMe ? (arrowOpacity > 0 ? 0 : -36) : null,
                    top: 0, bottom: 0,
                    child: Opacity(
                      opacity: arrowOpacity,
                      child: Center(
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: kAccent.withOpacity(0.15),
                            shape: BoxShape.circle),
                          child: const Icon(Icons.reply_rounded,
                              color: kAccent, size: 16))))),

                  // ── Bubble ─────────────────────────────────────────
                  Transform.translate(
                    offset: Offset(offset, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: radius,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.14),
                            blurRadius: 6,
                            offset: const Offset(0, 2)),
                        ]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            // Reply quote
                            if (reply != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.fromLTRB(
                                    10, 7, 10, 7),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(
                                      widget.isMe ? 0.18 : 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border(
                                    left: BorderSide(
                                      color: widget.isMe
                                          ? Colors.white54
                                          : kAccent,
                                      width: 3))),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reply['sender'] ?? '',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: widget.isMe
                                            ? Colors.white70
                                            : kAccent,
                                        letterSpacing: 0.1)),
                                    const SizedBox(height: 2),
                                    Text(
                                      reply['text'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: widget.isMe
                                            ? Colors.white54
                                            : kTextSecondary)),
                                  ])),

                            // Message text
                            Text(
                              deleted
                                ? (widget.isMe
                                    ? 'You deleted this message'
                                    : 'This message was deleted')
                                : text,
                              style: TextStyle(
                                color: deleted
                                  ? textColor.withOpacity(0.45)
                                  : textColor,
                                fontSize: 15,
                                height: 1.35,
                                letterSpacing: -0.1,
                                fontStyle: deleted
                                    ? FontStyle.italic
                                    : FontStyle.normal)),
                          ])))),

                  // Reaction chips
                  if (reactionCounts.isNotEmpty)
                    Positioned(
                      bottom: -13,
                      right: widget.isMe ? null : 6,
                      left:  widget.isMe ? 6 : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: kCard2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: kDivider, width: 0.5),
                          boxShadow: kElevation1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: reactionCounts.entries.map((e) =>
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Text(
                                '${e.key}${e.value > 1 ? ' ${e.value}' : ''}',
                                style: const TextStyle(
                                    fontSize: 12))))
                            .toList()))),
                ],
              ),

              // Timestamp + seen tick
              if (widget.isLast) ...[
                SizedBox(height: reactionCounts.isNotEmpty ? 18.0 : 5.0),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (expiresAt != null) ...[
                    const Icon(Icons.timer_outlined,
                        size: 10, color: kTextSecondary),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    _fmt(ts),
                    style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 10,
                        letterSpacing: 0.2)),
                  if (widget.isMe) ...[
                    const SizedBox(width: 4),
                    ts == null
                      ? const Icon(Icons.access_time_rounded,
                          size: 11, color: kTextSecondary)
                      : seen
                        ? const Icon(Icons.done_all_rounded,
                            size: 13, color: kAccent)
                        : const Icon(Icons.done_all_rounded,
                            size: 13, color: kTextSecondary),
                  ],
                ]),
              ] else
                const SizedBox(height: 1),
            ]))));
  }
}
