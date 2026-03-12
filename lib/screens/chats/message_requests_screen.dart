import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import 'chat_screen.dart';

class MessageRequestsScreen extends StatelessWidget {
  const MessageRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myUid  = auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        title: const Text('Message Requests',
          style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('message_requests')
          .where('to', isEqualTo: myUid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: kAccent, strokeWidth: 2));

          final docs = [...snap.data!.docs];
          docs.sort((a, b) {
            final aTs = (a.data() as Map)['timestamp'] as Timestamp?;
            final bTs = (b.data() as Map)['timestamp'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

          if (docs.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.inbox_rounded, size: 36, color: kAccent)),
              const SizedBox(height: 16),
              Text('No message requests',
                style: TextStyle(
                  color: isDark ? kTextPrimary : kLightText,
                  fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Text('Requests from people you don\'t know appear here',
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13),
                textAlign: TextAlign.center),
            ]));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
              Divider(height: 0, indent: 72,
                color: isDark ? kDivider : kLightDivider),
            itemBuilder: (_, i) {
              final doc     = docs[i];
              final d       = doc.data() as Map<String, dynamic>;
              final fromUid = d['from']       as String? ?? '';
              final chatId  = d['chatId']     as String? ?? doc.id;
              final name    = d['fromName']   as String? ?? 'User';
              final avatar  = d['fromAvatar'] as String? ?? 'U';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.18),
                    shape: BoxShape.circle),
                  child: Center(child: Text(avatar,
                    style: const TextStyle(
                      color: kAccent, fontWeight: FontWeight.bold,
                      fontSize: 16)))),
                title: Text(name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? kTextPrimary : kLightText)),
                subtitle: Text(
                  d['lastMessage'] ?? 'Wants to send you a message',
                  style: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _RequestPreviewScreen(
                    requestDoc: doc,
                    fromUid:   fromUid,
                    fromName:  name,
                    fromAvatar: avatar,
                    chatId:    chatId,
                    myUid:     myUid))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () => _accept(context, doc, d, myUid, chatId),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: kAccent.withOpacity(0.15),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                        color: kAccent, size: 22))),
                  const SizedBox(width: 8),
                  // DELETE the doc — not update status
                  GestureDetector(
                    onTap: () => doc.reference.delete(),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: kRed.withOpacity(0.12),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
                        color: kRed, size: 22))),
                ]));
            });
        }));
  }

  Future<void> _accept(
    BuildContext context,
    DocumentSnapshot doc,
    Map<String, dynamic> d,
    String myUid,
    String chatId,
  ) async {
    final fromUid = d['from'] as String? ?? '';
    final batch = db.batch();
    batch.delete(doc.reference); // remove request doc
    batch.set(
      db.collection('users').doc(myUid).collection('friends').doc(fromUid),
      {'uid': fromUid, 'since': FieldValue.serverTimestamp()});
    batch.set(
      db.collection('users').doc(fromUid).collection('friends').doc(myUid),
      {'uid': myUid, 'since': FieldValue.serverTimestamp()});
    batch.update(db.collection('users').doc(myUid),
      {'friendCount': FieldValue.increment(1)});
    batch.update(db.collection('users').doc(fromUid),
      {'friendCount': FieldValue.increment(1)});
    await batch.commit();
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUid:    fromUid,
          otherName:   d['fromName']   ?? 'User',
          otherAvatar: d['fromAvatar'] ?? 'U',
          chatId:      chatId)));
    }
  }
}

// ── Read-only preview ────────────────────────────────────────────────────────
class _RequestPreviewScreen extends StatelessWidget {
  final DocumentSnapshot requestDoc;
  final String fromUid, fromName, fromAvatar, chatId, myUid;
  const _RequestPreviewScreen({
    required this.requestDoc,
    required this.fromUid,
    required this.fromName,
    required this.fromAvatar,
    required this.chatId,
    required this.myUid,
  });

  Future<void> _accept(BuildContext context) async {
    final batch = db.batch();
    batch.delete(requestDoc.reference);
    batch.set(
      db.collection('users').doc(myUid).collection('friends').doc(fromUid),
      {'uid': fromUid, 'since': FieldValue.serverTimestamp()});
    batch.set(
      db.collection('users').doc(fromUid).collection('friends').doc(myUid),
      {'uid': myUid, 'since': FieldValue.serverTimestamp()});
    batch.update(db.collection('users').doc(myUid),
      {'friendCount': FieldValue.increment(1)});
    batch.update(db.collection('users').doc(fromUid),
      {'friendCount': FieldValue.increment(1)});
    await batch.commit();
    if (context.mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUid:    fromUid,
          otherName:   fromName,
          otherAvatar: fromAvatar,
          chatId:      chatId)));
    }
  }

  Future<void> _decline(BuildContext context) async {
    await requestDoc.reference.delete();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        title: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.2), shape: BoxShape.circle),
            child: Center(child: Text(fromAvatar,
              style: const TextStyle(
                color: kAccent, fontWeight: FontWeight.bold, fontSize: 15)))),
          const SizedBox(width: 10),
          Text(fromName,
            style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15)),
        ])),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: kAccent.withOpacity(0.08),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Icon(Icons.lock_outline_rounded, color: kAccent, size: 13),
            SizedBox(width: 6),
            Text('Accept to reply. Messages shown below.',
              style: TextStyle(color: kAccent, fontSize: 12)),
          ])),

        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: db.collection('chats').doc(chatId)
            .collection('messages').orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (snap.hasError || !snap.hasData) return const Center(
              child: CircularProgressIndicator(color: kAccent, strokeWidth: 2));
            final msgs = snap.data!.docs;
            if (msgs.isEmpty) return Center(
              child: Text('No messages yet',
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub)));
            return ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m    = msgs[i].data() as Map<String, dynamic>;
                final isMe = m['senderId'] == myUid;
                return Align(
                  alignment: isMe
                    ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72),
                    decoration: BoxDecoration(
                      color: isMe ? kAccent : isDark ? kCard : kLightCard,
                      borderRadius: BorderRadius.circular(16)),
                    child: Text(m['text'] ?? '',
                      style: TextStyle(
                        color: isMe
                          ? Colors.white
                          : isDark ? kTextPrimary : kLightText,
                        fontSize: 14))));
              });
          })),

        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          decoration: BoxDecoration(
            color: isDark ? kCard : kLightCard,
            border: Border(top: BorderSide(
              color: isDark ? kDivider : kLightDivider, width: 0.5))),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kRed.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              onPressed: () => _decline(context),
              child: const Text('Decline',
                style: TextStyle(
                  color: kRed, fontWeight: FontWeight.w600)))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent, elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              onPressed: () => _accept(context),
              child: const Text('Accept',
                style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)))),
          ])),
      ]));
  }
}
