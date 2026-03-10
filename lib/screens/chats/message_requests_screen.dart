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
      appBar: AppBar(title: const Text('Message Requests', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('message_requests')
          .where('to', isEqualTo: myUid)
          .where('status', isEqualTo: 'pending')
          .orderBy('timestamp', descending: true).snapshots(),
        builder: (_, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.inbox_rounded, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 12),
              Text('No message requests', style: TextStyle(color: Colors.grey[500])),
            ]));
          }
          return ListView(children: snap.data!.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return ListTile(
              leading: CircleAvatar(backgroundColor: kGreen,
                child: Text(d['fromAvatar'] ?? 'U',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              title: Text(d['fromName'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(d['lastMessage'] ?? 'Wants to send you a message',
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () async {
                    await db.collection('message_requests').doc(doc.id).update({'status': 'accepted'});
                    await db.collection('users').doc(myUid).collection('friends').doc(d['from'])
                        .set({'uid': d['from'], 'since': FieldValue.serverTimestamp()});
                    await db.collection('users').doc(d['from']).collection('friends').doc(myUid)
                        .set({'uid': myUid, 'since': FieldValue.serverTimestamp()});
                    final ids   = [myUid, d['from'] as String]..sort();
                    final chatId = ids.join('_');
                    if (context.mounted) Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUid: d['from'], otherName: d['fromName'] ?? 'User',
                        otherAvatar: d['fromAvatar'] ?? 'U', chatId: chatId)));
                  },
                  child: Container(width: 38, height: 38,
                    decoration: BoxDecoration(color: kGreen.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: kGreen, size: 22))),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => db.collection('message_requests').doc(doc.id).update({'status': 'declined'}),
                  child: Container(width: 38, height: 38,
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.red, size: 22))),
              ]),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ProfileScreen(uid: d['from']))));
          }).toList());
        }));
  }
}
