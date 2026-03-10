import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage msg) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);
  runApp(const ConvoApp());
}

const kGreen = Color(0xFF00C853);
const kDark  = Color(0xFF0A0A0A);
const kCard  = Color(0xFF1A1A1A);

// ─── APP ──────────────────────────────────────────────
class ConvoApp extends StatelessWidget {
  const ConvoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Convo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.light),
      darkTheme: ThemeData(
        useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.dark,
        scaffoldBackgroundColor: kDark,
        navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF111111)),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─── SPLASH ───────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => FirebaseAuth.instance.currentUser != null ? const MainScreen() : const LoginScreen(),
      ));
    });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      body: FadeTransition(opacity: _fade, child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(scale: _scale, child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00E676), kGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 54),
          )),
          const SizedBox(height: 24),
          const Text('Convo', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          const Text('powered by TheKami', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ))),
    );
  }
}

// ─── LOGIN ────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  bool _obscure = true, _loading = false;
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kCard : Colors.grey[100]!;
    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.white,
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 52),
          Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00E676), kGreen]), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 28)),
            const SizedBox(width: 12),
            const Text('Convo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 36),
          const Text('Welcome back 👋', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Sign in to continue', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) _errorBox(_error!),
          _inputField('Email', Icons.email_outlined, _emailCtrl, false, isDark, cardBg),
          const SizedBox(height: 14),
          TextField(
            controller: _passCtrl, obscureText: _obscure,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Password', hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
                onPressed: () => setState(() => _obscure = !_obscure)),
              filled: true, fillColor: cardBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          _greenBtn('Sign In', _loading ? null : _signIn, loading: _loading),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: kGreen), minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
            child: const Text('Create Account', style: TextStyle(color: kGreen, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 32),
        ]),
      )),
    );
  }
}

// ─── REGISTER ─────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen> {
  bool _obscure = true, _loading = false;
  String? _error;
  final _nameCtrl     = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _usernameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill all fields'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      
      // Save FCM token
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'name': _nameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'email': _emailCtrl.text.trim(),
        'avatar': _nameCtrl.text.trim()[0].toUpperCase(),
        'verified': false,
        'suggestionsEnabled': true,
        'city': '', 'education': '', 'bio': '',
        'social': {'fb': '', 'instagram': '', 'github': '', 'linkedin': ''},
        'fcmToken': fcmToken ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await cred.user!.updateDisplayName(_nameCtrl.text.trim());
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kCard : Colors.grey[100]!;
    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context))),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Create Account 🎉', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Join Convo today', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) _errorBox(_error!),
          _inputField('Full Name', Icons.person_outline, _nameCtrl, false, isDark, cardBg),
          const SizedBox(height: 14),
          _inputField('Username', Icons.alternate_email, _usernameCtrl, false, isDark, cardBg),
          const SizedBox(height: 14),
          _inputField('Email', Icons.email_outlined, _emailCtrl, false, isDark, cardBg),
          const SizedBox(height: 14),
          TextField(
            controller: _passCtrl, obscureText: _obscure,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Password', hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
                onPressed: () => setState(() => _obscure = !_obscure)),
              filled: true, fillColor: cardBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 24),
          _greenBtn('Create Account', _loading ? null : _register, loading: _loading),
          const SizedBox(height: 32),
        ]),
      )),
    );
  }
}

// ─── MAIN NAV ─────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> {
  int _idx = 0;
  @override
  void initState() {
    super.initState();
    _setupFCM();
  }

  Future<void> _setupFCM() async {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && token != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'fcmToken': token});
    }
    FirebaseMessaging.onMessage.listen((msg) {
      if (!mounted) return;
      final notif = msg.notification;
      if (notif != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${notif.title}: ${notif.body}'),
          backgroundColor: kGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    });
  }

  final _screens = const [ChatsScreen(), FriendsScreen(), ProfileScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        indicatorColor: kGreen.withOpacity(0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble, color: kGreen), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people, color: kGreen), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: kGreen), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings, color: kGreen), label: 'Settings'),
        ],
      ),
    );
  }
}

