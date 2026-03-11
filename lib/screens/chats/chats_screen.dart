import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../widgets/chat_tile.dart';
import '../friends/friends_screen.dart';
import 'chat_screen.dart';
import 'message_requests_screen.dart';
import 'group_chat_screen.dart';
import 'create_group_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    _myUid = auth.currentUser!.uid;
  }

  void _showNewChatOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person_rounded, color: kGreen),
            ),
            title: const Text('New Message',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Start a DM with a friend'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FriendsScreen(startChat: true)));
            },
          ),
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.group_add_rounded, color: kGreen),
            ),
            title: const Text('New Group',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Create a group chat'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white,
        elevation: 0,
        title: const Text('Chats',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('message_requests')
                .where('to', isEqualTo: _myUid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (_, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(children: [
                IconButton(
                  icon: const Icon(Icons.inbox_rounded),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MessageRequestsScreen())),
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: Center(
                        child: Text('$count',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ]);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGreen,
        onPressed: _showNewChatOptions,
        child: const Icon(Icons.edit_rounded, color: Colors.white),
      ),
      body: _CombinedChatList(myUid: _myUid),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Combined DM + Group list, sorted by lastTimestamp
// ─────────────────────────────────────────────────────────────────────────────
class _CombinedChatList extends StatelessWidget {
  final String myUid;
  const _CombinedChatList({required this.myUid});

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('chats')
          .where('participants', arrayContains: myUid)
          .snapshots(),
      builder: (_, dmSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: db
              .collection('groups')
              .where('members', arrayContains: myUid)
              .snapshots(),
          builder: (_, grpSnap) {
            if (!dmSnap.hasData || !grpSnap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: kGreen));
            }

            final List<Map<String, dynamic>> items = [];

            // DMs
            for (final doc in dmSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>;
              final participants =
                  List<String>.from(d['participants'] ?? []);
              final otherUid = participants.firstWhere(
                  (u) => u != myUid,
                  orElse: () => '');
              if (otherUid.isEmpty) continue;
              items.add({
                'type': 'dm',
                'id': doc.id,
                'otherUid': otherUid,
                'lastTimestamp': d['lastTimestamp'],
                'data': d,
              });
            }

            // Groups
            for (final doc in grpSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>;
              items.add({
                'type': 'group',
                'id': doc.id,
                'data': d,
                'lastTimestamp': d['lastTimestamp'],
              });
            }

            // Sort by lastTimestamp descending
            items.sort((a, b) {
              final aTs = a['lastTimestamp'] as Timestamp?;
              final bTs = b['lastTimestamp'] as Timestamp?;
              if (aTs == null && bTs == null) return 0;
              if (aTs == null) return 1;
              if (bTs == null) return -1;
              return bTs.compareTo(aTs);
            });

            if (items.isEmpty) {
              return Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded,
                          size: 64, color: kGreen),
                      const SizedBox(height: 16),
                      const Text('No chats yet',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Tap ✏️ to start a conversation',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 13)),
                    ]),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(
                  height: 0,
                  indent: 72,
                  color: Colors.grey.withOpacity(0.08)),
              itemBuilder: (_, i) {
                final item = items[i];

                if (item['type'] == 'dm') {
                  return ChatTile(
                    chatData: item['data'],
                    otherUid: item['otherUid'],
                    myUid: myUid,
                    chatId: item['id'],
                  );
                }

                // ── Group tile ────────────────────────────────────────
                final d = item['data'] as Map<String, dynamic>;
                final unread = (d['unread_$myUid'] ?? 0) as int;
                final lastTs = d['lastTimestamp'] as Timestamp?;
                final lastMsg = d['lastMessage'] as String? ?? 'Group created';
                final lastSender = d['lastSenderName'] as String?;

                return GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => GroupChatScreen(
                        groupId: item['id'],
                        groupName: d['name'] ?? 'Group')));
                  },
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      radius: 26,
                      backgroundColor: kGreen.withOpacity(0.18),
                      child:
                          const Icon(Icons.group_rounded, color: kGreen, size: 28),
                    ),
                    title: Row(children: [
                      Expanded(
                        child: Text(d['name'] ?? 'Group',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      Text(_timeAgo(lastTs),
                          style: TextStyle(
                              color: unread > 0 ? kGreen : Colors.grey[500],
                              fontSize: 12,
                              fontWeight: unread > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ]),
                    subtitle: Row(children: [
                      Expanded(
                        child: Text(
                          lastSender != null
                              ? '$lastSender: $lastMsg'
                              : lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: unread > 0
                                  ? Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color
                                  : Colors.grey[500],
                              fontSize: 13,
                              fontWeight: unread > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: kGreen,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('$unread',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ]),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
