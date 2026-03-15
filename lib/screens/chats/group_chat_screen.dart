import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../core/constants.dart';
import '../../widgets/typing_dots.dart';
import '../../widgets/markdown_text.dart';
import '../../widgets/link_preview.dart';
import '../../widgets/gif_picker.dart';

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
  bool _showEmoji = false;

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

  Future<void> _openGifPicker() async {
    final gifUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GifPicker());
    if (gifUrl != null && gifUrl.isNotEmpty) _send(gifUrl);
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
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        shadowColor: Colors.transparent,
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

      body: Stack(children: [

        // ── Messages — full screen, bottom padding for input ──────────
        Positioned.fill(
          child: Column(children: [
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
              padding: EdgeInsets.only(
                left: 8, right: 8, top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 80 : 90),
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
                  topLeft:     const Radius.circular(20),
                  topRight:    const Radius.circular(20),
                  bottomLeft:  Radius.circular(
                    isMe ? 20 : (isLast ? 5 : 20)),
                  bottomRight: Radius.circular(
                    isMe ? (isLast ? 5 : 20) : 20),
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
                                        color: Colors.black.withOpacity(
                                          isDark ? 0.18 : 0.07),
                                        blurRadius: 12,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 3))]),
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

        const SizedBox(height: 80), // space for floating input
      ])),  // Positioned.fill Column

      // ── Floating input island ─────────────────────────────────────
      Positioned(
        left: 0, right: 0, bottom: 0,
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // Emoji picker panel
          if (_showEmoji)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                textEditingController: _msgCtrl,
                onEmojiSelected: (_, __) {},
                config: Config(
                  height: 280,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    emojiSizeMax: 28,
                    backgroundColor: isDark ? kCard : kLightCard),
                  skinToneConfig: const SkinToneConfig(),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: isDark ? kCard : kLightCard,
                    iconColor: isDark ? kTextSecondary : kLightTextSub,
                    iconColorSelected: kAccent,
                    indicatorColor: kAccent)))),

          // Pill + reply
          Padding(
            padding: EdgeInsets.only(
              left: 12, right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // Reply strip
              if (_replyToId != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: isDark ? kCard : kLightCard,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12, offset: const Offset(0, 4))]),
                  child: Row(children: [
                    Container(width: 3, height: 26,
                      decoration: BoxDecoration(
                        color: kAccent,
                        borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_replyToSender ?? '',
                          style: const TextStyle(color: kAccent,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                        Text(_replyToText ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? kTextSecondary : kLightTextSub,
                            fontSize: 12)),
                      ])),
                    GestureDetector(
                      onTap: () => setState(() {
                        _replyToId = _replyToText = _replyToSender = null;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded, size: 16,
                          color: isDark ? kTextTertiary : kLightTextSub))),
                  ])),

              // Floating pill
              Container(
                constraints: const BoxConstraints(minHeight: 50),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
                    blurRadius: 20, spreadRadius: 0,
                    offset: const Offset(0, 4))]),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [

                    // Emoji toggle button
                    GestureDetector(
                      onTap: () {
                        setState(() => _showEmoji = !_showEmoji);
                        if (_showEmoji) FocusScope.of(context).unfocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                        child: Icon(
                          _showEmoji
                            ? Icons.keyboard_rounded
                            : Icons.mood_rounded,
                          size: 24,
                          color: _showEmoji
                            ? kAccent
                            : isDark
                              ? Colors.white.withOpacity(0.45)
                              : Colors.black.withOpacity(0.38)))),

                    // Text field
                    Expanded(
                      child: TextField(
                        controller: _msgCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 6, minLines: 1,
                        onTap: () {
                          if (_showEmoji)
                            setState(() => _showEmoji = false);
                        },
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 15, height: 1.45),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: TextStyle(
                            color: isDark
                              ? Colors.white.withOpacity(0.3)
                              : Colors.black.withOpacity(0.3),
                            fontSize: 15),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12)))),

                    // GIF button
                    GestureDetector(
                      onTap: _openGifPicker,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isDark
                                ? Colors.white.withOpacity(0.3)
                                : Colors.black.withOpacity(0.25),
                              width: 1.2),
                            borderRadius: BorderRadius.circular(5)),
                          child: Text('GIF',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                ? Colors.white.withOpacity(0.5)
                                : Colors.black.withOpacity(0.4),
                              letterSpacing: 0.5))))),

                    // Send button — always visible, no animation
                    GestureDetector(
                      onTap: () {
                        final text = _msgCtrl.text;
                        if (text.trim().isEmpty) return;
                        _send(text);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 10),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: kAccent,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                              color: kAccent.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2))]),
                          child: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 17)))),
                  ])),         // Row + Container pill
            ]),               // Column children
          )),                 // Padding + Positioned child Column
      ]));                    // Stack + Scaffold
  }

  void _showGroupInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, ctrl) => StreamBuilder<DocumentSnapshot>(
          stream: db.collection('groups').doc(widget.groupId).snapshots(),
          builder: (_, snap) {
            final data    = snap.data?.data() as Map<String, dynamic>? ?? {};
            final members = List<String>.from(data['members'] ?? []);
            final admins  = List<String>.from(data['admins']  ?? []);
            final isAdmin = admins.contains(_myUid);
            final groupName = data['name'] ?? widget.groupName;
            return Column(children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? kTextTertiary : kLightTextSub,
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.15),
                  shape: BoxShape.circle),
                child: const Icon(Icons.group_rounded, color: kAccent, size: 32)),
              const SizedBox(height: 10),
              Text(groupName,
                style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700,
                  color: isDark ? kTextPrimary : kLightText)),
              Text('${members.length} members',
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
              const SizedBox(height: 14),

              // ── Admin actions ──────────────────────────────────────────
              if (isAdmin) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: _groupActionBtn(
                    Icons.edit_rounded, 'Edit',
                    kAccent, () async {
                      Navigator.pop(context);
                      await _showEditGroup(context, groupName);
                    })),
                  const SizedBox(width: 10),
                  Expanded(child: _groupActionBtn(
                    Icons.person_add_rounded, 'Add',
                    const Color(0xFF34C759), () async {
                      Navigator.pop(context);
                      await _showAddMember(context, members);
                    })),
                  const SizedBox(width: 10),
                  Expanded(child: _groupActionBtn(
                    Icons.delete_rounded, 'Delete',
                    kRed, () async {
                      Navigator.pop(context);
                      await _deleteGroup(context);
                    })),
                ])),

              if (isAdmin) const SizedBox(height: 12),

              // ── Mute toggle ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FutureBuilder<DocumentSnapshot>(
                  future: db.collection('users').doc(_myUid)
                    .collection('muted').doc(widget.groupId).get(),
                  builder: (_, mSnap) {
                    final isMuted = mSnap.data?.exists == true;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final ref = db.collection('users').doc(_myUid)
                          .collection('muted').doc(widget.groupId);
                        if (isMuted) {
                          await ref.delete();
                        } else {
                          await ref.set({'mutedAt': FieldValue.serverTimestamp()});
                        }
                        if (context.mounted) setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? kCard2 : kLightCard2,
                          borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Icon(
                            isMuted
                              ? Icons.notifications_off_rounded
                              : Icons.notifications_rounded,
                            color: isMuted ? kOrange : kAccent, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            isMuted ? 'Unmute Group' : 'Mute Group',
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500,
                              color: isDark ? kTextPrimary : kLightText)),
                          const Spacer(),
                          if (isMuted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kOrange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8)),
                              child: const Text('Muted',
                                style: TextStyle(
                                  color: kOrange, fontSize: 11,
                                  fontWeight: FontWeight.bold))),
                        ])));
                  })),

              Divider(
                color: isDark ? kDivider : kLightDivider,
                height: 24, indent: 16, endIndent: 16),

              // ── Members list ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('Members',
                    style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13,
                      color: isDark ? kTextSecondary : kLightTextSub)),
                  const Spacer(),
                  Text('${members.length}',
                    style: TextStyle(
                      color: isDark ? kTextSecondary : kLightTextSub,
                      fontSize: 13)),
                ])),
              const SizedBox(height: 8),

              Expanded(child: ListView.builder(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: members.length,
                itemBuilder: (_, i) => FutureBuilder<DocumentSnapshot>(
                  future: db.collection('users').doc(members[i]).get(),
                  builder: (_, uSnap) {
                    final u = uSnap.data?.data() as Map<String, dynamic>? ?? {};
                    final isAdmin2 = admins.contains(members[i]);
                    final isMe = members[i] == _myUid;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                      leading: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: kAccent.withOpacity(0.18),
                          shape: BoxShape.circle),
                        child: Center(child: Text(
                          (u['avatar'] ?? u['name'] ?? '?').toString().isNotEmpty
                            ? (u['avatar'] ?? u['name'] ?? '?')[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: kAccent, fontWeight: FontWeight.bold,
                            fontSize: 16)))),
                      title: Text(
                        '${u['name'] ?? 'User'}${isMe ? ' (You)' : ''}',
                        style: TextStyle(
                          color: isDark ? kTextPrimary : kLightText,
                          fontWeight: FontWeight.w500)),
                      subtitle: Text('@${u['username'] ?? ''}',
                        style: TextStyle(
                          color: isDark ? kTextSecondary : kLightTextSub,
                          fontSize: 12)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (isAdmin2)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8)),
                            child: const Text('Admin',
                              style: TextStyle(
                                color: kAccent, fontSize: 11,
                                fontWeight: FontWeight.bold))),
                        if (isAdmin && !isMe) ...[ 
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () async {
                              Navigator.pop(context);
                              await _removeMember(context, members[i],
                                u['name'] ?? 'User');
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: kRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.remove_circle_outline_rounded,
                                color: kRed, size: 16))),
                        ],
                      ]));
                  }))),

              // ── Leave / Delete ─────────────────────────────────────────
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

  Widget _groupActionBtn(IconData icon, String label, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(label,
            style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ])));
  }

  Future<void> _showEditGroup(BuildContext context, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(
              color: isDark ? kTextTertiary : kLightTextSub,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Edit Group',
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold,
              color: isDark ? kTextPrimary : kLightText)),
          const SizedBox(height: 20),
          TextField(
            controller: ctrl,
            style: TextStyle(color: isDark ? kTextPrimary : kLightText),
            decoration: InputDecoration(
              labelText: 'Group Name',
              labelStyle: TextStyle(
                color: isDark ? kTextSecondary : kLightTextSub),
              filled: true,
              fillColor: isDark ? kCard2 : kLightCard2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kAccent)))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent, elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                await db.collection('groups').doc(widget.groupId)
                  .update({'name': name});
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save',
                style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)))),
        ])));
  }

  Future<void> _showAddMember(BuildContext context,
      List<String> currentMembers) async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? kTextTertiary : kLightTextSub,
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Add Member',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: isDark ? kTextPrimary : kLightText)),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchCtrl,
                  style: TextStyle(
                    color: isDark ? kTextPrimary : kLightText),
                  decoration: InputDecoration(
                    hintText: 'Search by username...',
                    hintStyle: TextStyle(
                      color: isDark ? kTextSecondary : kLightTextSub),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: isDark ? kCard2 : kLightCard2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none)),
                  onChanged: (q) async {
                    if (q.trim().isEmpty) {
                      setS(() => results = []);
                      return;
                    }
                    final qLow = q.trim().toLowerCase();
                    final snap = await db.collection('users')
                      .where('username',
                        isGreaterThanOrEqualTo: qLow,
                        isLessThan: '${qLow}z')
                      .limit(10).get();
                    setS(() => results = snap.docs
                      .where((d) => !currentMembers.contains(d.id)
                        && d.id != _myUid)
                      .map((d) => {...d.data(), 'uid': d.id})
                      .toList());
                  })),
              const SizedBox(height: 8),
              Expanded(child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final u = results[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kAccent,
                      child: Text(
                        (u['name'] ?? 'U').toString()[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold))),
                    title: Text(u['name'] ?? 'User',
                      style: TextStyle(
                        color: isDark ? kTextPrimary : kLightText)),
                    subtitle: Text('@${u['username'] ?? ''}',
                      style: TextStyle(
                        color: isDark ? kTextSecondary : kLightTextSub,
                        fontSize: 12)),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent, elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                      onPressed: () async {
                        await db.collection('groups')
                          .doc(widget.groupId)
                          .update({
                            'members': FieldValue.arrayUnion([u['uid']]),
                          });
                        setS(() => results.removeAt(i));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(
                              '${u['name']} added!'),
                              backgroundColor: kAccent));
                        }
                      },
                      child: const Text('Add',
                        style: TextStyle(
                          color: Colors.white, fontSize: 12))));
                })),
            ])))));
  }

  Future<void> _removeMember(BuildContext context, String uid,
      String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? kCard : kLightCard,
        title: Text('Remove Member?',
          style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
        content: Text('Remove $name from the group?',
          style: TextStyle(
            color: isDark ? kTextSecondary : kLightTextSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: kRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove')),
        ]));
    if (confirm != true) return;
    await db.collection('groups').doc(widget.groupId)
      .update({'members': FieldValue.arrayRemove([uid])});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name removed'),
        backgroundColor: kRed));
  }

  Future<void> _deleteGroup(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? kCard : kLightCard,
        title: Text('Delete Group?',
          style: TextStyle(color: isDark ? kTextPrimary : kLightText)),
        content: Text(
          'This will permanently delete the group and all messages.',
          style: TextStyle(
            color: isDark ? kTextSecondary : kLightTextSub)),
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
    await db.collection('groups').doc(widget.groupId).delete();
    if (mounted) Navigator.of(context)
      ..pop()
      ..pop();
  }
}