// ─── CHATS LIST ───────────────────────────────────────
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override State<ChatsScreen> createState() => _ChatsScreenState();
}
class _ChatsScreenState extends State<ChatsScreen> {
  final _myUid = FirebaseAuth.instance.currentUser!.uid;

  String get _initial {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? user?.email ?? 'U';
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white, elevation: 0,
        leading: Padding(padding: const EdgeInsets.all(8),
          child: CircleAvatar(backgroundColor: kGreen,
            child: Text(_initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
        title: const Text('Convo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('chats')
            .where('participants', arrayContains: _myUid)
            .orderBy('lastTimestamp', descending: true)
            .snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text('No conversations yet', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Find friends to start chatting!', style: TextStyle(color: kGreen, fontSize: 14)),
            ]));
          }
          final chats = snap.data!.docs;
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (_, i) {
              final data = chats[i].data() as Map<String, dynamic>;
              final participants = List<String>.from(data['participants'] ?? []);
              final otherUid = participants.firstWhere((u) => u != _myUid, orElse: () => '');
              return _ChatTile(chatData: data, otherUid: otherUid);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGreen,
        child: const Icon(Icons.edit_rounded, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen(startChat: true))),
      ),
    );
  }
}

class _ChatTile extends StatefulWidget {
  final Map<String, dynamic> chatData;
  final String otherUid;
  const _ChatTile({required this.chatData, required this.otherUid});
  @override State<_ChatTile> createState() => _ChatTileState();
}
class _ChatTileState extends State<_ChatTile> {
  Map<String, dynamic>? _user;
  @override
  void initState() {
    super.initState();
    _loadUser();
  }
  Future<void> _loadUser() async {
    if (widget.otherUid.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.otherUid).get();
    if (mounted) setState(() => _user = doc.data());
  }
  @override
  Widget build(BuildContext context) {
    final name = _user?['name'] ?? 'User';
    final avatar = _user?['avatar'] ?? '?';
    final lastMsg = widget.chatData['lastMessage'] ?? '';
    return ListTile(
      leading: CircleAvatar(backgroundColor: kGreen,
        child: Text(avatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(otherUid: widget.otherUid, otherName: name, otherAvatar: avatar),
      )),
    );
  }
}

