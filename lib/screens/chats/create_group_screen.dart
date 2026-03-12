import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;


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
        const SnackBar(content: Text('Enter a group name'),
          backgroundColor: kRed));
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
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        backgroundColor: isDark ? kDark : kLightBg,
        elevation: 0,
        title: const Text('New Group'),
        actions: [
          _creating
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                    color: kAccent, strokeWidth: 2)))
            : TextButton(
                onPressed: _create,
                child: const Text('Create',
                  style: TextStyle(
                    color: kAccent, fontWeight: FontWeight.bold, fontSize: 16))),
        ]),
      body: Column(children: [
        // Group name input
        Container(
          color: isDark ? kCard : kLightCard,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: kAccent.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.group_rounded, color: kAccent)),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: _nameCtrl,
              style: TextStyle(
                color: isDark ? kTextPrimary : kLightText, fontSize: 16, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Group name',
                hintStyle: TextStyle(color: isDark ? kTextSecondary : kLightTextSub),
                border: InputBorder.none))),
          ])),

        // Selected count bar
        if (_selected.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: kAccent.withOpacity(0.08),
            child: Row(children: [
              const Icon(Icons.people_rounded, color: kAccent, size: 16),
              const SizedBox(width: 6),
              Text('${_selected.length} selected',
                style: const TextStyle(
                  color: kAccent, fontSize: 13, fontWeight: FontWeight.w500)),
            ])),

        Divider(height: 0, color: isDark ? kDivider : kLightDivider),

        // Friends list
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: kAccent, strokeWidth: 2))
          : _friends.isEmpty
            ? Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.people_outline_rounded,
                    size: 32, color: kAccent)),
                const SizedBox(height: 12),
                Text('No friends yet',
                  style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
              ]))
            : ListView.builder(
                itemCount: _friends.length,
                itemBuilder: (_, i) {
                  final f = _friends[i];
                  final uid = f['uid'] as String;
                  final selected = _selected.contains(uid);
                  return ListTile(
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: kAccent.withOpacity(0.18),
                        shape: BoxShape.circle),
                      child: Center(
                        child: Text(f['avatar'] ?? '?',
                          style: const TextStyle(
                            color: kAccent,
                            fontWeight: FontWeight.bold, fontSize: 16)))),
                    title: Text(f['name'] ?? 'User',
                      style: TextStyle(
                        color: isDark ? kTextPrimary : kLightText, fontWeight: FontWeight.w600)),
                    subtitle: Text('@${f['username'] ?? ''}',
                      style: TextStyle(
                        color: isDark ? kTextSecondary : kLightTextSub, fontSize: 12)),
                    trailing: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? kAccent : Colors.transparent,
                        border: Border.all(
                          color: selected ? kAccent : isDark ? kTextSecondary : kLightTextSub,
                          width: 2)),
                      child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16)
                        : null),
                    onTap: () => setState(() {
                      if (selected) _selected.remove(uid);
                      else _selected.add(uid);
                    }));
                })),
      ]));
  }
}
