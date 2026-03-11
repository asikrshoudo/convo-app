import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../profile/profile_screen.dart';
import 'chat_screen.dart';

class MessageRequestsScreen extends StatelessWidget {
  const MessageRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = auth.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Requests')),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('message_requests')
          .where('to', isEqualTo: myUid)
          .where('status', isEqualTo: 'pending')
          .orderBy('timestamp', descending: true).snapshots(),
        builder: (_, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.inbox_rounded,
                  size: 36, color: kAccent)),
              const SizedBox(height: 16),
              const Text('No message requests',
                style: TextStyle(
                  color: kTextPrimary, fontSize: 16,
                  fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              const Text('Requests from people you don\'t know appear here',
                style: TextStyle(color: kTextSecondary, fontSize: 13),
                textAlign: TextAlign.center),
            ]));
          }
          return ListView.separated(
            itemCount: snap.data!.docs.length,
            separatorBuilder: (_, __) =>
              const Divider(height: 0, indent: 72, color: kDivider),
            itemBuilder: (_, i) {
              final doc = snap.data!.docs[i];
              final d = doc.data() as Map<String, dynamic>;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.18),
                    shape: BoxShape.circle),
                  child: Center(
                    child: Text(d['fromAvatar'] ?? 'U',
                      style: const TextStyle(
                        color: kAccent, fontWeight: FontWeight.bold,
                        fontSize: 16)))),
                title: Text(d['fromName'] ?? 'User',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600, color: kTextPrimary)),
                subtitle: Text(
                  d['lastMessage'] ?? 'Wants to send you a message',
                  style: const TextStyle(color: kTextSecondary, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () async {
                      await db.collection('message_requests')
                        .doc(doc.id).update({'status': 'accepted'});
                      await db.collection('users').doc(myUid)
                        .collection('friends').doc(d['from'])
                        .set({'uid': d['from'],
                              'since': FieldValue.serverTimestamp()});
                      await db.collection('users').doc(d['from'])
                        .collection('friends').doc(myUid)
                        .set({'uid': myUid,
                              'since': FieldValue.serverTimestamp()});
                      final ids = [myUid, d['from'] as String]..sort();
                      final chatId = ids.join('_');
                      if (context.mounted) Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ChatScreen(
                          otherUid: d['from'],
                          otherName: d['fromName'] ?? 'User',
                          otherAvatar: d['fromAvatar'] ?? 'U',
                          chatId: chatId)));
                    },
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: kAccent.withOpacity(0.15),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                        color: kAccent, size: 22))),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => db.collection('message_requests')
                      .doc(doc.id).update({'status': 'declined'}),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: kRed.withOpacity(0.12),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
                        color: kRed, size: 22))),
                ]),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(uid: d['from']))));
            });
        }));
  }
}
