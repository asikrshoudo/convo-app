import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

final _db   = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class ConvoApp extends StatelessWidget {
  const ConvoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Convo', debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.light),
    darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.dark,
      scaffoldBackgroundColor: kDark,
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF111111))),
    home: const SplashScreen(),
  );
}

// ─── SPLASH ───────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => _auth.currentUser != null ? const MainScreen() : const LoginScreen()));
    });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kDark,
    body: FadeTransition(opacity: _fade, child: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(scale: _scale, child: Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00E676), kGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))]),
          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 54))),
        const SizedBox(height: 24),
        const Text('Convo', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('powered by TheKami', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]))),
  );
}

// ─── LOGIN ────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  bool _obscure = true, _loading = false, _showPhone = false;
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  String? _error, _verificationId;
  bool _otpSent = false;

  // ── Email Sign In
  Future<void> _signIn() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill all fields'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Login failed');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  // ── Google Sign In
  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final gUser = await GoogleSignIn().signIn();
      if (gUser == null) { setState(() => _loading = false); return; }
      final gAuth = await gUser.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final result = await _auth.signInWithCredential(cred);
      await _ensureUserDoc(result.user!);
      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Google sign-in failed');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  // ── GitHub Sign In
  Future<void> _githubSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final provider = GithubAuthProvider();
      final result = await _auth.signInWithProvider(provider);
      await _ensureUserDoc(result.user!);
      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'GitHub sign-in failed');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  // ── Phone - Send OTP
  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.isEmpty) {
      setState(() => _error = 'Enter phone number'); return;
    }
    setState(() { _loading = true; _error = null; });
    await _auth.verifyPhoneNumber(
      phoneNumber: _phoneCtrl.text.trim(),
      verificationCompleted: (cred) async {
        final result = await _auth.signInWithCredential(cred);
        await _ensureUserDoc(result.user!);
        await _afterLogin();
      },
      verificationFailed: (e) => setState(() { _error = e.message; _loading = false; }),
      codeSent: (verificationId, _) {
        setState(() { _verificationId = verificationId; _otpSent = true; _loading = false; });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  // ── Phone - Verify OTP
  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.isEmpty || _verificationId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!, smsCode: _otpCtrl.text.trim());
      final result = await _auth.signInWithCredential(cred);
      await _ensureUserDoc(result.user!);
      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Invalid OTP');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _ensureUserDoc(User user) async {
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      final name = user.displayName ?? user.email?.split('@').first ?? 'User';
      final fcm  = await FirebaseMessaging.instance.getToken();
      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid, 'name': name,
        'username': name.toLowerCase().replaceAll(' ', '_') + '_${user.uid.substring(0, 4)}',
        'email': user.email ?? '', 'avatar': name[0].toUpperCase(),
        'verified': false, 'suggestionsEnabled': true,
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'social': {'fb': '', 'instagram': '', 'github': '', 'linkedin': ''},
        'fcmToken': fcm ?? '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _afterLogin() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await _db.collection('users').doc(uid).update({'isOnline': true});
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  void _forgotPassword() {
    final ctrl = TextEditingController(text: _emailCtrl.text);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Reset Password'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Your email', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          if (ctrl.text.isNotEmpty) {
            await _auth.sendPasswordResetEmail(email: ctrl.text.trim());
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset email sent! Check inbox.'), backgroundColor: kGreen));
          }
        }, child: const Text('Send', style: TextStyle(color: kGreen))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;
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

          // ── Email/Password section
          if (!_showPhone) ...[
            _field('Email', Icons.email_outlined, _emailCtrl, false, isDark, bg),
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
                filled: true, fillColor: bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
            ),
            Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: _forgotPassword,
                child: const Text('Forgot password?', style: TextStyle(color: kGreen, fontSize: 13)))),
            _greenBtn('Sign In', _loading ? null : _signIn, loading: _loading),
          ],

          // ── Phone section
          if (_showPhone) ...[
            if (!_otpSent) ...[
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: '+880 1XXXXXXXXX', hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.phone_outlined, color: Colors.grey),
                  filled: true, fillColor: bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 14),
              _greenBtn('Send OTP', _loading ? null : _sendOtp, loading: _loading),
            ] else ...[
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Enter OTP code', hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.sms_outlined, color: Colors.grey),
                  filled: true, fillColor: bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 14),
              _greenBtn('Verify OTP', _loading ? null : _verifyOtp, loading: _loading),
              TextButton(onPressed: () => setState(() { _otpSent = false; _verificationId = null; }),
                child: const Text('Resend OTP', style: TextStyle(color: kGreen))),
            ],
          ],

          const SizedBox(height: 12),

          // ── Toggle phone/email
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: kGreen),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: Icon(_showPhone ? Icons.email_outlined : Icons.phone_outlined, color: kGreen, size: 20),
            label: Text(_showPhone ? 'Use Email Instead' : 'Continue with Phone',
              style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600)),
            onPressed: () => setState(() { _showPhone = !_showPhone; _error = null; _otpSent = false; })),

          const SizedBox(height: 20),
          _divider(isDark),
          const SizedBox(height: 16),

          // ── Google
          _socialBtn(
            icon: Icons.g_mobiledata_rounded, iconColor: Colors.red,
            label: 'Continue with Google', isDark: isDark, bg: bg,
            onPressed: _loading ? null : _googleSignIn),
          const SizedBox(height: 12),

          // ── GitHub
          _socialBtn(
            icon: Icons.code_rounded, iconColor: isDark ? Colors.white : Colors.black,
            label: 'Continue with GitHub', isDark: isDark, bg: bg,
            onPressed: _loading ? null : _githubSignIn),

          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text("Don't have an account? ", style: TextStyle(color: Colors.grey[500])),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: const Text('Register', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 32),
        ]),
      )),
    );
  }

  Widget _divider(bool isDark) => Row(children: [
    Expanded(child: Divider(color: Colors.grey[700], thickness: 0.5)),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('or continue with', style: TextStyle(color: Colors.grey[500], fontSize: 13))),
    Expanded(child: Divider(color: Colors.grey[700], thickness: 0.5)),
  ]);

  Widget _socialBtn({required IconData icon, required Color iconColor, required String label,
      required bool isDark, required Color bg, VoidCallback? onPressed}) =>
    SizedBox(width: double.infinity, height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: bg, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey[800]!, width: 0.5))),
        icon: Icon(icon, color: iconColor, size: 26),
        label: Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black,
          fontSize: 15, fontWeight: FontWeight.w600)),
        onPressed: onPressed));
}

