import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

// ── Markdown parser ───────────────────────────────────────────────────────────
// Supports: **bold**, *italic*, ~~strike~~, `inline code`, ```code block```

bool _hasMarkdown(String text) =>
  text.contains('**') || text.contains('*') || text.contains('~~') ||
  text.contains('`')  || text.contains('__') || text.contains('_');

// Returns a list of segments: each is either plain text or a styled token
List<InlineSpan> _parseMarkdown(
  String text, {
  required Color baseColor,
  required bool isMe,
  required BuildContext context,
  required bool isDark,
}) {
  // Code blocks handled separately as widgets
  if (text.contains('```')) {
    final parts = text.split('```');
    final spans = <InlineSpan>[];
    for (int i = 0; i < parts.length; i++) {
      if (i.isOdd && parts[i].isNotEmpty) {
        final code = parts[i].trim();
        spans.add(WidgetSpan(
          child: _CodeBlock(code: code, isMe: isMe, isDark: isDark)));
      } else if (parts[i].isNotEmpty) {
        spans.addAll(_parseInline(
          parts[i], baseColor: baseColor, isMe: isMe, isDark: isDark));
      }
    }
    return spans;
  }
  return _parseInline(text, baseColor: baseColor, isMe: isMe, isDark: isDark);
}

List<InlineSpan> _parseInline(
  String text, {
  required Color baseColor,
  required bool isMe,
  required bool isDark,
}) {
  final pattern = RegExp(
    r'\*\*(.+?)\*\*|__(.+?)__|'   // bold
    r'\*(.+?)\*|_(.+?)_|'         // italic
    r'~~(.+?)~~|'                  // strikethrough
    r'`(.+?)`',                    // inline code
    dotAll: true,
  );

  final spans = <InlineSpan>[];
  int last = 0;

  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(
        text: text.substring(last, m.start),
        style: TextStyle(color: baseColor)));
    }

    final bold   = m.group(1) ?? m.group(2);
    final italic = m.group(3) ?? m.group(4);
    final strike = m.group(5);
    final code   = m.group(6);

    if (bold != null) {
      spans.add(TextSpan(
        text: bold,
        style: TextStyle(color: baseColor, fontWeight: FontWeight.bold)));
    } else if (italic != null) {
      spans.add(TextSpan(
        text: italic,
        style: TextStyle(color: baseColor, fontStyle: FontStyle.italic)));
    } else if (strike != null) {
      spans.add(TextSpan(
        text: strike,
        style: TextStyle(
          color: baseColor.withOpacity(0.55),
          decoration: TextDecoration.lineThrough,
          decorationColor: baseColor.withOpacity(0.55))));
    } else if (code != null) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(isMe ? 0.22 : 0.07),
            borderRadius: BorderRadius.circular(5)),
          child: Text(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: isMe
                ? Colors.white.withOpacity(0.9)
                : isDark ? const Color(0xFFE06C75) : const Color(0xFFD6546B))))));
    }
    last = m.end;
  }

  if (last < text.length) {
    spans.add(TextSpan(
      text: text.substring(last),
      style: TextStyle(color: baseColor)));
  }

  return spans.isEmpty
    ? [TextSpan(text: text, style: TextStyle(color: baseColor))]
    : spans;
}

