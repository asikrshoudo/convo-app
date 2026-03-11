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
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _myUid = auth.currentUser!.uid;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          const SizedBox(height: 8),
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.person_rounded, color: kGreen, size: 22)),
            title: const Text('New Message',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: Text('Start a DM with a friend',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen(startChat: true)));
            }),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.group_add_rounded, color: kGreen, size: 22)),
            title: const Text('New Group',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: Text('Create a group chat',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
            }),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : const Color(0xFFF5F5F5),
      body: Column(children: [
        // ── Search + inbox row ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? kCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200)),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search chats...',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: Colors.grey[500], size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: Colors.grey[500],
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          })
                      : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            StreamBuilder<QuerySnapshot>(
              stream: db.collection('message_requests')
                .where('to', isEqualTo: _myUid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
              builder: (_, snap) {
                final count = snap.data?.docs.length ?? 0;
                return Stack(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? kCard : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade200)),
                    child: IconButton(
                      icon: const Icon(Icons.inbox_rounded, size: 20),
                      onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const MessageRequestsScreen())))),
                  if (count > 0)
                    Positioned(
                      right: 4, top: 4,
                      child: Container(
                        width: 14, height: 14,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Center(
                          child: Text('$count',
                            style: const TextStyle(
                              color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))))),
                ]);
              }),
          ]),
        ),

        // ── List ─────────────────────────────────────────────────────────────
        Expanded(child: _CombinedChatList(myUid: _myUid, searchQuery: _searchQuery)),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGreen,
        elevation: 2,
        onPressed: _showNewChatOptions,
        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _CombinedChatList extends StatelessWidget {
  final String myUid;
  final String searchQuery;
  const _CombinedChatList({required this.myUid, required this.searchQuery});

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1)  return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24)   return '${d.inHours}h';
    if (d.inDays < 7)     return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('chats').where('participants', arrayContains: myUid).snapshots(),
      builder: (_, dmSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: db.collection('groups').where('members', arrayContains: myUid).snapshots(),
          builder: (_, grpSnap) {
            if (!dmSnap.hasData || !grpSnap.hasData) {
              return const Center(child: CircularProgressIndicator(color: kGreen));
            }

            final List<Map<String, dynamic>> items = [];

            for (final doc in dmSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>;
              final participants = List<String>.from(d['participants'] ?? []);
              final otherUid = participants.firstWhere((u) => u != myUid, orElse: () => '');
              if (otherUid.isEmpty) continue;
              items.add({
                'type': 'dm', 'id': doc.id,
                'otherUid': otherUid,
                'lastTimestamp': d['lastTimestamp'],
                'data': d,
              });
            }

            for (final doc in grpSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>;
              items.add({
                'type': 'group', 'id': doc.id, 'data': d,
                'lastTimestamp': d['lastTimestamp'],
                'nameLower': (d['name'] ?? '').toString().toLowerCase(),
              });
            }

            items.sort((a, b) {
              final aTs = a['lastTimestamp'] as Timestamp?;
              final bTs = b['lastTimestamp'] as Timestamp?;
              if (aTs == null && bTs == null) return 0;
              if (aTs == null) return 1;
              if (bTs == null) return -1;
              return bTs.compareTo(aTs);
            });

            final filtered = searchQuery.isEmpty
              ? items
              : items.where((item) {
                  if (item['type'] == 'group') {
                    return (item['nameLower'] as String).contains(searchQuery);
                  }
                  return true;
                }).toList();

            if (filtered.isEmpty) {
              return Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: kGreen.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 36, color: kGreen)),
                  const SizedBox(height: 20),
                  const Text('No chats yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Tap the pencil button to start a conversation',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    textAlign: TextAlign.center),
                ]));
            }

            return ListView.separated(
              padding: const EdgeInsets.only(top: 4, bottom: 80),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => Divider(
                height: 0, indent: 76,
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200),
              itemBuilder: (_, i) {
                final item = filtered[i];

                if (item['type'] == 'dm') {
                  return ChatTile(
                    chatData: item['data'],
                    otherUid: item['otherUid'],
                    myUid: myUid,
                    chatId: item['id']);
                }

                // ── Group tile ────────────────────────────────────────────────
                final d          = item['data'] as Map<String, dynamic>;
                final unread     = (d['unread_$myUid'] ?? 0) as int;
                final lastTs     = d['lastTimestamp'] as Timestamp?;
                final lastMsg    = d['lastMessage'] as String? ?? 'Group created';
                final lastSender = d['lastSenderName'] as String?;
                final groupName  = d['name'] ?? 'Group';

                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => GroupChatScreen(
                      groupId: item['id'], groupName: groupName))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          color: kGreen.withOpacity(0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.group_rounded, color: kGreen, size: 26)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(groupName,
                              style: TextStyle(
                                fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w600,
                                fontSize: 15),
                              overflow: TextOverflow.ellipsis)),
                          Text(_timeAgo(lastTs),
                            style: TextStyle(
                              color: unread > 0 ? kGreen : Colors.grey[500],
                              fontSize: 12,
                              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          Expanded(
                            child: Text(
                              lastSender != null ? '$lastSender: $lastMsg' : lastMsg,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unread > 0
                                  ? (isDark ? Colors.white70 : Colors.black87)
                                  : Colors.grey[500],
                                fontSize: 13,
                                fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal))),
                          if (unread > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: kGreen, borderRadius: BorderRadius.circular(10)),
                              child: Text('$unread',
                                style: const TextStyle(
                                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                          ],
                        ]),
                      ])),
                    ])));
              });
          });
      });
  }
}