// ─── REGISTER ─────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen> {
  bool _obscure = true, _loading = false;
  String? _error;
  String _usernameStatus = ''; // '', 'checking', 'available', 'taken'
  Timer? _debounce;

  final _nameCtrl     = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();

  void _onUsernameChanged(String val) {
    _debounce?.cancel();
    if (val.isEmpty) { setState(() => _usernameStatus = ''); return; }
    setState(() => _usernameStatus = 'checking');
    _debounce = Timer(const Duration(milliseconds: 600), () => _checkUsername(val));
  }

  Future<void> _checkUsername(String username) async {
    final clean = username.trim().toLowerCase();
    if (clean.length < 3) { setState(() => _usernameStatus = 'short'); return; }
    final snap = await _db.collection('users').where('username', isEqualTo: clean).get();
    if (mounted) setState(() => _usernameStatus = snap.docs.isEmpty ? 'available' : 'taken');
  }

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _usernameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill all fields'); return;
    }
    if (_usernameStatus == 'taken') { setState(() => _error = 'Username already taken'); return; }
    if (_usernameStatus != 'available') { setState(() => _error = 'Check username availability'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      final fcm = await FirebaseMessaging.instance.getToken();
      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid, 'name': _nameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'email': _emailCtrl.text.trim(),
        'avatar': _nameCtrl.text.trim()[0].toUpperCase(),
        'verified': false, 'suggestionsEnabled': true,
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'social': {'fb': '', 'instagram': '', 'github': '', 'linkedin': ''},
        'fcmToken': fcm ?? '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await cred.user!.updateDisplayName(_nameCtrl.text.trim());
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Registration failed');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;

    Color usernameColor = Colors.grey;
    IconData usernameIcon = Icons.alternate_email;
    String usernameHint = '';
    if (_usernameStatus == 'checking') { usernameColor = Colors.orange; usernameHint = 'Checking...'; }
    else if (_usernameStatus == 'available') { usernameColor = kGreen; usernameIcon = Icons.check_circle; usernameHint = '✓ Available'; }
    else if (_usernameStatus == 'taken') { usernameColor = Colors.red; usernameIcon = Icons.cancel; usernameHint = '✗ Already taken'; }
    else if (_usernameStatus == 'short') { usernameColor = Colors.orange; usernameHint = 'Min 3 characters'; }

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

          _field('Full Name', Icons.person_outline, _nameCtrl, false, isDark, bg),
          const SizedBox(height: 14),

          // Username field with live check
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _usernameCtrl,
              onChanged: _onUsernameChanged,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Username', hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(usernameIcon, color: usernameColor),
                suffixIcon: _usernameStatus == 'checking'
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)))
                    : null,
                filled: true, fillColor: bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: usernameColor, width: 1.5))),
            ),
            if (usernameHint.isNotEmpty) Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(usernameHint, style: TextStyle(color: usernameColor, fontSize: 12))),
          ]),
          const SizedBox(height: 14),

          _field('Email', Icons.email_outlined, _emailCtrl, false, isDark, bg),
          const SizedBox(height: 14),

          TextField(
            controller: _passCtrl, obscureText: _obscure,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Password (min 6 chars)', hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
                onPressed: () => setState(() => _obscure = !_obscure)),
              filled: true, fillColor: bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 24),
          _greenBtn('Create Account', _loading ? null : _register, loading: _loading),
          const SizedBox(height: 32),
        ]),
      )),
    );
  }
}