// ─── CHAT SCREEN ──────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String otherUid, otherName, otherAvatar;
  const ChatScreen({super.key, required this.otherUid, required this.otherName, required this.otherAvatar});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _db        = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  String? _replyToId, _replyToText, _replyToSender;
  bool _showEmoji = false;
  late String _chatId, _myUid;

  static const _emojis = ['😀','😂','❤️','👍','🔥','😭','🙏','😎','🥰','😡','💯','🤔','👀','✅','🎉','😴','💀','🤣','😍','🥲'];

  @override
  void initState() {
    super.initState();
    _myUid = _auth.currentUser!.uid;
    final ids = [_myUid, widget.otherUid]..sort();
    _chatId = ids.join('_');
  }

  Future<void> _sendMessage(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _msgCtrl.clear();
    final reply = _replyToId != null ? {'id': _replyToId, 'text': _replyToText, 'sender': _replyToSender} : null;
    setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; _showEmoji = false; });

    await _db.collection('chats').doc(_chatId).collection('messages').add({
      'text': t,
      'senderId': _myUid,
      'senderName': _auth.currentUser?.displayName ?? 'User',
      'timestamp': FieldValue.serverTimestamp(),
      'deleted': false,
      if (reply != null) 'reply': reply,
    });
    await _db.collection('chats').doc(_chatId).set({
      'participants': [_myUid, widget.otherUid],
      'lastMessage': t,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastSender': _myUid,
    }, SetOptions(merge: true));

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _deleteMessage(String msgId) async {
    await _db.collection('chats').doc(_chatId).collection('messages').doc(msgId)
        .update({'deleted': true, 'text': 'Bu mesaj silindi'});
  }

  void _setReply(String id, String text, String sender) {
    setState(() { _replyToId = id; _replyToText = text; _replyToSender = sender; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white,
        titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          CircleAvatar(radius: 18, backgroundColor: kGreen,
            child: Text(widget.otherAvatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.otherName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Text('tap for profile', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ]),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
        ],
      ),
      body: Column(children: [
        // Messages
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('chats').doc(_chatId).collection('messages')
                .orderBy('timestamp', descending: false).snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kGreen));
              final msgs = snap.data!.docs;
              if (msgs.isEmpty) return Center(child: Text('Say hi to ${widget.otherName}! 👋',
                  style: TextStyle(color: Colors.grey[500])));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
              });
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final data = msgs[i].data() as Map<String, dynamic>;
                  final isMe = data['senderId'] == _myUid;
                  final deleted = data['deleted'] == true;
                  final reply = data['reply'] as Map<String, dynamic>?;
                  return _buildMessage(msgs[i].id, data, isMe, deleted, reply);
                },
              );
            },
          ),
        ),

        // Reply preview
        if (_replyToId != null)
          Container(
            color: isDark ? const Color(0xFF222222) : Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(width: 3, height: 36, color: kGreen),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_replyToSender ?? '', style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ])),
              IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; })),
            ]),
          ),

        // Emoji picker
        if (_showEmoji)
          Container(
            height: 200,
            color: isDark ? kCard : Colors.grey[100],
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 4, crossAxisSpacing: 4),
              itemCount: _emojis.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _sendMessage(_emojis[i]),
                child: Center(child: Text(_emojis[i], style: const TextStyle(fontSize: 24))),
              ),
            ),
          ),

        // Input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? kCard : Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
          ),
          child: Row(children: [
            IconButton(
              icon: Icon(_showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined, color: kGreen),
              onPressed: () => setState(() { _showEmoji = !_showEmoji; }),
            ),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _sendMessage(_msgCtrl.text),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(22)),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildMessage(String id, Map<String, dynamic> data, bool isMe, bool deleted, Map<String, dynamic>? reply) {
    final text = data['text'] ?? '';
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -100 && !deleted) {
          _setReply(id, text, data['senderName'] ?? 'User');
        }
      },
      onLongPress: () {
        if (isMe && !deleted) {
          showDialog(context: context, builder: (_) => AlertDialog(
            title: const Text('Delete message?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(onPressed: () { Navigator.pop(context); _deleteMessage(id); },
                  child: const Text('Delete', style: TextStyle(color: Colors.red))),
            ],
          ));
        }
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: isMe ? kGreen : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(left: BorderSide(color: Colors.white54, width: 3)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(reply['sender'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text(reply['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
              Text(text,
                style: TextStyle(
                  color: deleted ? Colors.white54 : Colors.white,
                  fontSize: 15,
                  fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                )),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── FRIENDS ──────────────────────────────────────────
class FriendsScreen extends StatefulWidget {
  final bool startChat;
  const FriendsScreen({super.key, this.startChat = false});
  @override State<FriendsScreen> createState() => _FriendsScreenState();
}
class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  final _myUid = FirebaseAuth.instance.currentUser!.uid;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }
  @override void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _search(String query) async {
    if (query.isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('users')
          .where('username', isGreaterThanOrEqualTo: query.toLowerCase())
          .where('username', isLessThan: '${query.toLowerCase()}z')
          .limit(10).get();
      setState(() => _results = snap.docs.map((d) => {...d.data(), 'uid': d.id}).toList());
    } finally { setState(() => _searching = false); }
  }

  Future<void> _sendRequest(String toUid, String toName) async {
    final existing = await FirebaseFirestore.instance.collection('friend_requests')
        .where('from', isEqualTo: _myUid).where('to', isEqualTo: toUid).get();
    if (existing.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request already sent!')));
      return;
    }
    final myDoc = await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
    await FirebaseFirestore.instance.collection('friend_requests').add({
      'from': _myUid, 'fromName': myDoc.data()?['name'] ?? 'User',
      'to': toUid, 'toName': toName, 'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request sent to $toName!')));
  }

  Future<void> _acceptRequest(String docId, String fromUid) async {
    await FirebaseFirestore.instance.collection('friend_requests').doc(docId).update({'status': 'accepted'});
    await FirebaseFirestore.instance.collection('users').doc(_myUid).collection('friends').doc(fromUid).set({'uid': fromUid, 'since': FieldValue.serverTimestamp()});
    await FirebaseFirestore.instance.collection('users').doc(fromUid).collection('friends').doc(_myUid).set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
  }

  Future<void> _declineRequest(String docId) async {
    await FirebaseFirestore.instance.collection('friend_requests').doc(docId).update({'status': 'declined'});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kCard : Colors.grey[100]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: kGreen,
          labelColor: kGreen,
          tabs: const [Tab(text: 'Search'), Tab(text: 'Requests'), Tab(text: 'My Friends')],
        ),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        // Search tab
        Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl, onChanged: _search,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Search by username...', hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true, fillColor: cardBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_searching) const CircularProgressIndicator(color: kGreen)
          else Expanded(child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final u = _results[i];
              final isMe = u['uid'] == _myUid;
              return ListTile(
                leading: CircleAvatar(backgroundColor: kGreen,
                  child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                title: Text(u['name'] ?? ''),
                subtitle: Text('@${u['username']}', style: TextStyle(color: Colors.grey[500])),
                trailing: isMe ? const SizedBox() : widget.startChat
                    ? TextButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(otherUid: u['uid'], otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?'))),
                        child: const Text('Message', style: TextStyle(color: kGreen)))
                    : TextButton(
                        onPressed: () => _sendRequest(u['uid'], u['name'] ?? 'User'),
                        child: const Text('Add', style: TextStyle(color: kGreen))),
              );
            },
          )),
        ]),

        // Requests tab
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('friend_requests')
              .where('to', isEqualTo: _myUid).where('status', isEqualTo: 'pending').snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(
              child: Text('No pending requests', style: TextStyle(color: Colors.grey[500])));
            return ListView(children: snap.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(backgroundColor: kGreen,
                  child: Text((data['fromName'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                title: Text(data['fromName'] ?? 'User'),
                subtitle: const Text('wants to be your friend'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.check_circle, color: kGreen),
                      onPressed: () => _acceptRequest(doc.id, data['from'])),
                  IconButton(icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => _declineRequest(doc.id)),
                ]),
              );
            }).toList());
          },
        ),

        // My Friends tab
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(_myUid).collection('friends').snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(
              child: Text('No friends yet. Search to add!', style: TextStyle(color: Colors.grey[500])));
            return ListView(children: snap.data!.docs.map((doc) {
              final friendUid = doc.id;
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(friendUid).get(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const ListTile(title: Text('...'));
                  final u = snap.data!.data() as Map<String, dynamic>? ?? {};
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: kGreen,
                      child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    title: Text(u['name'] ?? 'User'),
                    subtitle: Text('@${u['username'] ?? ''}', style: TextStyle(color: Colors.grey[500])),
                    trailing: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(otherUid: friendUid, otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?'))),
                      child: const Text('Message', style: TextStyle(color: kGreen))),
                  );
                },
              );
            }).toList());
          },
        ),
      ]),
    );
  }
}

