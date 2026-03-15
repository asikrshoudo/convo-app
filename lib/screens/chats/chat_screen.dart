import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/active_status.dart';
import '../../core/chat_theme.dart';
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
  bool _sendAnimating = false;
  bool _hasText       = false; // tracks if input has text for Instagram-style morph

  // Track which message IDs have already been shown — only NEW ones animate
  final Set<String> _shownMsgIds = {};

  // ── Chat theme ────────────────────────────────────────────────────────────
  ChatThemeData _theme     = kChatThemes.first; // default
  String?       _customBgPath;                  // user-picked local photo path

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
    _loadChatTheme();
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

  // ── Theme helpers ─────────────────────────────────────────────────────────
  Future<void> _loadChatTheme() async {
    try {
      final doc = await db
          .collection('users').doc(_myUid)
          .collection('chatThemes').doc(widget.chatId).get();
      final themeId = (doc.data() as Map?)?['themeId'] as String?;
      final prefs   = await SharedPreferences.getInstance();
      final bgPath  = prefs.getString('chat_bg_${widget.chatId}');
      if (mounted) setState(() {
        _theme        = themeById(themeId);
        _customBgPath = bgPath;
      });
    } catch (_) {}
  }

  Future<void> _saveChatTheme(String themeId) async {
    setState(() => _theme = themeById(themeId));
    await db.collection('users').doc(_myUid)
        .collection('chatThemes').doc(widget.chatId)
        .set({'themeId': themeId}, SetOptions(merge: true));
  }

  Future<void> _pickCustomBackground() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_bg_${widget.chatId}', picked.path);
    if (mounted) setState(() => _customBgPath = picked.path);
  }

  Future<void> _removeCustomBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_bg_${widget.chatId}');
    if (mounted) setState(() => _customBgPath = null);
  }

  void _onTyping() {
    final hasText = _msgCtrl.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetRadius))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scroll) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: ListView(controller: scroll, children: [

              // Handle
              Center(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? kTextTertiary : kLightTextSub,
                    borderRadius: BorderRadius.circular(2))))),

              const Text('Chat Settings',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              // ── Chat Appearance ─────────────────────────────────────
              Align(alignment: Alignment.centerLeft,
                child: Text('Chat Appearance',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: isDark ? kTextSecondary : kLightTextSub))),
              const SizedBox(height: 12),

              // Theme grid
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kChatThemes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final t       = kChatThemes[i];
                    final selected = _theme.id == t.id;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _saveChatTheme(t.id);
                      },
                      child: Column(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: isDark ? t.bgDark : t.bgLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? kAccent : Colors.transparent,
                              width: 2.5),
                            boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 8, offset: const Offset(0, 3))]),
                          child: Stack(children: [
                            // Bubble preview
                            Positioned(right: 8, top: 10,
                              child: Container(
                                width: 28, height: 12,
                                decoration: BoxDecoration(
                                  color: t.bubbleMe,
                                  borderRadius: BorderRadius.circular(6)))),
                            Positioned(left: 8, bottom: 10,
                              child: Container(
                                width: 22, height: 12,
                                decoration: BoxDecoration(
                                  color: isDark
                                    ? t.bubbleOtherDark
                                    : t.bubbleOtherLight,
                                  borderRadius: BorderRadius.circular(6)))),
                            if (selected)
                              Positioned(right: 2, bottom: 2,
                                child: Container(
                                  width: 16, height: 16,
                                  decoration: const BoxDecoration(
                                    color: kAccent,
                                    shape: BoxShape.circle),
                                  child: const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 10))),
                          ])),
                        const SizedBox(height: 6),
                        Text(t.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                              ? FontWeight.w700 : FontWeight.normal,
                            color: selected ? kAccent
                              : isDark ? kTextSecondary : kLightTextSub)),
                      ]));
                  })),

              const SizedBox(height: 16),

              // Custom background
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.wallpaper_rounded,
                    color: kAccent, size: 20)),
                title: const Text('Custom Background',
                  style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(_customBgPath != null
                  ? 'Custom photo set' : 'Pick from gallery',
                  style: TextStyle(fontSize: 12,
                    color: isDark ? kTextSecondary : kLightTextSub)),
                trailing: _customBgPath != null
                  ? GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _removeCustomBackground();
                      },
                      child: Icon(Icons.close_rounded,
                        color: isDark ? kTextSecondary : kLightTextSub,
                        size: 18))
                  : null,
                onTap: () {
                  Navigator.pop(context);
                  _pickCustomBackground();
                }),

              Divider(color: isDark ? kDivider : kLightDivider, height: 24),

              // ── Disappearing Messages ────────────────────────────────
              Align(alignment: Alignment.centerLeft,
                child: Text('Disappearing Messages',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: isDark ? kTextSecondary : kLightTextSub))),
              const SizedBox(height: 6),
              ..._disappearOptions.map((opt) => RadioListTile<int?>(
                contentPadding: EdgeInsets.zero,
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

              Divider(color: isDark ? kDivider : kLightDivider, height: 24),

              // ── Nickname ─────────────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.badge_outlined,
                    color: kAccent, size: 20)),
                title: const Text('Set Nickname',
                  style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('Give this chat a nickname',
                  style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  final c = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Set Nickname'),
                      content: TextField(controller: c,
                        decoration: const InputDecoration(
                          hintText: 'Nickname...')),
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
            ])))));
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

  // ── Time divider helpers ──────────────────────────────────────────────────
  // Show divider when gap between messages >= 1 hour
  bool _shouldShowDivider(Timestamp? prev, Timestamp? curr) {
    if (prev == null || curr == null) return false;
    return curr.toDate().difference(prev.toDate()).inMinutes >= 60;
  }

  String _dividerLabel(Timestamp ts) {
    final now   = DateTime.now();
    final date  = ts.toDate().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final diff  = today.difference(msgDay).inDays;

    final h    = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final m    = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:$m $ampm';

    if (diff == 0) return 'Today $time';
    if (diff == 1) return 'Yesterday $time';
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[date.weekday - 1]} $time';
    }
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[date.month - 1]} ${date.day}, $time';
  }

  Widget _timeDivider(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      Expanded(child: Container(
        height: 0.5, color: isDark ? kDivider : kLightDivider)),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? kCard2 : kLightCard2,
          borderRadius: BorderRadius.circular(20)),
        child: Text(label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? kTextSecondary : kLightTextSub,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2))),
      Expanded(child: Container(
        height: 0.5, color: isDark ? kDivider : kLightDivider)),
    ]));

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
    // Resolve active bg — custom photo > theme asset > theme solid colour
    final themeBg      = isDark ? _theme.bgDark : _theme.bgLight;
    final bubbleMe     = _theme.bubbleMe;
    final bubbleOther  = isDark ? _theme.bubbleOtherDark : _theme.bubbleOtherLight;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: themeBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        shadowColor: Colors.transparent,
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

      body: Stack(children: [

        // ── Background layer ─────────────────────────────────────────
        Positioned.fill(child: Builder(builder: (_) {
          // 1. Custom user photo (local file)
          if (_customBgPath != null) {
            return Image.file(File(_customBgPath!),
              fit: BoxFit.cover, gaplessPlayback: true);
          }
          // 2. Preset theme asset photo
          if (_theme.bgAsset != null) {
            return Image.asset(_theme.bgAsset!,
              fit: BoxFit.cover, gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink());
          }
          // 3. Solid colour (already set as Scaffold bg)
          return const SizedBox.shrink();
        })),

        // ── Foreground content ────────────────────────────────────────
        Column(children: [
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
              padding: const EdgeInsets.only(left: 8, right: 8, top: 16, bottom: 90),
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
                final prevTs = prevData?['timestamp'] as Timestamp?;
                final currTs = data['timestamp'] as Timestamp?;
                final showDiv = _shouldShowDivider(prevTs, currTs);

                final msgId = msgs[i].id;
                final isNew = !_shownMsgIds.contains(msgId);
                if (isNew) _shownMsgIds.add(msgId);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDiv && currTs != null)
                      _timeDivider(_dividerLabel(currTs)),
                    ChatBubble(
                      msgId: msgId, chatId: widget.chatId,
                      data: data, isMe: isMe, isFirst: isFirst, isLast: isLast,
                      myUid: _myUid, otherUid: widget.otherUid,
                      isNew: isNew,
                      themeBubbleMe:    bubbleMe,
                      themeBubbleOther: bubbleOther,
                      onReply: (id, text, sender) {
                        if (!_canSend) return;
                        setState(() {
                          _replyToId     = id;
                          _replyToText   = text;
                          _replyToSender = sender;
                        });
                      }),
                  ]);
              });
          })),
        ]),        // Column (foreground) — messages only, no input here

        // ── Floating input island — truly over messages ───────────────
        if (_replyToId != null || _canSend)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(
                left: 12, right: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).viewInsets.bottom + 8
                  : MediaQuery.of(context).padding.bottom + 12),
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
                      color: Colors.black.withOpacity(0.12),
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
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 4)),
                  ]),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [

                    // Emoji
                    GestureDetector(
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 4, 12),
                        child: Icon(Icons.mood_rounded, size: 26,
                          color: isDark
                            ? Colors.white.withOpacity(0.5)
                            : Colors.black.withOpacity(0.4)))),

                    // Text field
                    Expanded(
                      child: TextField(
                        controller: _msgCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 6, minLines: 1,
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
                            vertical: 13)))),

                    // Send button — morphs in when typing
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: _hasText
                        ? GestureDetector(
                            onTap: () async {
                              final text = _msgCtrl.text;
                              if (text.trim().isEmpty || !_canSend) return;
                              setState(() => _sendAnimating = true);
                              await Future.delayed(
                                const Duration(milliseconds: 100));
                              if (mounted) setState(() => _sendAnimating = false);
                              _send(text);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(6, 0, 8, 8),
                              child: AnimatedScale(
                                scale: _sendAnimating ? 0.82 : 1.0,
                                duration: const Duration(milliseconds: 90),
                                curve: Curves.easeOut,
                                child: Container(
                                  width: 34, height: 34,
                                  decoration: BoxDecoration(
                                    color: kAccent,
                                    shape: BoxShape.circle),
                                  child: const Icon(Icons.send_rounded,
                                    color: Colors.white, size: 17)))))
                        : const SizedBox(width: 8)),

                  ])),          // Row (pill contents)
            ),                  // Container (pill)
          ]),                   // Column (reply + pill)
        ),                      // Padding
      ]));                      // Positioned + Stack + Scaffold
  }
}