// ─── MAIN SCREEN ──────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _idx = 0;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _setOnline(true); _setupFCM(); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _setOnline(false); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState s) => _setOnline(s == AppLifecycleState.resumed);

  Future<void> _setOnline(bool v) async {
    final uid = _auth.currentUser?.uid; if (uid == null) return;
    await _db.collection('users').doc(uid).update({'isOnline': v, 'lastSeen': FieldValue.serverTimestamp()});
  }

  Future<void> _setupFCM() async {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    final uid = _auth.currentUser?.uid;
    if (uid != null && token != null) await _db.collection('users').doc(uid).update({'fcmToken': token});
    FirebaseMessaging.onMessage.listen((msg) {
      if (!mounted) return;
      final n = msg.notification;
      if (n != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${n.title}: ${n.body}'), backgroundColor: kGreen, behavior: SnackBarBehavior.floating));
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser!.uid;
    final screens = [const ChatsScreen(), const FriendsScreen(), ProfileScreen(uid: uid), const SettingsScreen()];
    return Scaffold(
      body: screens[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx, onDestinationSelected: (i) => setState(() => _idx = i),
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

// ─── CHATS ────────────────────────────────────────────
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser!.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white, elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: myUid))),
          child: Padding(padding: const EdgeInsets.all(8),
            child: StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('users').doc(myUid).snapshots(),
              builder: (_, snap) {
                final name = snap.data?.get('name') as String? ?? 'U';
                return CircleAvatar(backgroundColor: kGreen,
                  child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));
              }))),
        title: const Text('Convo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        actions: [
          IconButton(icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen()))),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('chats').where('participants', arrayContains: myUid)
            .orderBy('lastTimestamp', descending: true).snapshots(),
        builder: (_, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text('No conversations yet', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Find friends to start chatting!', style: TextStyle(color: kGreen, fontSize: 14)),
            ]));
          return ListView.builder(
            itemCount: snap.data!.docs.length,
            itemBuilder: (_, i) {
              final data = snap.data!.docs[i].data() as Map<String, dynamic>;
              final parts = List<String>.from(data['participants'] ?? []);
              final other = parts.firstWhere((u) => u != myUid, orElse: () => '');
              return _ChatTile(chatData: data, otherUid: other, myUid: myUid);
            });
        }),
      floatingActionButton: FloatingActionButton(backgroundColor: kGreen,
        child: const Icon(Icons.edit_rounded, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen(startChat: true)))),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chatData;
  final String otherUid, myUid;
  const _ChatTile({required this.chatData, required this.otherUid, required this.myUid});
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot>(
    stream: _db.collection('users').doc(otherUid).snapshots(),
    builder: (_, snap) {
      final u = snap.data?.data() as Map<String, dynamic>? ?? {};
      final name = u['name'] ?? 'User'; final avatar = u['avatar'] ?? '?';
      final online = u['isOnline'] == true;
      final lastMsg = chatData['lastMessage'] ?? '';
      final unread = (chatData['unread_$myUid'] ?? 0) as int;
      return ListTile(
        leading: Stack(children: [
          CircleAvatar(backgroundColor: kGreen, child: Text(avatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          if (online) Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12,
            decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
        ]),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: unread > 0 ? kGreen : Colors.grey[500], fontSize: 13,
            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
        trailing: unread > 0 ? Container(padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
          child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))) : null,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatScreen(otherUid: otherUid, otherName: name, otherAvatar: avatar))),
      );
    });
}

