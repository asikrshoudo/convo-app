import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _myUid = auth.currentUser!.uid;
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _friends = [];
  bool _loading = false, _creating = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    final snap = await db.collection('users').doc(_myUid).collection('friends').get();
    final friends = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final uDoc = await db.collection('users').doc(doc.id).get();
      if (uDoc.exists) {
        friends.add({...uDoc.data()!, 'uid': doc.id});
      }
    }
    if (mounted) setState(() { _friends = friends; _loading = false; });
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a group name'), backgroundColor: Colors.red));
      return;
    }
    if (_selected.length < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 1 member'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _creating = true);
    try {
      final me = await db.collection('users').doc(_myUid).get();
      final members = [_myUid, ..._selected.toList()];
      final ref = await db.collection('groups').add({
        'name': _nameCtrl.text.trim(),
        'members': members,
        'admins': [_myUid],
        'createdBy': _myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': 'Group created',
        'lastTimestamp': FieldValue.serverTimestamp(),
        'lastSenderName': me.data()?['name'] ?? 'User',
      });
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            groupId: ref.id,
            groupName: _nameCtrl.text.trim())));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white,
        elevation: 0,
        title: const Text('New Group', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          _creating
            ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: kGreen, strokeWidth: 2)))
            : TextButton(
                onPressed: _create,
                child: const Text('Create', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold, fontSize: 16))),
        ]),
      body: Column(children: [
        // Group name input
        Container(
          color: isDark ? kCard : Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: kGreen.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.group_rounded, color: kGreen)),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'Group name',
                hintStyle: TextStyle(color: Colors.grey[500]),
                border: InputBorder.none),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
          ])),

        // Selected count
        if (_selected.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: kGreen.withOpacity(0.08),
            child: Row(children: [
              const Icon(Icons.people_rounded, color: kGreen, size: 16),
              const SizedBox(width: 6),
              Text('${_selected.length} selected', style: const TextStyle(color: kGreen, fontSize: 13, fontWeight: FontWeight.w500)),
            ])),

        // Friends list
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: kGreen))
          : _friends.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[600]),
                const SizedBox(height: 12),
                Text('No friends yet', style: TextStyle(color: Colors.grey[500])),
              ]))
            : ListView.builder(
                itemCount: _friends.length,
                itemBuilder: (_, i) {
                  final f = _friends[i];
                  final uid = f['uid'] as String;
                  final selected = _selected.contains(uid);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kGreen,
                      child: Text(f['avatar'] ?? '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    title: Text(f['name'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('@${f['username'] ?? ''}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    trailing: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? kGreen : Colors.transparent,
                        border: Border.all(color: selected ? kGreen : Colors.grey, width: 2)),
                      child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null),
                    onTap: () => setState(() {
                      if (selected) _selected.remove(uid);
                      else _selected.add(uid);
                    }));
                })),
      ]));
  }
}
