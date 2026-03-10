import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/typing_dots.dart';
import '../profile/profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final String otherUid, otherName, otherAvatar, chatId;
  const ChatScreen({
    super.key,
    required this.otherUid,
    required this.otherName,
    required this.otherAvatar,
    required this.chatId,
  });
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _replyToId, _replyToText, _replyToSender;
  int?    _disappearSeconds;
  late String _myUid;
  Timer? _typingTimer;

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
    _clearUnread();
    _loadDisappearSetting();
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

  Future<void> _loadDisappearSetting() async {
    final doc = await db.collection('chats').doc(widget.chatId).get();
    if (doc.exists && mounted) {
      setState(() => _disappearSeconds = (doc.data() as Map?)?['disappearSeconds']);
    }
  }

  void _onTyping() {
    _typingTimer?.cancel();
    _setTyping(true);
    _typingTimer = Timer(const Duration(seconds: 3), () => _setTyping(false));
  }

  Future<void> _setTyping(bool v) async =>
    db.collection('chats').doc(widget.chatId).collection('typing').doc(_myUid)
      .set({'isTyping': v, 'ts': FieldValue.serverTimestamp()});

  Future<void> _clearUnread() async =>
    db.collection('chats').doc(widget.chatId).set({'unread_$_myUid': 0}, SetOptions(merge: true));

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _msgCtrl.clear();
    _setTyping(false);

    final reply = _replyToId != null
      ? {'id': _replyToId, 'text': _replyToText, 'sender': _replyToSender}
      : null;
    setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; });

    final expiresAt = _disappearSeconds != null
      ? Timestamp.fromDate(DateTime.now().add(Duration(seconds: _disappearSeconds!)))
      : null;

    final msgRef = await db.collection('chats').doc(widget.chatId).collection('messages').add({
      'text': t, 'senderId': _myUid,
      'senderName': auth.currentUser?.displayName ?? 'User',
      'timestamp': FieldValue.serverTimestamp(), 'deleted': false,
      if (reply != null)    'reply': reply,
      if (expiresAt != null) 'expiresAt': expiresAt,
    });
    await db.collection('chats').doc(widget.chatId).set({
      'participants': [_myUid, widget.otherUid],
      'lastMessage': t, 'lastTimestamp': FieldValue.serverTimestamp(), 'lastSender': _myUid,
      'unread_${widget.otherUid}': FieldValue.increment(1), 'unread_$_myUid': 0,
    }, SetOptions(merge: true));

    // ── Notify receiver ───────────────────────────────────────────────────────
    try {
      await http.post(
        Uri.parse(_notifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId':    widget.chatId,
          'messageId': msgRef.id,
          'senderId':  _myUid,
          'text':      t,
        }),
      );
    } catch (_) {
      // Notification failure shouldn't block the user
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _showChatSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Chat Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft,
            child: Text('Disappearing Messages', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          const SizedBox(height: 10),
          ..._disappearOptions.map((opt) => RadioListTile<int?>(
            value: opt['seconds'] as int?,
            groupValue: _disappearSeconds,
            activeColor: kGreen,
            title: Text(opt['label'] as String),
            onChanged: (v) async {
              setSt(() {});
              setState(() => _disappearSeconds = v);
              await db.collection('chats').doc(widget.chatId).set({'disappearSeconds': v}, SetOptions(merge: true));
            })).toList(),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: kGreen),
            title: const Text('Set Nickname'),
            subtitle: const Text('Give this chat a nickname'),
            onTap: () {
              Navigator.pop(context);
              final c = TextEditingController();
              showDialog(context: context, builder: (_) => AlertDialog(
                title: const Text('Set Nickname'),
                content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Nickname...')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kGreen),
                    onPressed: () async {
                      await db.collection('chats').doc(widget.chatId).set(
                          {'nickname_$_myUid': c.text.trim()}, SetOptions(merge: true));
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Save', style: TextStyle(color: Colors.white))),
                ]));
            }),
        ]))));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white, titleSpacing: 0, elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context)),
        title: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: widget.otherUid))),
          child: Row(children: [
            Stack(children: [
              CircleAvatar(radius: 19, backgroundColor: kGreen,
                child: Text(widget.otherAvatar,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              StreamBuilder<DocumentSnapshot>(
                stream: db.collection('users').doc(widget.otherUid).snapshots(),
                builder: (_, snap) {
                  if (snap.data?.get('isOnline') != true) return const SizedBox();
                  return Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
                      border: Border.all(color: isDark ? kDark : Colors.white, width: 2))));
                }),
            ]),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.otherName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              StreamBuilder<DocumentSnapshot>(
                stream: db.collection('chats').doc(widget.chatId).collection('typing').doc(widget.otherUid).snapshots(),
                builder: (_, tSnap) {
                  final isTyping = tSnap.data?.get('isTyping') == true;
                  if (isTyping) return Row(children: [
                    const TypingDots(),
                    const SizedBox(width: 4),
                    Text('typing...', style: TextStyle(color: kGreen, fontSize: 11)),
                  ]);
                  return StreamBuilder<DocumentSnapshot>(
                    stream: db.collection('users').doc(widget.otherUid).snapshots(),
                    builder: (_, snap) {
                      final online = snap.data?.get('isOnline') == true;
                      return Text(online ? 'Online' : 'Offline',
                        style: TextStyle(color: online ? kGreen : Colors.grey, fontSize: 11));
                    });
                }),
            ]),
          ])),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _showChatSettings),
        ]),
      body: Column(children: [
        // Disappearing messages banner
        if (_disappearSeconds != null) Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6),
          color: kGreen.withOpacity(0.1),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.timer_outlined, color: kGreen, size: 14),
            const SizedBox(width: 4),
            Text('Disappearing: ${_disappearOptions.firstWhere((o) => o['seconds'] == _disappearSeconds)['label']}',
              style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w500)),
          ])),

        // Messages list
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('chats').doc(widget.chatId).collection('messages').orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kGreen));
            final now  = Timestamp.now();
            final msgs = snap.data!.docs.where((d) {
              final exp = (d.data() as Map)['expiresAt'] as Timestamp?;
              return exp == null || exp.compareTo(now) > 0;
            }).toList();

            if (msgs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.waving_hand_rounded, size: 48, color: kGreen),
              const SizedBox(height: 12),
              Text('Say hi to ${widget.otherName}!', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
            ]));

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            });

            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final data    = msgs[i].data() as Map<String, dynamic>;
                final isMe    = data['senderId'] == _myUid;
                final prevData = i > 0 ? msgs[i - 1].data() as Map<String, dynamic> : null;
                final isFirst = prevData == null || prevData['senderId'] != data['senderId'];
                return ChatBubble(
                  msgId: msgs[i].id, chatId: widget.chatId,
                  data: data, isMe: isMe, isFirst: isFirst,
                  onReply: (id, text, sender) =>
                    setState(() { _replyToId = id; _replyToText = text; _replyToSender = sender; }));
              });
          })),

        // Reply preview strip
        if (_replyToId != null) Container(
          color: isDark ? kCard2 : Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(width: 3, height: 36,
              decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_replyToSender ?? '', style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; })),
          ])),

        // Input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? kCard : Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))]),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _msgCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4, minLines: 1,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Message...', hintStyle: TextStyle(color: Colors.grey[500]),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                filled: true, fillColor: isDark ? kCard2 : Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(_msgCtrl.text),
              child: Container(width: 46, height: 46,
                decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(23)),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
          ])),
      ]));
  }
}