// ─── CHAT SCREEN ──────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String otherUid, otherName, otherAvatar;
  const ChatScreen({super.key, required this.otherUid, required this.otherName, required this.otherAvatar});
  @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _replyToId, _replyToText, _replyToSender;
  bool _showEmoji = false;
  late String _chatId, _myUid;
  static const _emojis = ['😀','😂','❤️','👍','🔥','😭','🙏','😎','🥰','😡','💯','🤔','👀','✅','🎉','😴','💀','🤣','😍','🥲'];

  @override void initState() {
    super.initState(); _myUid = _auth.currentUser!.uid;
    final ids = [_myUid, widget.otherUid]..sort(); _chatId = ids.join('_');
    _clearUnread();
  }

  Future<void> _clearUnread() async => await _db.collection('chats').doc(_chatId).set({'unread_$_myUid': 0}, SetOptions(merge: true));

  Future<void> _send(String text) async {
    final t = text.trim(); if (t.isEmpty) return;
    _msgCtrl.clear();
    final reply = _replyToId != null ? {'id': _replyToId, 'text': _replyToText, 'sender': _replyToSender} : null;
    setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; _showEmoji = false; });
    await _db.collection('chats').doc(_chatId).collection('messages').add({
      'text': t, 'senderId': _myUid, 'senderName': _auth.currentUser?.displayName ?? 'User',
      'timestamp': FieldValue.serverTimestamp(), 'deleted': false,
      if (reply != null) 'reply': reply,
    });
    await _db.collection('chats').doc(_chatId).set({
      'participants': [_myUid, widget.otherUid],
      'lastMessage': t, 'lastTimestamp': FieldValue.serverTimestamp(), 'lastSender': _myUid,
      'unread_${widget.otherUid}': FieldValue.increment(1), 'unread_$_myUid': 0,
    }, SetOptions(merge: true));
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white, titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        title: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: widget.otherUid))),
          child: Row(children: [
            Stack(children: [
              CircleAvatar(radius: 18, backgroundColor: kGreen,
                child: Text(widget.otherAvatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              StreamBuilder<DocumentSnapshot>(
                stream: _db.collection('users').doc(widget.otherUid).snapshots(),
                builder: (_, snap) {
                  if (snap.data?.get('isOnline') != true) return const SizedBox();
                  return Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
                      border: Border.all(color: isDark ? kDark : Colors.white, width: 2))));
                }),
            ]),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.otherName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              StreamBuilder<DocumentSnapshot>(
                stream: _db.collection('users').doc(widget.otherUid).snapshots(),
                builder: (_, snap) {
                  final online = snap.data?.get('isOnline') == true;
                  return Text(online ? 'Online' : 'Offline', style: TextStyle(color: online ? kGreen : Colors.grey, fontSize: 11));
                }),
            ]),
          ])),
      ),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('chats').doc(_chatId).collection('messages').orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kGreen));
            final msgs = snap.data!.docs;
            if (msgs.isEmpty) return Center(child: Text('Say hi to ${widget.otherName}! 👋', style: TextStyle(color: Colors.grey[500])));
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            });
            return ListView.builder(
              controller: _scrollCtrl, padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final data = msgs[i].data() as Map<String, dynamic>;
                final isMe = data['senderId'] == _myUid;
                return _bubble(msgs[i].id, data, isMe);
              });
          })),

        if (_replyToId != null) Container(
          color: isDark ? const Color(0xFF222222) : Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(width: 3, height: 36, color: kGreen), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_replyToSender ?? '', style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.close, size: 16),
              onPressed: () => setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; })),
          ])),

        if (_showEmoji) Container(height: 180, color: isDark ? kCard : Colors.grey[100],
          child: GridView.builder(padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: _emojis.length,
            itemBuilder: (_, i) => GestureDetector(onTap: () => _send(_emojis[i]),
              child: Center(child: Text(_emojis[i], style: const TextStyle(fontSize: 24)))))),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(color: isDark ? kCard : Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
          child: Row(children: [
            IconButton(icon: Icon(_showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined, color: kGreen),
              onPressed: () => setState(() => _showEmoji = !_showEmoji)),
            Expanded(child: TextField(
              controller: _msgCtrl, textCapitalization: TextCapitalization.sentences, onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Message...', hintStyle: TextStyle(color: Colors.grey[500]),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                filled: true, fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
            const SizedBox(width: 8),
            GestureDetector(onTap: () => _send(_msgCtrl.text),
              child: Container(width: 44, height: 44,
                decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(22)),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
          ])),
      ]),
    );
  }

  Widget _bubble(String id, Map<String, dynamic> data, bool isMe) {
    final text = data['text'] ?? ''; final deleted = data['deleted'] == true;
    final reply = data['reply'] as Map<String, dynamic>?;
    return GestureDetector(
      onHorizontalDragEnd: (d) { if (!deleted && (d.primaryVelocity ?? 0) < -100)
        setState(() { _replyToId = id; _replyToText = text; _replyToSender = data['senderName']; }); },
      onLongPress: () { if (isMe && !deleted) showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () { Navigator.pop(context);
            _db.collection('chats').doc(_chatId).collection('messages').doc(id).update({'deleted': true, 'text': 'Message deleted'}); },
            child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ])); },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: isMe ? kGreen : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4), bottomRight: Radius.circular(isMe ? 4 : 18))),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (reply != null) Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.15), borderRadius: BorderRadius.circular(8),
                  border: const Border(left: BorderSide(color: Colors.white54, width: 3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(reply['sender'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(reply['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ])),
              Text(text, style: TextStyle(color: deleted ? Colors.white54 : Colors.white, fontSize: 15,
                fontStyle: deleted ? FontStyle.italic : FontStyle.normal)),
            ])))));
  }
}