// ── Code block widget with copy button ───────────────────────────────────────
class _CodeBlock extends StatefulWidget {
  final String code;
  final bool isMe, isDark;
  const _CodeBlock({
    required this.code,
    required this.isMe,
    required this.isDark});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2),
      () { if (mounted) setState(() => _copied = false); });
  }

  @override
  Widget build(BuildContext context) {
    final bg = Colors.black.withOpacity(widget.isMe ? 0.25 : 0.07);
    final textColor = widget.isMe
      ? Colors.white.withOpacity(0.88)
      : widget.isDark ? kTextPrimary : kLightText;
    final subtleColor = widget.isMe
      ? Colors.white.withOpacity(0.5)
      : widget.isDark ? kTextSecondary : kLightTextSub;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (widget.isMe ? Colors.white : kAccent).withOpacity(0.15),
          width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar with copy button ──────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: (widget.isMe ? Colors.white : kAccent)
                    .withOpacity(0.12),
                  width: 0.5))),
            child: Row(children: [
              Row(children: [
                _dot(const Color(0xFFFF5F57)),
                const SizedBox(width: 5),
                _dot(const Color(0xFFFFBD2E)),
                const SizedBox(width: 5),
                _dot(const Color(0xFF28C840)),
              ]),
              const Spacer(),
              GestureDetector(
                onTap: _copy,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _copied
                    ? Row(key: const ValueKey('done'), children: [
                        Icon(Icons.check_rounded,
                          size: 12, color: subtleColor),
                        const SizedBox(width: 4),
                        Text('Copied',
                          style: TextStyle(
                            fontSize: 11, color: subtleColor,
                            fontWeight: FontWeight.w500)),
                      ])
                    : Row(key: const ValueKey('copy'), children: [
                        Icon(Icons.copy_rounded,
                          size: 12, color: subtleColor),
                        const SizedBox(width: 4),
                        Text('Copy',
                          style: TextStyle(
                            fontSize: 11, color: subtleColor,
                            fontWeight: FontWeight.w500)),
                      ])),
              ),
            ])),

          // ── Code content ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Text(
              widget.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: textColor,
                height: 1.5))),
        ]));
  }

  Widget _dot(Color c) => Container(
    width: 9, height: 9,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ── ChatBubble ────────────────────────────────────────────────────────────────
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
  double _dragOffset    = 0;
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
  void dispose() { _snapCtrl.dispose(); super.dispose(); }

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
      final text = widget.data['text'] as String? ?? '';
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
    final d = ts.toDate().toLocal();
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

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
            widget.onReply(widget.msgId, text, widget.data['senderName'] ?? '');
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
            leading: const Icon(Icons.delete_outline_rounded, color: kOrange),
            title: const Text('Delete for me',
              style: TextStyle(color: kOrange)),
            onTap: () {
              Navigator.pop(ctx);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .update({'deletedFor': FieldValue.arrayUnion([widget.myUid])});
            }),
          ListTile(
            leading: const Icon(Icons.undo_rounded, color: kRed),
            title: const Text('Unsend', style: TextStyle(color: kRed)),
            subtitle: Text('Remove for everyone',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? kTextSecondary : kLightTextSub)),
            onTap: () {
              Navigator.pop(ctx);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId).delete();
            }),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: kOrange),
            title: const Text('Delete for me',
              style: TextStyle(color: kOrange)),
            onTap: () {
              Navigator.pop(ctx);
              db.collection('chats').doc(widget.chatId)
                .collection('messages').doc(widget.msgId)
                .update({'deletedFor': FieldValue.arrayUnion([widget.myUid])});
            }),
          if (widget.otherUid != null) ...[
            Divider(height: 1, color: isDark ? kDivider : kLightDivider),
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
        content: const Text('They won\'t be able to message you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block', style: TextStyle(color: kRed))),
        ]));
    if (confirm != true) return;
    await db.collection('users').doc(widget.myUid)
      .collection('blocked').doc(widget.otherUid)
      .set({'blockedAt': FieldValue.serverTimestamp()});
    if (ctx.mounted) {
      Navigator.of(ctx).popUntil(
          (r) => r.isFirst || r.settings.name == '/main');
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('User blocked'), backgroundColor: kRed));
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
               'Fake account', 'Other'].map((r) => ListTile(
            dense: true, title: Text(r),
            leading: Radio<String>(
              value: r, groupValue: reason, activeColor: kAccent,
              onChanged: (v) { reason = v; Navigator.pop(ctx); }),
          )),
        ])));
    if (reason == null) return;
    await db.collection('reports').add({
      'reporterUid': widget.myUid,
      'reportedUid': widget.otherUid,
      'reason':      reason,
      'msgText':     msgText,
      'chatId':      widget.chatId,
      'createdAt':   FieldValue.serverTimestamp(),
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
    final reactions  = Map<String, dynamic>.from(widget.data['reactions'] ?? {});

    if (deletedFor.contains(widget.myUid)) return const SizedBox.shrink();
    if (widget.data['unsent'] == true)     return const SizedBox.shrink();

    final reactionCounts = <String, int>{};
    for (final e in reactions.values) {
      reactionCounts[e as String] = (reactionCounts[e] ?? 0) + 1;
    }

    final offset       = _snapCtrl.isAnimating ? _snapAnim.value : _dragOffset;
    final arrowOpacity = (_dragOffset.abs() / 52).clamp(0.0, 1.0);

    final radius = BorderRadius.only(
      topLeft:     const Radius.circular(kBubbleRadius),
      topRight:    const Radius.circular(kBubbleRadius),
      bottomLeft:  Radius.circular(
          widget.isMe ? kBubbleRadius : (widget.isLast ? 4 : kBubbleRadius)),
      bottomRight: Radius.circular(
          widget.isMe ? (widget.isLast ? 4 : kBubbleRadius) : kBubbleRadius),
    );

    final bubbleColor = widget.isMe
      ? kBubbleMe : (isDark ? kBubbleOther : kLightCard);
    final textColor = widget.isMe
      ? Colors.white : (isDark ? kTextPrimary : kLightText);
    final subtleColor = isDark ? kTextSecondary : kLightTextSub;

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
              Stack(clipBehavior: Clip.none, children: [

                // Swipe-to-reply arrow
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

                // Bubble
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
                                      fontSize: 11, fontWeight: FontWeight.w700,
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

                          // Message text (with markdown or plain)
                          if (deleted)
                            Text(
                              widget.isMe
                                ? 'You deleted this message'
                                : 'This message was deleted',
                              style: TextStyle(
                                color: textColor.withOpacity(0.45),
                                fontSize: 15, height: 1.35,
                                fontStyle: FontStyle.italic))
                          else if (_hasMarkdown(text))
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 15, height: 1.35,
                                  letterSpacing: -0.1),
                                children: _parseMarkdown(
                                  text,
                                  baseColor: textColor,
                                  isMe: widget.isMe,
                                  context: context,
                                  isDark: isDark)))
                          else
                            Text(text,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15, height: 1.35,
                                letterSpacing: -0.1)),
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
                              style: const TextStyle(fontSize: 12))))
                          .toList()))),
              ]),

              // ── Timestamp + tick + Seen ────────────────────────────
              if (widget.isLast) ...[
                SizedBox(height: reactionCounts.isNotEmpty ? 18.0 : 5.0),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (expiresAt != null) ...[
                    Icon(Icons.timer_outlined,
                      size: 10, color: subtleColor),
                    const SizedBox(width: 3),
                  ],
                  Text(_fmt(ts),
                    style: TextStyle(
                      color: subtleColor, fontSize: 10,
                      letterSpacing: 0.2)),
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

                // ── "Seen" label — only on my last seen message ────
                if (widget.isMe && seen) ...[
                  const SizedBox(height: 3),
                  Text('Seen',
                    style: TextStyle(
                      fontSize: 11,
                      color: kAccent.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2)),
                ],
              ] else
                const SizedBox(height: 1),
            ]))));
  }
}
