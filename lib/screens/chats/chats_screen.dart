import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../widgets/chat_tile.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
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
  bool get isDark => Theme.of(context).brightness == Brightness.dark;


  late final String _myUid;
  final _searchCtrl  = TextEditingController();
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

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(kSheetRadius))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4,
            decoration: BoxDecoration(
              color: isDark ? kTextTertiary : kLightTextSub,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: kAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.person_rounded, color: kAccent, size: 22)),
            title: Text('New Message',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15,
                color: isDark ? kTextPrimary : kLightText)),
            subtitle: Text('Start a DM with a friend',
              style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const FriendsScreen(startChat: true)));
            }),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: kAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.group_add_rounded, color: kAccent, size: 22)),
            title: Text('New Group',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15,
                color: isDark ? kTextPrimary : kLightText)),
            subtitle: Text('Create a group chat',
              style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
            }),
          const SizedBox(height: 16),
        ])));
  }

  void _showProfileMenu(BuildContext context) {
    final myUid = _myUid;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? kCard : kLightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: isDark ? kTextTertiary : kLightTextSub,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          // Profile row header
          FutureBuilder<DocumentSnapshot>(
            future: db.collection('users').doc(myUid).get(),
            builder: (_, snap) {
              final data = snap.data?.data() as Map<String, dynamic>? ?? {};
              final name = data['name'] as String? ?? 'You';
              final username = data['username'] as String? ?? '';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: CircleAvatar(
                  radius: 24, backgroundColor: kAccent,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.bold))),
                title: Text(name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16,
                    color: isDark ? kTextPrimary : kLightText)),
                subtitle: Text('@$username',
                  style: TextStyle(
                    color: isDark ? kTextSecondary : kLightTextSub,
                    fontSize: 13)),
                trailing: Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: isDark ? kTextSecondary : kLightTextSub),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ProfileScreen(uid: myUid)));
                });
            }),
          Divider(color: isDark ? kDivider : kLightDivider, height: 1),
          const SizedBox(height: 6),
          _menuTile(context, Icons.inbox_rounded, 'Message Requests',
            isDark ? kTextSecondary : kLightTextSub, () {
              Navigator.pop(context);
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MessageRequestsScreen()));
            }),
          _menuTile(context, Icons.block_rounded, 'Blocked Users',
            isDark ? kTextSecondary : kLightTextSub, () {
              Navigator.pop(context);
              // Navigate to blocked users via profile settings
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => ProfileScreen(uid: myUid)));
            }),
          _menuTile(context, Icons.settings_rounded, 'Settings',
            isDark ? kTextSecondary : kLightTextSub, () {
              Navigator.pop(context);
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
          const SizedBox(height: 6),
          Divider(color: isDark ? kDivider : kLightDivider, height: 1),
          const SizedBox(height: 6),
          _menuTile(context, Icons.logout_rounded, 'Sign Out',
            kRed, () async {
              Navigator.pop(context);
              await auth.signOut();
            }),
          const SizedBox(height: 12),
        ])));
  }

  Widget _menuTile(BuildContext context, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20)),
      title: Text(label,
        style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500,
          color: isDark ? kTextPrimary : kLightText)),
      onTap: onTap);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Chats',
          style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold,
            color: isDark ? kTextPrimary : kLightText)),
        actions: [
          // Message requests badge
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('message_requests')
              .where('to', isEqualTo: _myUid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
            builder: (_, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(children: [
                IconButton(
                  icon: Icon(Icons.inbox_rounded,
                    size: 22, color: isDark ? kTextSecondary : kLightTextSub),
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(
                      builder: (_) => const MessageRequestsScreen()))),
                if (count > 0)
                  Positioned(right: 6, top: 6,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(
                        color: kRed, shape: BoxShape.circle),
                      child: Center(child: Text('$count',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 9,
                          fontWeight: FontWeight.bold))))),
              ]);
            }),
          // Profile icon
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FutureBuilder<DocumentSnapshot>(
              future: db.collection('users').doc(_myUid).get(),
              builder: (_, snap) {
                final data = snap.data?.data() as Map<String, dynamic>? ?? {};
                final name = data['name'] as String? ?? 'U';
                return GestureDetector(
                  onTap: () => _showProfileMenu(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: kAccent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: kAccent.withOpacity(0.3),
                        blurRadius: 8, offset: const Offset(0, 2))]),
                    child: Center(child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.bold)))));
              })),
        ]),
      body: Column(children: [
        // ── Search + inbox row ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? kCard : kLightCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? kDivider : kLightDivider, width: 0.5)),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              style: TextStyle(fontSize: 14, color: isDark ? kTextPrimary : kLightText),
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                  color: isDark ? kTextSecondary : kLightTextSub, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: isDark ? kTextSecondary : kLightTextSub,
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      })
                  : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13))))),

        // ── Chat list ──────────────────────────────────────────────────────
        Expanded(child: _CombinedChatList(
          myUid: _myUid, searchQuery: _searchQuery)),
      ]),

      floatingActionButton: FloatingActionButton(
        backgroundColor: kAccent, elevation: 2,
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
    // ── Outer stream: pending message-requests to ME ───────────────────────
    // Any chatId in here should NOT appear in the main chat list
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('message_requests')
        .where('to', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending')
        .snapshots(),
      builder: (_, reqSnap) {
        final pendingChatIds = {
          for (final d in (reqSnap.data?.docs ?? []))
            ((d.data() as Map)['chatId'] as String? ?? d.id)
        };

        return StreamBuilder<QuerySnapshot>(
          stream: db.collection('chats')
            .where('participants', arrayContains: myUid).snapshots(),
          builder: (_, dmSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: db.collection('groups')
                .where('members', arrayContains: myUid).snapshots(),
              builder: (_, grpSnap) {
                if (!dmSnap.hasData || !grpSnap.hasData) {
                  return const Center(child: CircularProgressIndicator(
                    color: kAccent, strokeWidth: 2));
                }

                final List<Map<String, dynamic>> items = [];

                for (final doc in dmSnap.data!.docs) {
                  // Hide chats that are still pending requests
                  if (pendingChatIds.contains(doc.id)) continue;
                  final d = doc.data() as Map<String, dynamic>;
                  final participants =
                    List<String>.from(d['participants'] ?? []);
                  final otherUid = participants.firstWhere(
                    (u) => u != myUid, orElse: () => '');
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
                        return (item['nameLower'] as String)
                          .contains(searchQuery);
                      }
                      return true;
                    }).toList();

                if (filtered.isEmpty) {
                  return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 36, color: kAccent)),
                    const SizedBox(height: 20),
                    Text('No chats yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                        color: isDark ? kTextPrimary : kLightText)),
                    const SizedBox(height: 8),
                    Text('Tap the pencil button to start a conversation',
                      style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13),
                      textAlign: TextAlign.center),
                  ]));
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(top: 4, bottom: 80),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                    Divider(height: 0, indent: 76, color: isDark ? kDivider : kLightDivider),
                  itemBuilder: (_, i) {
                    final item = filtered[i];

                    if (item['type'] == 'dm') {
                      return ChatTile(
                        chatData: item['data'],
                        otherUid: item['otherUid'],
                        myUid: myUid,
                        chatId: item['id']);
                    }

                    // ── Group tile ──────────────────────────────────────────
                    final d          = item['data'] as Map<String, dynamic>;
                    final unread     = (d['unread_$myUid'] ?? 0) as int;
                    final lastTs     = d['lastTimestamp'] as Timestamp?;
                    final lastMsg    = d['lastMessage']   as String? ?? 'Group created';
                    final lastSender = d['lastSenderName'] as String?;
                    final groupName  = d['name'] ?? 'Group';

                    return InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => GroupChatScreen(
                          groupId: item['id'], groupName: groupName))),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                        child: Row(children: [
                          Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.15),
                              shape: BoxShape.circle),
                            child: const Icon(Icons.group_rounded,
                              color: kAccent, size: 26)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Row(children: [
                              Expanded(child: Text(groupName,
                                style: TextStyle(
                                  fontWeight: unread > 0
                                    ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15, color: isDark ? kTextPrimary : kLightText),
                                overflow: TextOverflow.ellipsis)),
                              Text(_timeAgo(lastTs),
                                style: TextStyle(
                                  color: unread > 0 ? kAccent : isDark ? kTextSecondary : kLightTextSub,
                                  fontSize: 12,
                                  fontWeight: unread > 0
                                    ? FontWeight.w600 : FontWeight.normal)),
                            ]),
                            const SizedBox(height: 3),
                            Row(children: [
                              Expanded(child: Text(
                                lastSender != null
                                  ? '$lastSender: $lastMsg' : lastMsg,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: unread > 0 ? isDark ? kTextPrimary : kLightText : kTextSecondary,
                                  fontSize: 13,
                                  fontWeight: unread > 0
                                    ? FontWeight.w500 : FontWeight.normal))),
                              if (unread > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: kAccent,
                                    borderRadius: BorderRadius.circular(10)),
                                  child: Text('$unread',
                                    style: const TextStyle(
                                      color: Colors.white, fontSize: 11,
                                      fontWeight: FontWeight.bold))),
                              ],
                            ]),
                          ])),
                        ])));
                  });
              });
          });
      });
  }
}