// ─── FRIENDS ──────────────────────────────────────────
class FriendsScreen extends StatefulWidget {
  final bool startChat;
  const FriendsScreen({super.key, this.startChat = false});
  @override State<FriendsScreen> createState() => _FriendsScreenState();
}
class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _searchCtrl = TextEditingController();
  final _myUid = _auth.currentUser!.uid;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  @override void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    try {
      final snap = await _db.collection('users')
          .where('username', isGreaterThanOrEqualTo: q.toLowerCase())
          .where('username', isLessThan: '${q.toLowerCase()}z').limit(15).get();
      setState(() => _results = snap.docs.map((d) => {...d.data(), 'uid': d.id}).toList());
    } finally { setState(() => _searching = false); }
  }

  Future<void> _sendRequest(String toUid, String toName) async {
    final ex = await _db.collection('friend_requests').where('from', isEqualTo: _myUid).where('to', isEqualTo: toUid).get();
    if (ex.docs.isNotEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request already sent!'))); return; }
    final fd = await _db.collection('users').doc(_myUid).collection('friends').doc(toUid).get();
    if (fd.exists) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already friends!'))); return; }
    final my = await _db.collection('users').doc(_myUid).get();
    await _db.collection('friend_requests').add({
      'from': _myUid, 'fromName': my.data()?['name'] ?? 'User', 'fromAvatar': my.data()?['avatar'] ?? 'U',
      'to': toUid, 'toName': toName, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request sent to $toName ✅'), backgroundColor: kGreen));
  }

  Future<void> _accept(String docId, String fromUid) async {
    await _db.collection('friend_requests').doc(docId).update({'status': 'accepted'});
    await _db.collection('users').doc(_myUid).collection('friends').doc(fromUid).set({'uid': fromUid, 'since': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(fromUid).collection('friends').doc(_myUid).set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend added! 🎉'), backgroundColor: kGreen));
  }

  Future<void> _decline(String docId) async => await _db.collection('friend_requests').doc(docId).update({'status': 'declined'});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.startChat ? 'New Message' : 'Friends', style: const TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(controller: _tab, indicatorColor: kGreen, labelColor: kGreen,
          tabs: const [Tab(text: 'Search'), Tab(text: 'Requests'), Tab(text: 'My Friends')])),
      body: TabBarView(controller: _tab, children: [
        Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: TextField(
            controller: _searchCtrl, onChanged: _search,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(hintText: 'Search by username...', hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search, color: Colors.grey), filled: true, fillColor: bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
          if (_searching) const CircularProgressIndicator(color: kGreen)
          else Expanded(child: ListView.builder(itemCount: _results.length, itemBuilder: (_, i) {
            final u = _results[i]; if (u['uid'] == _myUid) return const SizedBox();
            return ListTile(
              leading: CircleAvatar(backgroundColor: kGreen, child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              title: Text(u['name'] ?? ''), subtitle: Text('@${u['username']}', style: TextStyle(color: Colors.grey[500])),
              trailing: widget.startChat
                ? TextButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(otherUid: u['uid'], otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?'))),
                  child: const Text('Message', style: TextStyle(color: kGreen)))
                : TextButton(onPressed: () => _sendRequest(u['uid'], u['name'] ?? 'User'),
                  child: const Text('Add', style: TextStyle(color: kGreen))),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: u['uid']))));
          })),
        ]),

        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('friend_requests').where('to', isEqualTo: _myUid).where('status', isEqualTo: 'pending')
              .orderBy('timestamp', descending: true).snapshots(),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Text('No pending requests', style: TextStyle(color: Colors.grey[500])));
            return ListView(children: snap.data!.docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(backgroundColor: kGreen, child: Text(d['fromAvatar'] ?? 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                title: Text(d['fromName'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('sent you a friend request'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.check_circle, color: kGreen, size: 28), onPressed: () => _accept(doc.id, d['from'])),
                  IconButton(icon: const Icon(Icons.cancel, color: Colors.red, size: 28), onPressed: () => _decline(doc.id)),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: d['from']))));
            }).toList());
          }),

        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('users').doc(_myUid).collection('friends').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Text('No friends yet.\nSearch to add!',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])));
            return ListView(children: snap.data!.docs.map((doc) => StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('users').doc(doc.id).snapshots(),
              builder: (_, uSnap) {
                final u = uSnap.data?.data() as Map<String, dynamic>? ?? {};
                final online = u['isOnline'] == true;
                return ListTile(
                  leading: Stack(children: [
                    CircleAvatar(backgroundColor: kGreen, child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    if (online) Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10,
                      decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
                  ]),
                  title: Text(u['name'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(online ? 'Online' : '@${u['username'] ?? ''}', style: TextStyle(color: online ? kGreen : Colors.grey[500], fontSize: 12)),
                  trailing: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(otherUid: doc.id, otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?'))),
                    child: const Text('Message', style: TextStyle(color: kGreen))),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: doc.id))));
              })).toList());
          }),
      ]));
  }
}

