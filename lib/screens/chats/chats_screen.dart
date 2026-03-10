import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../widgets/chat_tile.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import 'message_requests_screen.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid  = auth.currentUser!.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white, elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: myUid))),
          child: Padding(padding: const EdgeInsets.all(8),
            child: StreamBuilder<DocumentSnapshot>(
              stream: db.collection('users').doc(myUid).snapshots(),
              builder: (_, snap) {
                final name = snap.data?.get('name') as String? ?? 'U';
                return CircleAvatar(backgroundColor: kGreen,
                  child: Text(name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));
              }))),
        title: const Text('Convo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          // Message requests with unread badge
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('message_requests')
              .where('to', isEqualTo: myUid)
              .where('status', isEqualTo: 'pending').snapshots(),
            builder: (_, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(children: [
                IconButton(
                  icon: const Icon(Icons.inbox_rounded),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MessageRequestsScreen()))),
                if (count > 0) Positioned(right: 6, top: 6, child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Center(child: Text('$count',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))))),
              ]);
            }),
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FriendsScreen(startChat: true)))),
        ]),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('chats').where('participants', arrayContains: myUid).snapshots(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: kGreen));
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 80, height: 80,
                decoration: BoxDecoration(color: kGreen.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: kGreen)),
              const SizedBox(height: 16),
              const Text('No conversations yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Find friends and start chatting!', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
            ]));
          }

          // Sort by most recent message
          final docs = snap.data!.docs.toList()..sort((a, b) {
            final aTs = (a.data() as Map)['lastTimestamp'];
            final bTs = (b.data() as Map)['lastTimestamp'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as dynamic).compareTo(aTs);
          });

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                Divider(height: 0, color: Colors.grey.withOpacity(0.08), indent: 76),
            itemBuilder: (_, i) {
              final data  = docs[i].data() as Map<String, dynamic>;
              final parts = List<String>.from(data['participants'] ?? []);
              final other = parts.firstWhere((u) => u != myUid, orElse: () => '');
              return ChatTile(chatData: data, otherUid: other, myUid: myUid, chatId: docs[i].id);
            });
        }));
  }
}