// ─── PROFILE ──────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  @override void initState() { super.initState(); _loadUser(); }
  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (mounted) setState(() => _userData = doc.data());
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _userData?['name'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'User';
    final username = _userData?['username'] ?? 'username';
    final initial = name[0].toUpperCase();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _showEditProfile(context))],
      ),
      body: SingleChildScrollView(child: Column(children: [
        Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Container(height: 120, width: double.infinity,
            decoration: BoxDecoration(gradient: LinearGradient(
              colors: [kGreen.withOpacity(0.7), const Color(0xFF004D20)],
              begin: Alignment.topLeft, end: Alignment.bottomRight))),
          Positioned(bottom: -44, child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
              border: Border.all(color: isDark ? kDark : Colors.white, width: 4)),
            child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold))),
          )),
        ]),
        const SizedBox(height: 56),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          if (_userData?['verified'] == true) ...[
            const SizedBox(width: 6),
            const Icon(Icons.verified_rounded, color: kGreen, size: 20),
          ],
        ]),
        const SizedBox(height: 4),
        Text('@$username', style: TextStyle(color: Colors.grey[500])),
        if ((_userData?['bio'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_userData!['bio'], textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 13))),
        ],
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _statCol('0', 'Friends'),
          Container(height: 32, width: 1, color: Colors.grey[800]),
          _statCol('0', 'Chats'),
        ]),
        const SizedBox(height: 32),
      ])),
    );
  }
  Widget _statCol(String val, String label) => Column(children: [
    Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
  ]);
  void _showEditProfile(BuildContext context) {
    final nameCtrl = TextEditingController(text: _userData?['name'] ?? '');
    final bioCtrl  = TextEditingController(text: _userData?['bio'] ?? '');
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: bioCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          _greenBtn('Save', () async {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) return;
            await FirebaseFirestore.instance.collection('users').doc(uid).update({
              'name': nameCtrl.text.trim(), 'bio': bioCtrl.text.trim(),
              'avatar': nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim()[0].toUpperCase() : 'U',
            });
            await FirebaseAuth.instance.currentUser?.updateDisplayName(nameCtrl.text.trim());
            Navigator.pop(context);
            _loadUser();
          }),
        ]),
      ));
  }
}