// ─── PROFILE ──────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  final String uid;
  const ProfileScreen({super.key, required this.uid});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool get _isMe => widget.uid == _auth.currentUser?.uid;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final doc = await _db.collection('users').doc(widget.uid).get();
    if (mounted) setState(() => _user = doc.data());
  }
  @override
  Widget build(BuildContext context) {
    if (_user == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kGreen)));
    final name = _user!['name'] ?? 'User'; final username = _user!['username'] ?? '';
    final bio = _user!['bio'] ?? ''; final city = _user!['city'] ?? '';
    final education = _user!['education'] ?? ''; final work = _user!['work'] ?? '';
    final hometown = _user!['hometown'] ?? ''; final verified = _user!['verified'] == true;
    final online = _user!['isOnline'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(_isMe ? 'My Profile' : name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [if (_isMe) IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _showEdit(context))]),
      body: SingleChildScrollView(child: Column(children: [
        const SizedBox(height: 28),
        Center(child: Stack(children: [
          Container(width: 90, height: 90, decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
            border: Border.all(color: kGreen.withOpacity(0.3), width: 3)),
            child: Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)))),
          if (online) Positioned(right: 4, bottom: 4, child: Container(width: 14, height: 14,
            decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
        ])),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          if (verified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: kGreen, size: 20)],
        ]),
        Text('@$username', style: TextStyle(color: Colors.grey[500])),
        Text(online ? '🟢 Online' : '⚫ Offline', style: TextStyle(color: online ? kGreen : Colors.grey[600], fontSize: 12)),
        if (bio.isNotEmpty) ...[const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(bio, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400], fontSize: 13)))],
        const SizedBox(height: 20),
        if (city.isNotEmpty) _infoTile(Icons.location_on_outlined, 'City', city),
        if (hometown.isNotEmpty) _infoTile(Icons.home_outlined, 'Hometown / Village', hometown),
        if (education.isNotEmpty) _infoTile(Icons.school_outlined, 'Education', education),
        if (work.isNotEmpty) _infoTile(Icons.work_outline, 'Work', work),
        const SizedBox(height: 16),
        if (!_isMe) Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _greenBtn('Send Message', () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(otherUid: widget.uid, otherName: name, otherAvatar: name[0].toUpperCase()))))),
        const SizedBox(height: 32),
      ])),
    );
  }
  Widget _infoTile(IconData icon, String label, String value) => ListTile(
    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: kGreen, size: 20)),
    title: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
    subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)));

  void _showEdit(BuildContext context) {
    final nc = TextEditingController(text: _user?['name'] ?? '');
    final bc = TextEditingController(text: _user?['bio'] ?? '');
    final cc = TextEditingController(text: _user?['city'] ?? '');
    final hc = TextEditingController(text: _user?['hometown'] ?? '');
    final ec = TextEditingController(text: _user?['education'] ?? '');
    final wc = TextEditingController(text: _user?['work'] ?? '');
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _ef('Name', nc), const SizedBox(height: 10),
          _ef('Bio', bc, lines: 2), const SizedBox(height: 10),
          _ef('City', cc), const SizedBox(height: 10),
          _ef('Hometown / Village', hc), const SizedBox(height: 10),
          _ef('Education', ec), const SizedBox(height: 10),
          _ef('Work / Occupation', wc), const SizedBox(height: 16),
          _greenBtn('Save', () async {
            await _db.collection('users').doc(widget.uid).update({
              'name': nc.text.trim(), 'bio': bc.text.trim(), 'city': cc.text.trim(),
              'hometown': hc.text.trim(), 'education': ec.text.trim(), 'work': wc.text.trim(),
              'avatar': nc.text.trim().isNotEmpty ? nc.text.trim()[0].toUpperCase() : 'U',
            });
            await _auth.currentUser?.updateDisplayName(nc.text.trim());
            Navigator.pop(context); _load();
          }),
        ]))));
  }
  Widget _ef(String label, TextEditingController ctrl, {int lines = 1}) => TextField(
    controller: ctrl, maxLines: lines,
    decoration: InputDecoration(labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kGreen))));
}

