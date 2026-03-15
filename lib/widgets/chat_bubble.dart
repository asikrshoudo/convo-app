import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import 'markdown_text.dart';
import 'link_preview.dart';

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
    with TickerProviderStateMixin {

  // ── Swipe-to-reply ─────────────────────────────────────────────────────
  double _dragOffset     = 0;
  bool   _replyTriggered = false;
  late final AnimationController _snapCtrl;
  late       Animation<double>   _snapAnim;

  // ── Entrance animation ─────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _entranceFade;
  late final Animation<Offset>   _entranceSlide;

  // ── Single-tap time toggle ─────────────────────────────────────────────
  bool _showTime = false;

  // ── Seen timer (refreshes label every 30s) ─────────────────────────────
  Timer? _seenTimer;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _snapAnim = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    _snapCtrl.addListener(() => setState(() {}));

    // Entrance animation — only plays for new/just-sent messages
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _entranceFade = CurvedAnimation(
        parent: _entranceCtrl, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(
      begin: Offset(widget.isMe ? 0.25 : -0.25, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _entranceCtrl, curve: Curves.easeOutCubic));

    if (_isNewMessage) {
      _entranceCtrl.forward();
    } else {
      _entranceCtrl.value = 1.0; // skip for old messages
    }

    _maybeStartSeenTimer();
  }

  @override
  void didUpdateWidget(ChatBubble old) {
    super.didUpdateWidget(old);
    if (widget.data['seen'] == true && old.data['seen'] != true) {
      _maybeStartSeenTimer();
    }
  }

  void _maybeStartSeenTimer() {
    if (!widget.isMe || widget.data['seen'] != true) return;
    _seenTimer?.cancel();
    _seenTimer = Timer.periodic(const Duration(seconds: 30),
        (_) { if (mounted) setState(() {}); });
  }

  // ── New message check ─────────────────────────────────────────────────
  bool get _isNewMessage {
    final ts = widget.data['timestamp'] as Timestamp?;
    if (ts == null) return true; // just sent, no server ts yet
    return DateTime.now().difference(ts.toDate()).inSeconds < 6;
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    _entranceCtrl.dispose();
    _seenTimer?.cancel();
    super.dispose();
  }

  // ── Drag ──────────────────────────────────────────────────────────────
  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.data['deleted'] == true) return;
    final delta = widget.isMe ? d.delta.dx : -d.delta.dx;
    if (delta > 0) return;
    setState(() {
      _dragOffset = (_dragOffset + d.delta.dx).clamp(
          widget.isMe ? -72.0 : 0.0,
          widget.isMe ? 0.0   : 72.0);
    });
    if (!_replyTriggered && _dragOffset.abs() >= 52) {
      _replyTriggered = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (_replyTriggered && widget.data['deleted'] != true) {
      final t = widget.data['text'] as String? ?? '';
      widget.onReply(widget.msgId, t, widget.data['senderName'] ?? '');
    }
    final from = _dragOffset;
    _snapAnim = Tween<double>(begin: from, end: 0).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    _snapCtrl.forward(from: 0);
    setState(() { _dragOffset = 0; _replyTriggered = false; });
  }

  // ── Formatters ────────────────────────────────────────────────────────
  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d    = ts.toDate().toLocal();
    final h    = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final m    = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _seenLabel(Timestamp? seenAt) {
    if (seenAt == null) return 'Seen now';
    final diff = DateTime.now().difference(seenAt.toDate());
    if (diff.inSeconds < 60) return 'Seen now';
    if (diff.inMinutes < 60) return 'Seen ${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return 'Seen ${diff.inHours}h ago';
    if (diff.inDays    < 7)  return 'Seen ${diff.inDays}d ago';
    return 'Seen ${(diff.inDays / 7).floor()}w ago';
  }

  // ── Context menu ──────────────────────────────────────────────────────
  void _showMenu(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final text   = widget.data['text'] as String? ?? '';
    if (widget.data['deleted'] == true) return;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetRadius))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(
            color: isDark ? kTextTertiary : kLightTextSub,
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),

        // Emoji reactions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['❤️', '😂', '😮', '😢', '👍', '👎'].map((emoji) =>
              GestureDetector(
                onTap: () { Navigator.pop(ctx); _addReaction(emoji); },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? kCard2 : kLightCard2,
                    shape: BoxShape.circle),
                  child: Text(emoji,
                    style: const TextStyle(fontSize: 22))))).toList())),

        Divider(height: 1, color: isDark ? kDivider : kLightDivider),

        ListTile(
          leading: const Icon(Icons.reply_rounded, color: kAccent),
          title: const Text('Reply'),
          onTap: () {
            Navigator.pop(ctx);
            widget.onReply(
                widget.msgId, text, widget.data['senderName'] ?? '');
          }),
        ListTile(
          leading: Icon(Icons.copy_rounded,
              color: isDark ? kTextSecondary : kLightTextSub),
          title: const Text('Copy'),
          onTap: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: text));
          }),

        if (widget.isMe) ...[
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: kAccent),
            title: const Text('Edit'),
            onTap: () {
              Navigator.pop(ctx);
              _editMessage(ctx, text);
            }),
          ListTile(
            leading: const Icon(
                Icons.delete_outline_rounded, color: kOrange),
            title: const Text('Delete for me',
                style: TextStyle(color: kOrange)),
            onTap: () {
              Navigator.pop(ctx);
              db.collection('chats').doc(widget.chatId)
                  .collection('messages').doc(widget.msgId)
                  .update({
                'deletedFor': FieldValue.arrayUnion([widget.myUid])
              });
            }),
          ListTile(
            leading: const Icon(Icons.undo_rounded, color: kRed),
            title: const Text('Unsend',
                style: TextStyle(color: kRed)),
            subtitle: Text('Remove for everyone',
                style: TextStyle(fontSize: 11,
                    color: isDark ? kTextSecondary : kLightTextSub)),
            onTap: () {
              Navigator.pop(ctx);
              db.collection('chats').doc(widget.chatId)
                  .collection('messages').doc(widget.msgId).delete();
            }),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded,
                color: kOrange),
            title: const Text('Delete for me',
                style: TextStyle(color: kOrange)),
            onTap: () {
              Navigator.pop(ctx);
              db.collection('chats').doc(widget.chatId)
                  .collection('messages').doc(widget.msgId)
                  .update({
                'deletedFor': FieldValue.arrayUnion([widget.myUid])
              });
            }),
          if (widget.otherUid != null) ...[
            Divider(height: 1,
                color: isDark ? kDivider : kLightDivider),
            ListTile(
              leading: Icon(Icons.volume_off_rounded,
                  color: isDark ? kTextSecondary : kLightTextSub),
              title: const Text('Mute notifications'),
              onTap: () { Navigator.pop(ctx); _muteUser(ctx); }),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: kRed),
              title: const Text('Block user',
                  style: TextStyle(color: kRed)),
              onTap: () { Navigator.pop(ctx); _blockUser(ctx); }),
            ListTile(
              leading: const Icon(Icons.flag_rounded, color: kOrange),
              title: const Text('Report',
                  style: TextStyle(color: kOrange)),
              onTap: () { Navigator.pop(ctx); _reportUser(ctx, text); }),
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

  // ── Edit message ─────────────────────────────────────────────────────────
  void _editMessage(BuildContext ctx, String currentText) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final ctrl   = TextEditingController(text: currentText);
    ctrl.selection = TextSelection(
      baseOffset:   0,
      extentOffset: currentText.length);

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetRadius))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(
              color: isDark ? kTextTertiary : kLightTextSub,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Container(
              decoration: BoxDecoration(
                color: isDark ? kCard2 : kLightCard2,
                borderRadius: BorderRadius.circular(14)),
              child: TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  color: isDark ? kTextPrimary : kLightText,
                  fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Edit message...',
                  hintStyle: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10))))),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                final newText = ctrl.text.trim();
                if (newText.isEmpty || newText == currentText) {
                  Navigator.pop(sheetCtx);
                  return;
                }
                Navigator.pop(sheetCtx);
                db.collection('chats').doc(widget.chatId)
                    .collection('messages').doc(widget.msgId)
                    .update({'text': newText});
              },
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                  color: kAccent, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 20))),
          ]),
        ])));
    ctrl.dispose;
  }

  Future<void> _muteUser(BuildContext ctx) async {
    await db.collection('users').doc(widget.myUid)
        .collection('muted').doc(widget.otherUid)
        .set({'mutedAt': FieldValue.serverTimestamp()});
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('Notifications muted'),
          backgroundColor: kCard2));
  }

  Future<void> _blockUser(BuildContext ctx) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Block user?'),
        content: const Text("They won't be able to message you."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block',
                  style: TextStyle(color: kRed))),
        ]));
    if (confirm != true) return;
    await db.collection('users').doc(widget.myUid)
        .collection('blocked').doc(widget.otherUid)
        .set({'blockedAt': FieldValue.serverTimestamp()});
    if (ctx.mounted) {
      Navigator.of(ctx)
          .popUntil((r) => r.isFirst || r.settings.name == '/main');
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('User blocked'),
            backgroundColor: kRed));
    }
  }

  Future<void> _reportUser(BuildContext ctx, String msgText) async {
    String? reason;
    await showDialog(
      context: ctx,
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
              onChanged: (v) { reason = v; Navigator.pop(ctx); }),
          )),
        ])));
    if (reason == null) return;
    await db.collection('reports').add({
      'reporterUid': widget.myUid, 'reportedUid': widget.otherUid,
      'reason': reason, 'msgText': msgText,
      'chatId': widget.chatId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final reports = await db.collection('reports')
        .where('reportedUid', isEqualTo: widget.otherUid).get();
    if (reports.docs.length >= 10) {
      await db.collection('users').doc(widget.otherUid)
          .update({'suspended': true});
    }
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('Report submitted. Thank you.'),
          backgroundColor: kOrange));
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final text       = widget.data['text']      as String? ?? '';
    final deleted    = widget.data['deleted']   == true;
    final deletedFor = List<String>.from(widget.data['deletedFor'] ?? []);
    final reply      = widget.data['reply']     as Map<String, dynamic>?;
    final ts         = widget.data['timestamp'] as Timestamp?;
    final expiresAt  = widget.data['expiresAt'] as Timestamp?;
    final seen       = widget.data['seen']      == true;
    final seenAt     = widget.data['seenAt']    as Timestamp?;
    final reactions  = Map<String, dynamic>.from(
        widget.data['reactions'] ?? {});

    if (deletedFor.contains(widget.myUid)) return const SizedBox.shrink();
    if (widget.data['unsent'] == true)      return const SizedBox.shrink();

    // Detect link in the message text
    final linkUrl = deleted ? null : extractFirstUrl(text);

    final reactionCounts = <String, int>{};
    for (final e in reactions.values) {
      reactionCounts[e as String] = (reactionCounts[e] ?? 0) + 1;
    }

    final offset       = _snapCtrl.isAnimating ? _snapAnim.value : _dragOffset;
    final arrowOpacity = (_dragOffset.abs() / 52).clamp(0.0, 1.0);

    final radius = BorderRadius.only(
      topLeft:    const Radius.circular(kBubbleRadius),
      topRight:   const Radius.circular(kBubbleRadius),
      bottomLeft: Radius.circular(
          widget.isMe ? kBubbleRadius : (widget.isLast ? 4 : kBubbleRadius)),
      bottomRight: Radius.circular(
          widget.isMe ? (widget.isLast ? 4 : kBubbleRadius) : kBubbleRadius),
    );

    final bubbleColor = widget.isMe
        ? kBubbleMe : (isDark ? kBubbleOther : kLightCard);
    final textColor = widget.isMe
        ? Colors.white : (isDark ? kTextPrimary : kLightText);
    final subtleColor = isDark ? kTextSecondary : kLightTextSub;

    return FadeTransition(
      opacity: _entranceFade,
      child: SlideTransition(
        position: _entranceSlide,
        child: GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd:    _onDragEnd,
      onTap: () { if (ts != null) setState(() => _showTime = !_showTime); },
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

              Stack(clipBehavior: Clip.none, children: [

                // Swipe arrow
                Positioned(
                  left:  widget.isMe ? null : (arrowOpacity > 0 ? 0 : -36),
                  right: widget.isMe ? (arrowOpacity > 0 ? 0 : -36) : null,
                  top: 0, bottom: 0,
                  child: Opacity(
                    opacity: arrowOpacity,
                    child: Center(child: Container(
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
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.14),
                        blurRadius: 6,
                        offset: const Offset(0, 2))]),
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
                              padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(
                                    widget.isMe ? 0.18 : 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border(left: BorderSide(
                                  color: widget.isMe
                                      ? Colors.white54 : kAccent,
                                  width: 3))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(reply['sender'] ?? '',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: widget.isMe
                                          ? Colors.white70 : kAccent,
                                      letterSpacing: 0.1)),
                                  const SizedBox(height: 2),
                                  Text(reply['text'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: widget.isMe
                                          ? Colors.white54 : subtleColor)),
                                ])),

                          // ── Message text ──────────────────────────
                          if (deleted)
                            Text(
                              widget.isMe
                                  ? 'You deleted this message'
                                  : 'This message was deleted',
                              style: TextStyle(
                                color: textColor.withOpacity(0.45),
                                fontSize: 15, height: 1.35,
                                fontStyle: FontStyle.italic))
                          else if (MarkdownText.hasMarkdown(text))
                            MarkdownText(
                              text: text,
                              textColor: textColor,
                              isMe: widget.isMe)
                          else
                            Text(text,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15, height: 1.35,
                                letterSpacing: -0.1)),

                          // ── Link Preview ──────────────────────────
                          if (linkUrl != null)
                            LinkPreviewCard(
                              url:  linkUrl,
                              isMe: widget.isMe),
                        ])))),

                // Reaction chips
                if (reactionCounts.isNotEmpty)
                  Positioned(
                    bottom: -13,
                    right: widget.isMe ? null : 6,
                    left:  widget.isMe ? 6   : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? kCard2 : kLightCard2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: isDark ? kDivider : kLightDivider,
                            width: 0.5),
                        boxShadow: kElevation1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: reactionCounts.entries.map((e) =>
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Text(
                              '${e.key}${e.value > 1 ? ' ${e.value}' : ''}',
                              style: const TextStyle(
                                  fontSize: 12)))).toList()))),
              ]),

              // ── isLast: tick + seen ────────────────────────────────
              if (widget.isLast) ...[
                SizedBox(height: reactionCounts.isNotEmpty ? 18.0 : 5.0),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (expiresAt != null) ...[
                    Icon(Icons.timer_outlined, size: 10, color: subtleColor),
                    const SizedBox(width: 3),
                  ],
                  Text(_fmt(ts),
                    style: TextStyle(color: subtleColor,
                        fontSize: 10, letterSpacing: 0.2)),
                  if (widget.isMe) ...[
                    const SizedBox(width: 4),
                    ts == null
                      ? Icon(Icons.access_time_rounded,
                            size: 11, color: subtleColor)
                      : seen
                        ? const Icon(Icons.done_all_rounded,
                              size: 13, color: kAccent)
                        : Icon(Icons.done_all_rounded,
                              size: 13, color: subtleColor),
                  ],
                ]),
                if (widget.isMe && seen) ...[
                  const SizedBox(height: 3),
                  Text(_seenLabel(seenAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: kAccent.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2)),
                ],
              ] else
                const SizedBox(height: 1),

              // ── Tap-to-reveal time ─────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _showTime
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Text(_fmt(ts),
                        style: TextStyle(
                          fontSize: 11, color: subtleColor,
                          letterSpacing: 0.1)))
                  : const SizedBox.shrink()),

            ]))));
      }));
  }
}