// ─── SETTINGS ─────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  bool _suggestions = true;
  Map<String, dynamic>? _userData;
  @override void initState() { super.initState(); _loadUser(); }
  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (mounted) setState(() { _userData = doc.data(); _suggestions = doc.data()?['suggestionsEnabled'] ?? true; });
  }
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _userData?['name'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'User';
    final username = _userData?['username'] ?? '';
    final initial = name[0].toUpperCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isDark ? kCard : Colors.grey[100], borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: kGreen,
              child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ])),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
        _section('Preferences'),
        _tile(Icons.notifications_outlined, 'Notifications', 'Manage alerts', () {}),
        _tile(Icons.lock_outline, 'Privacy & Security', 'Control your data', () {}),
        _section('Discovery'),
        SwitchListTile(
          value: _suggestions, onChanged: (val) async {
            setState(() => _suggestions = val);
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) await FirebaseFirestore.instance.collection('users').doc(uid).update({'suggestionsEnabled': val});
          },
          activeColor: kGreen,
          secondary: _iconBox(Icons.person_search_outlined),
          title: const Text('Account Suggestions', style: TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text('Suggest your profile to others', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ),
        _section('About'),
        _tile(Icons.favorite_outline, 'Powered by TheKami', 'thekami.tech', () => launchUrl(Uri.parse('https://thekami.tech'))),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), elevation: 0,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            onPressed: _signOut,
          )),
        const SizedBox(height: 32),
      ]),
    );
  }
  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4)));
  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
    leading: _iconBox(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(sub, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    onTap: onTap,
  );
  Widget _iconBox(IconData icon) => Container(width: 40, height: 40,
    decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: kGreen, size: 20));
}

// ─── HELPERS ──────────────────────────────────────────
Widget _errorBox(String msg) => Container(
  padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.withOpacity(0.3))),
  child: Text(msg, style: const TextStyle(color: Colors.red, fontSize: 13)));

Widget _inputField(String hint, IconData icon, TextEditingController ctrl, bool obscure, bool isDark, Color bg) {
  return TextField(
    controller: ctrl, obscureText: obscure,
    style: TextStyle(color: isDark ? Colors.white : Colors.black),
    decoration: InputDecoration(
      hintText: hint, hintStyle: TextStyle(color: Colors.grey[500]),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true, fillColor: bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
  );
}

Widget _greenBtn(String label, VoidCallback? onTap, {bool loading = false}) {
  return SizedBox(width: double.infinity, height: 54,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      onPressed: onTap,
      child: loading
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ));
}