// ─── SETTINGS ─────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  bool _suggestions = true;
  Map<String, dynamic>? _user;
  final _myUid = _auth.currentUser!.uid;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final doc = await _db.collection('users').doc(_myUid).get();
    if (mounted) setState(() { _user = doc.data(); _suggestions = doc.data()?['suggestionsEnabled'] ?? true; });
  }
  Future<void> _signOut() async {
    await _db.collection('users').doc(_myUid).update({'isOnline': false});
    await _auth.signOut();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _user?['name'] ?? 'User'; final username = _user?['username'] ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(children: [
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid))),
          child: Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: isDark ? kCard : Colors.grey[100], borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              CircleAvatar(radius: 28, backgroundColor: kGreen,
                child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                const Text('Tap to view profile', style: TextStyle(color: kGreen, fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ])),
        ),
        _sec('Account'),
        _t(Icons.person_outline, 'Edit Profile', 'Name, bio, work, education',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid)))),
        _t(Icons.lock_outline, 'Change Password', 'Update your password', () => _changePass(context)),
        _t(Icons.verified_outlined, 'Get Verified', 'Monthly or yearly plan', () => _verify(context)),
        _sec('Preferences'),
        _t(Icons.notifications_outlined, 'Notifications', 'Manage alerts', () {}),
        _t(Icons.palette_outlined, 'Appearance', 'Theme, colors', () {}),
        _t(Icons.language_outlined, 'Language', 'Bangla / English', () {}),
        _sec('Discovery'),
        SwitchListTile(
          value: _suggestions,
          onChanged: (val) async { setState(() => _suggestions = val);
            await _db.collection('users').doc(_myUid).update({'suggestionsEnabled': val}); },
          activeColor: kGreen,
          secondary: _ib(Icons.person_search_outlined),
          title: const Text('Account Suggestions', style: TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text('Suggest your profile to others', style: TextStyle(color: Colors.grey[500], fontSize: 12))),
        _sec('About'),
        _t(Icons.favorite_outline, 'Powered by TheKami', 'thekami.tech', () => launchUrl(Uri.parse('https://thekami.tech'))),
        _t(Icons.info_outline, 'App Version', 'Convo v1.0.2', () {}),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), elevation: 0,
              minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            onPressed: _signOut)),
        const SizedBox(height: 32),
      ]));
  }
  void _changePass(BuildContext context) {
    final c = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Change Password'),
      content: TextField(controller: c, obscureText: true, decoration: const InputDecoration(hintText: 'New password (min 6)', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          if (c.text.length >= 6) { await _auth.currentUser?.updatePassword(c.text); Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated!'), backgroundColor: kGreen)); }
        }, child: const Text('Update', style: TextStyle(color: kGreen))),
      ]));
  }
  void _verify(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified_rounded, color: kGreen, size: 48), const SizedBox(height: 16),
        const Text('Get Verified', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        Text('Show everyone you\'re the real deal', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400])),
        const SizedBox(height: 24),
        _pt('Monthly', '\$1.99/month', false), const SizedBox(height: 10),
        _pt('Yearly', '\$14.99/year  🔥 Save 37%', true), const SizedBox(height: 20),
        _greenBtn('Coming Soon', () => Navigator.pop(context)),
      ])));
  }
  Widget _pt(String t, String p, bool h) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(border: Border.all(color: h ? kGreen : Colors.grey[700]!), borderRadius: BorderRadius.circular(12),
      color: h ? kGreen.withOpacity(0.1) : Colors.transparent),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(p, style: TextStyle(color: h ? kGreen : Colors.grey[400], fontSize: 13))]));
  Widget _sec(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4)));
  Widget _t(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
    leading: _ib(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(sub, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: Colors.grey), onTap: onTap);
  Widget _ib(IconData icon) => Container(width: 40, height: 40,
    decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: kGreen, size: 20));
}

// ─── HELPERS ──────────────────────────────────────────
Widget _errorBox(String msg) => Container(
  padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.red.withOpacity(0.3))),
  child: Text(msg, style: const TextStyle(color: Colors.red, fontSize: 13)));

Widget _field(String hint, IconData icon, TextEditingController ctrl, bool obscure, bool isDark, Color bg) => TextField(
  controller: ctrl, obscureText: obscure,
  style: TextStyle(color: isDark ? Colors.white : Colors.black),
  decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey[500]),
    prefixIcon: Icon(icon, color: Colors.grey), filled: true, fillColor: bg,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)));

Widget _greenBtn(String label, VoidCallback? onTap, {bool loading = false}) => SizedBox(
  width: double.infinity, height: 54,
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    onPressed: onTap,
    child: loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))));
