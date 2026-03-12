import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../widgets/typing_dots.dart';
import '../../widgets/markdown_text.dart';
import '../../widgets/link_preview.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId, groupName;
  const GroupChatScreen({super.key, required this.groupId, required this.groupName});
  @override State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _replyToId, _replyToText, _replyToSender;
  late String _myUid, _myName;
  Timer? _typingTimer;

  static const _notifyUrl = 'https://convo-notify.onrender.com/notify/group';

  @override
  void initState() {
    super.initState();
    _myUid  = auth.currentUser!.uid;
    _myName = auth.currentUser?.displayName ?? 'User';
    _clearUnread();
    _msgCtrl.addListener(_onTyping);
  }

  @override
  void dispose() {
    _setTyping(false);
    _msgCtrl.removeListener(_onTyping);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  Future<void> _clearUnread() async =>
    db.collection('groups').doc(widget.groupId)
      .set({'unread_$_myUid': 0}, SetOptions(merge: true));

  void _onTyping() {
    _typingTimer?.cancel();
    _setTyping(true);
    _typingTimer = Timer(const Duration(seconds: 3), () => _setTyping(false));
  }

  Future<void> _setTyping(bool v) async =>
    db.collection('groups').doc(widget.groupId)
      .collection('typing').doc(_myUid)
      .set({'isTyping': v, 'name': _myName, 'ts': FieldValue.serverTimestamp()});

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _msgCtrl.clear();
    _setTyping(false);

    final reply = _replyToId != null
      ? {'id': _replyToId, 'text': _replyToText, 'sender': _replyToSender}
      : null;
    setState(() {
      _replyToId = null; _replyToText = null; _replyToSender = null;
    });

    final groupDoc = await db.collection('groups').doc(widget.groupId).get();
    final members  = List<String>.from(groupDoc.data()?['members'] ?? []);
    final unreadUpdates = <String, dynamic>{};
    for (final uid in members) {
      if (uid != _myUid) unreadUpdates['unread_$uid'] = FieldValue.increment(1);
    }

    await db.collection('groups').doc(widget.groupId)
      .collection('messages').add({
        'text': t, 'senderId': _myUid, 'senderName': _myName,
        'timestamp': FieldValue.serverTimestamp(),
        'deleted': false, 'seen': false,
        if (reply != null) 'reply': reply,
      });

    await db.collection('groups').doc(widget.groupId).set({
      'lastMessage': t,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastSenderName': _myName,
      'unread_$_myUid': 0,
      ...unreadUpdates,
    }, SetOptions(merge: true));

    try {
      await http.post(
        Uri.parse(_notifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'groupId': widget.groupId,
          'senderId': _myUid,
          'senderName': _myName,
          'text': t,
        }),
      );
    } catch (_) {}

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _showMsgMenu(BuildContext ctx, String msgId, String text, String senderName, {bool isSender = false}) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
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
                onTap: () { Navigator.pop(ctx); _addReaction(msgId, emoji); },
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
            setState(() {
              _replyToId     = msgId;
              _replyToText   = text;
              _replyToSender = senderName;
            });
          }),
        ListTile(
          leading: Icon(Icons.copy_rounded,
            color: isDark ? kTextSecondary : kLightTextSub),
          title: const Text('Copy'),
          onTap: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: text));
          }),
        if (isSender)
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: kAccent),
            title: const Text('Edit'),
            onTap: () {
              Navigator.pop(ctx);
              _editGroupMessage(ctx, msgId, text);
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
            db.collection('groups').doc(widget.groupId)
              .collection('messages').doc(msgId)
              .update({'deleted': true, 'text': '', 'unsent': true});
          }),
        const SizedBox(height: 16),
      ]));
  }

  Future<void> _addReaction(String msgId, String emoji) async {
    final doc = await db.collection('groups').doc(widget.groupId)
      .collection('messages').doc(msgId).get();
    final reactions = Map<String, dynamic>.from(
      doc.data()?['reactions'] ?? {});
    if (reactions[_myUid] == emoji) {
      reactions.remove(_myUid);
    } else {
      reactions[_myUid] = emoji;
    }
    await db.collection('groups').doc(widget.groupId)
      .collection('messages').doc(msgId)
      .update({'reactions': reactions});
  }

  // ── Edit message ──────────────────────────────────────────────────────────
  void _editGroupMessage(BuildContext ctx, String msgId, String currentText) {
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
                db.collection('groups').doc(widget.groupId)
                    .collection('messages').doc(msgId)
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
  }

  // ── Time helpers ──────────────────────────────────────────────────────────
  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate().toLocal();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // Show time divider when gap between consecutive messages >= 1 minute
  bool _shouldShowTimeDivider(Timestamp? prev, Timestamp? curr) {
    if (prev == null || curr == null) return false;
    final diff = curr.toDate().difference(prev.toDate()).inSeconds;
    return diff >= 60;
  }

  Widget _timeDivider(String time) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Expanded(child: Container(
        height: 0.5,
        color: isDark ? kDivider : kLightDivider)),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? kCard2 : kLightCard2,
          borderRadius: BorderRadius.circular(20)),
        child: Text(time,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? kTextSecondary : kLightTextSub,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3))),
      Expanded(child: Container(
        height: 0.5,
        color: isDark ? kDivider : kLightDivider)),
    ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        titleSpacing: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.18),
              shape: BoxShape.circle),
            child: const Icon(Icons.group_rounded,
              color: kAccent, size: 20)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.groupName,
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15,
                color: isDark ? kTextPrimary : kLightText)),
            StreamBuilder<DocumentSnapshot>(
              stream: db.collection('groups').doc(widget.groupId).snapshots(),
              builder: (_, snap) {
                final members = List<String>.from(
                  (snap.data?.data() as Map?)?['members'] ?? []);
                return Text('${members.length} members',
                  style: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 11));
              }),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showGroupInfo(context)),
        ]),

      body: Column(children: [
        // ── Messages ──────────────────────────────────────────────────────
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('groups').doc(widget.groupId)
            .collection('messages').orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(
              child: CircularProgressIndicator(color: kAccent, strokeWidth: 2));
            final msgs = snap.data!.docs;

            if (msgs.isEmpty) return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.group_rounded,
                  size: 30, color: kAccent)),
              const SizedBox(height: 16),
              Text('Say hi to the group!',
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub,
                  fontSize: 15)),
            ]));

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollCtrl.hasClients) {
                _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
              }
            });

            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final data    = msgs[i].data() as Map<String, dynamic>;
                final isMe    = data['senderId'] == _myUid;
                final deleted = data['deleted'] == true;
                final unsent  = data['unsent']  == true;
                final text    = data['text'] as String? ?? '';
                final ts      = data['timestamp'] as Timestamp?;
                final reply   = data['reply']     as Map<String, dynamic>?;
                final reactions = Map<String, dynamic>.from(
                  data['reactions'] ?? {});

                final prevData = i > 0
                  ? msgs[i - 1].data() as Map<String, dynamic> : null;
                final nextData = i < msgs.length - 1
                  ? msgs[i + 1].data() as Map<String, dynamic> : null;

                final isFirst = prevData == null ||
                  prevData['senderId'] != data['senderId'];
                final isLast  = nextData == null ||
                  nextData['senderId'] != data['senderId'];

                final prevTs  = prevData?['timestamp'] as Timestamp?;
                final showTimeDivider = _shouldShowTimeDivider(prevTs, ts);

                final reactionCounts = <String, int>{};
                for (final e in reactions.values) {
                  reactionCounts[e as String] =
                    (reactionCounts[e] ?? 0) + 1;
                }

                final radius = BorderRadius.only(
                  topLeft:     const Radius.circular(kBubbleRadius),
                  topRight:    const Radius.circular(kBubbleRadius),
                  bottomLeft:  Radius.circular(
                    isMe ? kBubbleRadius : (isLast ? 4 : kBubbleRadius)),
                  bottomRight: Radius.circular(
                    isMe ? (isLast ? 4 : kBubbleRadius) : kBubbleRadius),
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Instagram-style time divider ──────────────────────
                    if (showTimeDivider) _timeDivider(_fmt(ts)),

                    // ── Unsent ghost ──────────────────────────────────────
                    if (unsent)
                      Padding(
                        padding: EdgeInsets.only(
                          top: isFirst ? 10 : 1, bottom: 1,
                          left: isMe ? 64 : 8, right: isMe ? 8 : 64),
                        child: Align(
                          alignment: isMe
                            ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              border: Border.all(
                                color: isDark ? kDivider : kLightDivider,
                                width: 1)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.undo_rounded, size: 12,
                                color: isDark ? kTextSecondary : kLightTextSub),
                              const SizedBox(width: 5),
                              Text(
                                isMe
                                  ? 'You unsent a message'
                                  : '${data['senderName'] ?? 'Someone'} unsent a message',
                                style: TextStyle(
                                  color: isDark ? kTextSecondary : kLightTextSub,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic)),
                            ]))))
                    else
                      // ── Normal bubble ─────────────────────────────────
                      GestureDetector(
                        onDoubleTap: () => _addReaction(msgs[i].id, '❤️'),
                        onLongPress: () => _showMsgMenu(
                          context, msgs[i].id, text,
                          data['senderName'] as String? ?? '',
                          isSender: isMe),
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: isFirst ? 10 : 1, bottom: 1,
                            left: isMe ? 64 : 8, right: isMe ? 8 : 64),
                          child: Align(
                            alignment: isMe
                              ? Alignment.centerRight : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                              children: [
                                if (!isMe && isFirst)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 4, bottom: 3),
                                    child: Text(data['senderName'] ?? '',
                                      style: const TextStyle(
                                        color: kAccent, fontSize: 11,
                                        fontWeight: FontWeight.w700))),

                                Stack(clipBehavior: Clip.none, children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: isMe ? kBubbleMe : kBubbleOther,
                                      borderRadius: radius,
                                      boxShadow: [BoxShadow(
                                        color: Colors.black.withOpacity(0.14),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2))]),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                      child: Column(
                                        crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                        children: [
                                          // Reply quote
                                          if (reply != null)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 8),
                                              padding: const EdgeInsets.fromLTRB(
                                                10, 7, 10, 7),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                  isMe ? 0.18 : 0.06),
                                                borderRadius:
                                                  BorderRadius.circular(10),
                                                border: Border(
                                                  left: BorderSide(
                                                    color: isMe
                                                      ? Colors.white54
                                                      : kAccent,
                                                    width: 3))),
                                              child: Column(
                                                crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                                children: [
                                                  Text(reply['sender'] ?? '',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: isMe
                                                        ? Colors.white70
                                                        : kAccent,
                                                      letterSpacing: 0.1)),
                                                  const SizedBox(height: 2),
                                                  Text(reply['text'] ?? '',
                                                    maxLines: 1,
                                                    overflow:
                                                      TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isMe
                                                        ? Colors.white54
                                                        : isDark
                                                          ? kTextSecondary
                                                          : kLightTextSub)),
                                                ])),

                                          // Message text
                                          if (deleted)
                                            Text(
                                              isMe
                                                ? 'You deleted this message'
                                                : 'This message was deleted',
                                              style: TextStyle(
                                                color: isMe
                                                  ? Colors.white38
                                                  : isDark
                                                    ? kTextSecondary
                                                    : kLightTextSub,
                                                fontSize: 15,
                                                height: 1.35,
                                                fontStyle: FontStyle.italic))
                                          else if (MarkdownText.hasMarkdown(text))
                                            MarkdownText(
                                              text: text,
                                              textColor: isMe
                                                ? Colors.white
                                                : isDark
                                                  ? kTextPrimary
                                                  : kLightText,
                                              isMe: isMe)
                                          else
                                            Text(text,
                                              style: TextStyle(
                                                color: isMe
                                                  ? Colors.white
                                                  : isDark
                                                    ? kTextPrimary
                                                    : kLightText,
                                                fontSize: 15,
                                                height: 1.35,
                                                letterSpacing: -0.1)),

                                          // Link Preview
                                          if (!deleted && hasUrl(text))
                                            LinkPreviewCard(
                                              url:  extractFirstUrl(text)!,
                                              isMe: isMe),
                                        ]))),

                                  // Reaction chips
                                  if (reactionCounts.isNotEmpty)
                                    Positioned(
                                      bottom: -13,
                                      right: isMe ? null : 6,
                                      left:  isMe ? 6 : null,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDark ? kCard2 : kLightCard2,
                                          borderRadius:
                                            BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isDark
                                              ? kDivider : kLightDivider,
                                            width: 0.5),
                                          boxShadow: kElevation1),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: reactionCounts.entries
                                            .map((e) => Padding(
                                              padding: const EdgeInsets.only(
                                                right: 2),
                                              child: Text(
                                                '${e.key}${e.value > 1 ? ' ${e.value}' : ''}',
                                                style: const TextStyle(
                                                  fontSize: 12))))
                                            .toList()))),
                                ]),

                                // Timestamp (only on last bubble in group)
                                if (isLast) ...[
                                  SizedBox(
                                    height: reactionCounts.isNotEmpty
                                      ? 18.0 : 5.0),
                                  Text(_fmt(ts),
                                    style: TextStyle(
                                      color: isDark
                                        ? kTextSecondary : kLightTextSub,
                                      fontSize: 10,
                                      letterSpacing: 0.2)),
                                ] else
                                  const SizedBox(height: 1),
                              ])))),
                  ]);
              });
          })),

        // ── Typing indicator ──────────────────────────────────────────────
        StreamBuilder<QuerySnapshot>(
          stream: db.collection('groups').doc(widget.groupId)
            .collection('typing').snapshots(),
          builder: (_, snap) {
            final typers = snap.data?.docs
              .where((d) => d.id != _myUid && d.get('isTyping') == true)
              .map((d) => d.get('name') as String? ?? 'Someone')
              .toList() ?? [];
            if (typers.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const TypingDots(),
                const SizedBox(width: 6),
                Text('${typers.join(', ')} typing...',
                  style: const TextStyle(color: kAccent, fontSize: 12)),
              ]));
          }),

        // ── Reply preview ─────────────────────────────────────────────────
        if (_replyToId != null)
          Container(
            color: isDark ? kCard : kLightCard,
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(children: [
              Container(width: 3, height: 36,
                decoration: BoxDecoration(
                  color: kAccent, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_replyToSender ?? '',
                  style: const TextStyle(
                    color: kAccent, fontSize: 12,
                    fontWeight: FontWeight.w700)),
                Text(_replyToText ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 12)),
              ])),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 18,
                  color: isDark ? kTextSecondary : kLightTextSub),
                onPressed: () => setState(() {
                  _replyToId = null;
                  _replyToText = null;
                  _replyToSender = null;
                })),
            ])),

        // ── Input bar ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(
            color: isDark ? kCard : kLightCard,
            border: Border(top: BorderSide(
              color: isDark ? kDivider : kLightDivider, width: 0.5))),
          child: Row(children: [
            Expanded(child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: isDark ? kCard2 : kLightCard2,
                borderRadius: BorderRadius.circular(22)),
              child: TextField(
                controller: _msgCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null, minLines: 1,
                style: TextStyle(
                  color: isDark ? kTextPrimary : kLightText, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10))))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(_msgCtrl.text),
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                  color: kAccent, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 18))),
          ])),
      ]));
  }

  void _showGroupInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kSheetRadius))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (_, ctrl) => StreamBuilder<DocumentSnapshot>(
          stream: db.collection('groups').doc(widget.groupId).snapshots(),
          builder: (_, snap) {
            final data    = snap.data?.data() as Map<String, dynamic>? ?? {};
            final members = List<String>.from(data['members'] ?? []);
            final admins  = List<String>.from(data['admins']  ?? []);
            return Column(children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? kTextTertiary : kLightTextSub,
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.15),
                  shape: BoxShape.circle),
                child: const Icon(Icons.group_rounded,
                  color: kAccent, size: 28)),
              const SizedBox(height: 10),
              Text(widget.groupName,
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: isDark ? kTextPrimary : kLightText)),
              Text('${members.length} members',
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub,
                  fontSize: 13)),
              const SizedBox(height: 16),
              Divider(color: isDark ? kDivider : kLightDivider),
              Expanded(child: ListView.builder(
                controller: ctrl,
                itemCount: members.length,
                itemBuilder: (_, i) => FutureBuilder<DocumentSnapshot>(
                  future: db.collection('users').doc(members[i]).get(),
                  builder: (_, uSnap) {
                    final u = uSnap.data?.data()
                      as Map<String, dynamic>? ?? {};
                    final isAdmin = admins.contains(members[i]);
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: kAccent.withOpacity(0.18),
                          shape: BoxShape.circle),
                        child: Center(child: Text(u['avatar'] ?? '?',
                          style: const TextStyle(
                            color: kAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)))),
                      title: Text(u['name'] ?? 'User',
                        style: TextStyle(
                          color: isDark ? kTextPrimary : kLightText,
                          fontWeight: FontWeight.w500)),
                      subtitle: Text('@${u['username'] ?? ''}',
                        style: TextStyle(
                          color: isDark ? kTextSecondary : kLightTextSub,
                          fontSize: 12)),
                      trailing: isAdmin
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8)),
                            child: const Text('Admin',
                              style: TextStyle(
                                color: kAccent, fontSize: 11,
                                fontWeight: FontWeight.bold)))
                        : null);
                  }))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kRed),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.exit_to_app_rounded, color: kRed),
                    label: const Text('Leave Group',
                      style: TextStyle(
                        color: kRed, fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      await db.collection('groups').doc(widget.groupId)
                        .update({'members': FieldValue.arrayRemove([_myUid])});
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      }
                    }))),
            ]);
          })));
  }
}
