import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../widgets/typing_dots.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId, groupName;
  const GroupChatScreen({super.key, required this.groupId, required this.groupName});
  @override State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
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
    setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; });

    // Get group members for unread increment
    final groupDoc = await db.collection('groups').doc(widget.groupId).get();
    final members = List<String>.from(groupDoc.data()?['members'] ?? []);
    final unreadUpdates = <String, dynamic>{};
    for (final uid in members) {
      if (uid != _myUid) unreadUpdates['unread_$uid'] = FieldValue.increment(1);
    }

    await db.collection('groups').doc(widget.groupId)
      .collection('messages').add({
        'text': t, 'senderId': _myUid, 'senderName': _myName,
        'timestamp': FieldValue.serverTimestamp(), 'deleted': false,
        'seen': false,
        if (reply != null) 'reply': reply,
      });

    await db.collection('groups').doc(widget.groupId).set({
      'lastMessage': t,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastSenderName': _myName,
      'unread_$_myUid': 0,
      ...unreadUpdates,
    }, SetOptions(merge: true));

    // Notify group members
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

  void _showMsgMenu(BuildContext context, bool isDark, String msgId, String text, String senderName) {
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
        // Emoji row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['❤️', '😂', '😮', '😢', '👍', '👎'].map((emoji) =>
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _addReaction(msgId, emoji);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? kCard2 : Colors.grey[100],
                    shape: BoxShape.circle),
                  child: Text(emoji, style: const TextStyle(fontSize: 24))))).toList())),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.reply_rounded, color: kGreen),
          title: const Text('Reply'),
          onTap: () {
            Navigator.pop(context);
            setState(() {
              _replyToId = msgId;
              _replyToText = text;
              _replyToSender = senderName;
            });
          }),
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy'),
          onTap: () { Navigator.pop(context); Clipboard.setData(ClipboardData(text: text)); }),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          title: const Text('Delete', style: TextStyle(color: Colors.red)),
          onTap: () {
            Navigator.pop(context);
            db.collection('groups').doc(widget.groupId)
              .collection('messages').doc(msgId)
              .update({'deleted': true, 'text': 'This message was deleted'});
          }),
        const SizedBox(height: 12),
      ]));
  }

  Future<void> _addReaction(String msgId, String emoji) async {
    final doc = await db.collection('groups').doc(widget.groupId)
      .collection('messages').doc(msgId).get();
    final reactions = Map<String, dynamic>.from(doc.data()?['reactions'] ?? {});
    if (reactions[_myUid] == emoji) {
      reactions.remove(_myUid);
    } else {
      reactions[_myUid] = emoji;
    }
    await db.collection('groups').doc(widget.groupId)
      .collection('messages').doc(msgId).update({'reactions': reactions});
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white,
        titleSpacing: 0, elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: kGreen.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.group_rounded, color: kGreen, size: 22)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            StreamBuilder<DocumentSnapshot>(
              stream: db.collection('groups').doc(widget.groupId).snapshots(),
              builder: (_, snap) {
                final members = List<String>.from((snap.data?.data() as Map?)?['members'] ?? []);
                return Text('${members.length} members', style: TextStyle(color: Colors.grey[500], fontSize: 11));
              }),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showGroupInfo(context)),
        ]),
      body: Column(children: [
        // Messages
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('groups').doc(widget.groupId)
            .collection('messages').orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kGreen));
            final msgs = snap.data!.docs;

            if (msgs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.group_rounded, size: 48, color: kGreen),
              const SizedBox(height: 12),
              Text('Say hi to the group!', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
            ]));

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            });

            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final data = msgs[i].data() as Map<String, dynamic>;
                final isMe = data['senderId'] == _myUid;
                final deleted = data['deleted'] == true;
                final text = data['text'] as String? ?? '';
                final ts = data['timestamp'] as Timestamp?;
                final reply = data['reply'] as Map<String, dynamic>?;
                final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
                final prevData = i > 0 ? msgs[i - 1].data() as Map<String, dynamic> : null;
                final isFirst = prevData == null || prevData['senderId'] != data['senderId'];
                final nextData = i < msgs.length - 1 ? msgs[i + 1].data() as Map<String, dynamic> : null;
                final isLast = nextData == null || nextData['senderId'] != data['senderId'];

                final reactionCounts = <String, int>{};
                for (final e in reactions.values) {
                  reactionCounts[e as String] = (reactionCounts[e] ?? 0) + 1;
                }

                return GestureDetector(
                  onDoubleTap: () => _addReaction(msgs[i].id, '❤️'),
                  onLongPress: () => _showMsgMenu(context, isDark, msgs[i].id, text, data['senderName'] as String? ?? ''),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: isFirst ? 8 : 2, bottom: 2,
                      left: isMe ? 56 : 0, right: isMe ? 0 : 56),
                    child: Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          // Sender name for others
                          if (!isMe && isFirst)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 2),
                              child: Text(data['senderName'] ?? '',
                                style: TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold))),

                          Stack(clipBehavior: Clip.none, children: [
                            Container(
                              decoration: BoxDecoration(
                                color: isMe ? kGreen : (isDark ? kCard2 : Colors.white),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 18)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]),
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
                                      Text(reply['sender'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                      Text(reply['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                    ])),
                                  Text(text, style: TextStyle(
                                    color: deleted
                                      ? (isMe ? Colors.white54 : Colors.grey[500])
                                      : (isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color),
                                    fontSize: 15,
                                    fontStyle: deleted ? FontStyle.italic : FontStyle.normal)),
                                ]))),

                            if (reactionCounts.isNotEmpty)
                              Positioned(
                                bottom: -14,
                                right: isMe ? null : 8,
                                left: isMe ? 8 : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? kCard : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]),
                                  child: Row(mainAxisSize: MainAxisSize.min,
                                    children: reactionCounts.entries.map((e) =>
                                      Text('${e.key}${e.value > 1 ? e.value.toString() : ''}',
                                        style: const TextStyle(fontSize: 12))).toList()))),
                          ]),

                          if (isLast) ...[
                            SizedBox(height: reactionCounts.isNotEmpty ? 16 : 4),
                            Text(_fmt(ts), style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                          ] else
                            const SizedBox(height: 2),
                        ]))));
              });
          })),

        // Typing indicator
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
                  style: TextStyle(color: kGreen, fontSize: 12)),
              ]));
          }),

        // Reply preview
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
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
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

  void _showGroupInfo(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (_, ctrl) => StreamBuilder<DocumentSnapshot>(
          stream: db.collection('groups').doc(widget.groupId).snapshots(),
          builder: (_, snap) {
            final data = snap.data?.data() as Map<String, dynamic>? ?? {};
            final members = List<String>.from(data['members'] ?? []);
            final admins = List<String>.from(data['admins'] ?? []);
            return Column(children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Icon(Icons.group_rounded, color: kGreen, size: 48),
              const SizedBox(height: 8),
              Text(widget.groupName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${members.length} members', style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 16),
              const Divider(),
              Expanded(child: ListView.builder(
                controller: ctrl,
                itemCount: members.length,
                itemBuilder: (_, i) => FutureBuilder<DocumentSnapshot>(
                  future: db.collection('users').doc(members[i]).get(),
                  builder: (_, uSnap) {
                    final u = uSnap.data?.data() as Map<String, dynamic>? ?? {};
                    final isAdmin = admins.contains(members[i]);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kGreen,
                        child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      title: Text(u['name'] ?? 'User'),
                      subtitle: Text('@${u['username'] ?? ''}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      trailing: isAdmin ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: const Text('Admin', style: TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold))) : null);
                  }))),
              // Leave group button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.exit_to_app_rounded, color: Colors.red),
                    label: const Text('Leave Group', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
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
