import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/active_status.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/typing_dots.dart';
import '../profile/profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final String otherUid, otherName, otherAvatar, chatId;
  // isRequest: true → opened from MessageRequestsScreen (read-only until accepted)
  final bool isRequest;
  const ChatScreen({
    super.key,
    required this.otherUid,
    required this.otherName,
    required this.otherAvatar,
    required this.chatId,
    this.isRequest = false,
  });
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;


  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _replyToId, _replyToText, _replyToSender;
  int?    _disappearSeconds;
  late String _myUid;
  Timer? _typingTimer;

  // Relationship state
  bool _iBlockedThem  = false;
  bool _theyBlockedMe = false;
  bool _isFriend      = false;
  bool _statusLoaded  = false;

  static const _notifyUrl = 'https://convo-notify.onrender.com/notify/dm';

  static const _disappearOptions = [
    {'label': 'Off',      'seconds': null},
    {'label': '12 hours', 'seconds': 43200},
    {'label': '24 hours', 'seconds': 86400},
    {'label': '7 days',   'seconds': 604800},
  ];

  @override
  void initState() {
    super.initState();
    _myUid = auth.currentUser!.uid;
    _clearUnreadSafe();
    _markMessagesSeenSafe();
    _loadDisappearSetting();
    _loadRelationshipStatus();
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

  // ── Load block + friend status ────────────────────────────────────────────
  Future<void> _loadRelationshipStatus() async {
    try {
      // Only read what our rules allow: our own blocked + friends lists.
      // We cannot read otherUid's blocked list (permission denied by rules).
      // Instead, store a 'blockedBy' mirror doc when blocking someone.
      final results = await Future.wait([
        db.collection('users').doc(_myUid)
            .collection('blocked').doc(widget.otherUid).get(),
        db.collection('users').doc(_myUid)
            .collection('blockedBy').doc(widget.otherUid).get(),
        db.collection('users').doc(_myUid)
            .collection('friends').doc(widget.otherUid).get(),
      ]);
      if (!mounted) return;
      setState(() {
        _iBlockedThem  = results[0].exists;
        _theyBlockedMe = results[1].exists; // mirror written when other blocks us
        _isFriend      = results[2].exists;
        _statusLoaded  = true;
      });
    } catch (_) {
      // Fallback: if any read fails, allow sending (fail open).
      if (mounted) setState(() => _statusLoaded = true);
    }
  }

  Future<void> _loadDisappearSetting() async {
    final doc = await db.collection('chats').doc(widget.chatId).get();
    if (doc.exists && mounted) {
      setState(() => _disappearSeconds =
          (doc.data() as Map?)?['disappearSeconds']);
    }
  }

  void _onTyping() {
    _typingTimer?.cancel();
    _setTyping(true);
    _typingTimer =
        Timer(const Duration(seconds: 3), () => _setTyping(false));
  }

  Future<void> _setTyping(bool v) async =>
    db.collection('chats').doc(widget.chatId)
      .collection('typing').doc(_myUid)
      .set({'isTyping': v, 'ts': FieldValue.serverTimestamp()});

  Future<void> _clearUnread() async =>
    db.collection('chats').doc(widget.chatId)
      .set({'unread_$_myUid': 0}, SetOptions(merge: true));

  Future<void> _markMessagesSeen() async {
    final msgs = await db
        .collection('chats').doc(widget.chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: _myUid)
        .where('seen', isEqualTo: false)
        .get();
    final batch = db.batch();
    for (final doc in msgs.docs) {
      batch.update(doc.reference,
          {'seen': true, 'seenAt': FieldValue.serverTimestamp()});
    }
    if (msgs.docs.isNotEmpty) await batch.commit();
  }

  // chat doc henot exist করলে silently ignore করো
  Future<void> _clearUnreadSafe() async {
    try { await _clearUnread(); } catch (_) {}
  }
  Future<void> _markMessagesSeenSafe() async {
    try { await _markMessagesSeen(); } catch (_) {}
  }

  // ── Can the current user send? ────────────────────────────────────────────
  bool get _canSend =>
    _statusLoaded && !_iBlockedThem && !_theyBlockedMe && !widget.isRequest;

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || !_canSend) return;
    _msgCtrl.clear();
    _setTyping(false);

    final reply = _replyToId != null
      ? {'id': _replyToId, 'text': _replyToText, 'sender': _replyToSender}
      : null;
    setState(() {
      _replyToId = null; _replyToText = null; _replyToSender = null;
    });

    final expiresAt = _disappearSeconds != null
      ? Timestamp.fromDate(
          DateTime.now().add(Duration(seconds: _disappearSeconds!)))
      : null;

    // Step 1: chat doc আগে তৈরি করতে হবে — rules এ isChatParticipant চেক করে
    await db.collection('chats').doc(widget.chatId).set({
      'participants': [_myUid, widget.otherUid],
      'lastMessage': t,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastSender': _myUid,
      'unread_${widget.otherUid}': FieldValue.increment(1),
      'unread_$_myUid': 0,
    }, SetOptions(merge: true));

    // Step 2: এখন message লেখো (chat doc exists, rules pass)
    final msgRef = await db
      .collection('chats').doc(widget.chatId)
      .collection('messages').add({
        'text': t, 'senderId': _myUid,
        'senderName': auth.currentUser?.displayName ?? 'User',
        'timestamp': FieldValue.serverTimestamp(),
        'deleted': false, 'seen': false,
        if (reply != null)     'reply': reply,
        if (expiresAt != null) 'expiresAt': expiresAt,
      });

    // Step 3: friend না হলে message_requests এ সেভ করো
    if (!_isFriend) {
      final meDoc  = await db.collection('users').doc(_myUid).get();
      final myName = meDoc.data()?['name']   as String? ?? 'User';
      final myAvtr = meDoc.data()?['avatar'] as String? ?? 'U';
      await db.collection('message_requests').doc(widget.chatId).set({
        'from':        _myUid,
        'to':          widget.otherUid,
        'fromName':    myName,
        'fromAvatar':  myAvtr,
        'chatId':      widget.chatId,
        'lastMessage': t,
        'status':      'pending',
        'timestamp':   FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    try {
      await http.post(
        Uri.parse(_notifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId': widget.chatId, 'messageId': msgRef.id,
          'senderId': _myUid, 'text': t,
        }),
      );
    } catch (_) {}

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
      }
    });
  }

  void _showChatSettings() {

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetRadius))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? kTextTertiary : kLightTextSub,
                  borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Chat Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Disappearing Messages',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: isDark ? kTextSecondary : kLightTextSub))),
            const SizedBox(height: 10),
            ..._disappearOptions.map((opt) => RadioListTile<int?>(
              value: opt['seconds'] as int?,
              groupValue: _disappearSeconds,
              activeColor: kAccent,
              title: Text(opt['label'] as String),
              onChanged: (v) async {
                setSt(() {});
                setState(() => _disappearSeconds = v);
                await db.collection('chats').doc(widget.chatId)
                  .set({'disappearSeconds': v}, SetOptions(merge: true));
              })).toList(),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.badge_outlined, color: kAccent),
              title: const Text('Set Nickname'),
              subtitle: Text('Give this chat a nickname',
                  style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                final c = TextEditingController();
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Set Nickname'),
                    content: TextField(controller: c,
                      decoration: InputDecoration(hintText: 'Nickname...')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () async {
                          await db.collection('chats').doc(widget.chatId)
                            .set({'nickname_$_myUid': c.text.trim()},
                                SetOptions(merge: true));
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Save')),
                    ]));
              }),
          ]))));
  }

  // ── Status banner ────────────────────────────────────────────────────────
  Widget? _buildStatusBanner() {
    if (!_statusLoaded) return null;
    if (_iBlockedThem) {
      return _banner(Icons.block_rounded, kRed,
        'You blocked this user. Unblock to send messages.');
    }
    if (_theyBlockedMe) {
      return _banner(Icons.block_rounded, kRed,
        'You cannot send messages to this user.');
    }
    if (widget.isRequest) {
      return _banner(Icons.inbox_rounded, kAccent,
        'Accept this request to reply.');
    }
    if (!_isFriend) {
      return _banner(Icons.info_outline_rounded, const Color(0xFFFFB300),
        'They\'re not your friend — your message goes to their Requests.');
    }
    return null;
  }

  Widget _banner(IconData icon, Color color, String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    color: color.withOpacity(0.10),
    child: Row(children: [
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 8),
      Expanded(child: Text(msg,
        style: TextStyle(color: color, fontSize: 12,
          fontWeight: FontWeight.w500))),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ProfileScreen(uid: widget.otherUid))),
          child: Row(children: [
            Stack(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.2),
                  shape: BoxShape.circle),
                child: Center(child: Text(
                  widget.otherAvatar,
                  style: const TextStyle(
                    color: kAccent, fontWeight: FontWeight.bold,
                    fontSize: 16)))),
              StreamBuilder<DocumentSnapshot>(
                stream: db.collection('users').doc(widget.otherUid).snapshots(),
                builder: (_, snap) {
                  if (snap.data?.get('isOnline') != true) return const SizedBox();
                  return Positioned(right: 0, bottom: 0,
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759),
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? kDark : kLightBg, width: 1.5))));
                }),
            ]),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.otherName,
                style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15,
                  color: isDark ? kTextPrimary : kLightText)),
              StreamBuilder<DocumentSnapshot>(
                stream: db.collection('chats').doc(widget.chatId)
                  .collection('typing').doc(widget.otherUid).snapshots(),
                builder: (_, tSnap) {
                  if (tSnap.data?.get('isTyping') == true) {
                    return Row(children: [
                      const TypingDots(),
                      const SizedBox(width: 4),
                      const Text('typing...',
                        style: TextStyle(color: kAccent, fontSize: 11)),
                    ]);
                  }
                  return StreamBuilder<DocumentSnapshot>(
                    stream: db.collection('users').doc(widget.otherUid).snapshots(),
                    builder: (_, snap) {
                      final online   = snap.data?.get('isOnline') == true;
                      final lastSeen = snap.data?.get('lastSeen') as Timestamp?;
                      final text     = activeStatusText(online, lastSeen);
                      if (text == null) return const SizedBox.shrink();
                      return Text(text,
                        style: TextStyle(
                          color: online ? const Color(0xFF34C759) : isDark ? kTextSecondary : kLightTextSub,
                          fontSize: 11));
                    });
                }),
            ]),
          ])),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: _showChatSettings),
        ]),

      body: Column(children: [
        // Status banner (block / request / non-friend)
        if (_buildStatusBanner() != null) _buildStatusBanner()!,

        // Disappearing messages banner
        if (_disappearSeconds != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: kAccent.withOpacity(0.08),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.timer_outlined, color: kAccent, size: 13),
              const SizedBox(width: 5),
              Text(
                'Disappearing: ${_disappearOptions.firstWhere((o) => o['seconds'] == _disappearSeconds)['label']}',
                style: const TextStyle(color: kAccent, fontSize: 12,
                  fontWeight: FontWeight.w500)),
            ])),

        // Messages
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('chats').doc(widget.chatId)
            .collection('messages').orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (snap.hasError) {
              // chat doc এখনো নেই — empty state দেখাও
              return Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.waving_hand_rounded,
                    size: 30, color: kAccent)),
                const SizedBox(height: 16),
                Text('Say hi to ${widget.otherName}!',
                  style: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub, fontSize: 15)),
              ]));
            }
            if (!snap.hasData) return const Center(
              child: CircularProgressIndicator(color: kAccent, strokeWidth: 2));

            final now  = Timestamp.now();
            final msgs = snap.data!.docs.where((d) {
              final exp = (d.data() as Map)['expiresAt'] as Timestamp?;
              return exp == null || exp.compareTo(now) > 0;
            }).toList();

            if (msgs.isEmpty) {
              return Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.waving_hand_rounded,
                    size: 30, color: kAccent)),
                const SizedBox(height: 16),
                Text('Say hi to ${widget.otherName}!',
                  style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 15)),
              ]));
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollCtrl.hasClients) {
                _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
              }
            });
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _markMessagesSeenSafe());

            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final data     = msgs[i].data() as Map<String, dynamic>;
                final isMe     = data['senderId'] == _myUid;
                final prevData = i > 0
                  ? msgs[i - 1].data() as Map<String, dynamic> : null;
                final nextData = i < msgs.length - 1
                  ? msgs[i + 1].data() as Map<String, dynamic> : null;
                final isFirst  =
                  prevData == null || prevData['senderId'] != data['senderId'];
                final isLast   =
                  nextData == null || nextData['senderId'] != data['senderId'];
                return ChatBubble(
                  msgId: msgs[i].id, chatId: widget.chatId,
                  data: data, isMe: isMe, isFirst: isFirst, isLast: isLast,
                  myUid: _myUid, otherUid: widget.otherUid,
                  onReply: (id, text, sender) {
                    if (!_canSend) return;
                    setState(() {
                      _replyToId     = id;
                      _replyToText   = text;
                      _replyToSender = sender;
                    });
                  });
              });
          })),

        // Reply preview
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
                    color: kAccent, fontSize: 12, fontWeight: FontWeight.w700)),
                Text(_replyToText ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
              ])),
              IconButton(
                icon: Icon(Icons.close_rounded,
                  size: 18, color: isDark ? kTextSecondary : kLightTextSub),
                onPressed: () => setState(() {
                  _replyToId = null; _replyToText = null; _replyToSender = null;
                })),
            ])),

        // Input bar — only shown when _canSend
        if (_canSend)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: BoxDecoration(
              color: isDark ? kCard : kLightCard,
              border: Border(top: BorderSide(color: isDark ? kDivider : kLightDivider, width: 0.5))),
            child: Row(children: [
              Expanded(child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark ? kCard2 : kLightCard2, borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  controller: _msgCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null, minLines: 1,
                  style: TextStyle(color: isDark ? kTextPrimary : kLightText, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    hintStyle: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
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
}
