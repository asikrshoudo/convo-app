import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const kGreen  = Color(0xFF00C853);
const kDark   = Color(0xFF0A0A0A);
const kCard   = Color(0xFF1A1A1A);
const kCard2  = Color(0xFF222222);

final _db   = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

// ─── APP ──────────────────────────────────────────────
class ConvoApp extends StatelessWidget {
  const ConvoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Convo', debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: ThemeData(
      useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.light,
      fontFamily: 'Roboto',
    ),
    darkTheme: ThemeData(
      useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.dark,
      scaffoldBackgroundColor: kDark, fontFamily: 'Roboto',
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF111111)),
    ),
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
            gradient: const LinearGradient(colors: [Color(0xFF00E676), kGreen],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 8))]),
          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 54))),
        const SizedBox(height: 24),
        const Text('Convo', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('powered by TheKami', style: TextStyle(color: Colors.grey, fontSize: 13, letterSpacing: 0.5)),
      ]))),
  );
}

// ─── LOGIN ────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  bool _obscure = true, _loading = false, _showPhone = false, _otpSent = false;
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  String? _error, _verificationId;

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
      setState(() => _error = _friendlyError(e.code));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final gUser = await GoogleSignIn().signIn();
      if (gUser == null) { setState(() => _loading = false); return; }
      final gAuth = await gUser.authentication;
      final cred = GoogleAuthProvider.credential(accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final result = await _auth.signInWithCredential(cred);
      await _ensureUserDoc(result.user!);
      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyError(e.code));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _githubSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _auth.signInWithProvider(GithubAuthProvider());
      await _ensureUserDoc(result.user!);
      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyError(e.code));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.isEmpty) { setState(() => _error = 'Enter phone number'); return; }
    setState(() { _loading = true; _error = null; });
    await _auth.verifyPhoneNumber(
      phoneNumber: _phoneCtrl.text.trim(),
      verificationCompleted: (cred) async {
        final r = await _auth.signInWithCredential(cred);
        await _ensureUserDoc(r.user!); await _afterLogin();
      },
      verificationFailed: (e) => setState(() { _error = _friendlyError(e.code); _loading = false; }),
      codeSent: (vId, _) => setState(() { _verificationId = vId; _otpSent = true; _loading = false; }),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.isEmpty || _verificationId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otpCtrl.text.trim());
      final r = await _auth.signInWithCredential(cred);
      await _ensureUserDoc(r.user!); await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyError(e.code));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found': return 'No account found with this email.';
      case 'wrong-password': return 'Incorrect password.';
      case 'invalid-email': return 'Invalid email address.';
      case 'too-many-requests': return 'Too many attempts. Try again later.';
      case 'network-request-failed': return 'No internet connection.';
      default: return 'Something went wrong. Try again.';
    }
  }

  Future<void> _ensureUserDoc(User user) async {
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      final name = user.displayName ?? user.email?.split('@').first ?? 'User';
      final fcm  = await FirebaseMessaging.instance.getToken();
      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid, 'name': name,
        'username': '${name.toLowerCase().replaceAll(' ', '_')}_${user.uid.substring(0, 4)}',
        'email': user.email ?? '', 'avatar': name[0].toUpperCase(),
        'verified': false, 'suggestionsEnabled': true,
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'social': {'facebook': '', 'instagram': '', 'github': '', 'linkedin': '', 'twitter': ''},
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Enter your email to receive a reset link', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        const SizedBox(height: 12),
        TextField(controller: ctrl, decoration: InputDecoration(hintText: 'Email address',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen)))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () async {
            if (ctrl.text.isNotEmpty) {
              await _auth.sendPasswordResetEmail(email: ctrl.text.trim());
              Navigator.pop(context);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reset link sent! Check your inbox.'), backgroundColor: kGreen));
            }
          }, child: const Text('Send', style: TextStyle(color: Colors.white))),
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
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF00E676), kGreen]),
                borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 28)),
            const SizedBox(width: 12),
            const Text('Convo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 36),
          const Text('Welcome back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Sign in to continue', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) _errorBox(_error!),

          if (!_showPhone) ...[
            _inputField('Email address', Icons.email_outlined, _emailCtrl, false, isDark, bg),
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
            _primaryBtn('Sign In', _loading ? null : _signIn, loading: _loading),
          ],

          if (_showPhone) ...[
            if (!_otpSent) ...[
              TextField(
                controller: _phoneCtrl, keyboardType: TextInputType.phone,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: '+880 1XXXXXXXXX', hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.phone_outlined, color: Colors.grey),
                  filled: true, fillColor: bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 14),
              _primaryBtn('Send OTP', _loading ? null : _sendOtp, loading: _loading),
            ] else ...[
              TextField(
                controller: _otpCtrl, keyboardType: TextInputType.number,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: '6-digit OTP code', hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.sms_outlined, color: Colors.grey),
                  filled: true, fillColor: bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 14),
              _primaryBtn('Verify OTP', _loading ? null : _verifyOtp, loading: _loading),
              Center(child: TextButton(
                onPressed: () => setState(() { _otpSent = false; _verificationId = null; }),
                child: const Text('Resend OTP', style: TextStyle(color: kGreen)))),
            ],
          ],

          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kGreen),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: Icon(_showPhone ? Icons.email_outlined : Icons.phone_outlined, color: kGreen, size: 20),
            label: Text(_showPhone ? 'Use Email Instead' : 'Continue with Phone',
              style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600)),
            onPressed: () => setState(() { _showPhone = !_showPhone; _error = null; _otpSent = false; })),

          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: Divider(color: Colors.grey[700], thickness: 0.5)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or continue with', style: TextStyle(color: Colors.grey[500], fontSize: 13))),
            Expanded(child: Divider(color: Colors.grey[700], thickness: 0.5)),
          ]),
          const SizedBox(height: 16),

          // Google
          _oauthBtn(
            icon: Icons.g_mobiledata_rounded, iconColor: const Color(0xFFDB4437),
            label: 'Continue with Google', isDark: isDark, bg: bg,
            onPressed: _loading ? null : _googleSignIn),
          const SizedBox(height: 12),

          // GitHub
          _oauthBtn(
            icon: Icons.code_rounded, iconColor: isDark ? Colors.white : Colors.black87,
            label: 'Continue with GitHub', isDark: isDark, bg: bg,
            onPressed: _loading ? null : _githubSignIn),

          const SizedBox(height: 24),
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

  Widget _oauthBtn({required IconData icon, required Color iconColor, required String label,
      required bool isDark, required Color bg, VoidCallback? onPressed}) =>
    SizedBox(width: double.infinity, height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: bg, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey[isDark ? 700 : 300]!, width: 1))),
        icon: Icon(icon, color: iconColor, size: 28),
        label: Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black87,
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
  String _usernameStatus = '';
  Timer? _debounce;
  final _nameCtrl     = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();

  // Username suggestions list
  final List<String> _suggestions = [];

  void _onUsernameChanged(String val) {
    _debounce?.cancel();
    if (val.isEmpty) { setState(() { _usernameStatus = ''; _suggestions.clear(); }); return; }
    setState(() => _usernameStatus = 'checking');
    _debounce = Timer(const Duration(milliseconds: 500), () => _checkUsername(val));
  }

  Future<void> _checkUsername(String username) async {
    final clean = username.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (clean.length < 3) { setState(() { _usernameStatus = 'short'; _suggestions.clear(); }); return; }
    final snap = await _db.collection('users').where('username', isEqualTo: clean).get();
    if (!mounted) return;
    if (snap.docs.isEmpty) {
      setState(() { _usernameStatus = 'available'; _suggestions.clear(); });
    } else {
      // Generate suggestions
      final base = clean.replaceAll(RegExp(r'\d+$'), '');
      final now = DateTime.now();
      final sugg = [
        '${base}${now.year % 100}',
        '${base}_official',
        '${base}__',
        '${base}x',
        '${base}${now.month}${now.day}',
      ];
      setState(() { _usernameStatus = 'taken'; _suggestions.clear(); _suggestions.addAll(sugg); });
    }
  }

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _usernameCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill all fields'); return;
    }
    if (_usernameStatus == 'taken') { setState(() => _error = 'Username is already taken'); return; }
    if (_usernameStatus != 'available') { setState(() => _error = 'Choose a valid username'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      await cred.user!.sendEmailVerification();
      final fcm = await FirebaseMessaging.instance.getToken();
      final uname = _usernameCtrl.text.trim().toLowerCase();
      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid, 'name': _nameCtrl.text.trim(),
        'username': uname, 'email': _emailCtrl.text.trim(),
        'avatar': _nameCtrl.text.trim()[0].toUpperCase(),
        'verified': false, 'emailVerified': false, 'suggestionsEnabled': true,
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'social': {'facebook': '', 'instagram': '', 'github': '', 'linkedin': '', 'twitter': ''},
        'fcmToken': fcm ?? '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await cred.user!.updateDisplayName(_nameCtrl.text.trim());
      if (mounted) {
        showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Verify your email', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.mark_email_read_outlined, color: kGreen, size: 48),
            const SizedBox(height: 12),
            Text('We sent a verification link to\n${_emailCtrl.text.trim()}',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
          ]),
          actions: [
            TextButton(onPressed: () => cred.user!.sendEmailVerification(),
              child: const Text('Resend', style: TextStyle(color: kGreen))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
              },
              child: const Text('Continue', style: TextStyle(color: Colors.white))),
          ],
        ));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Registration failed');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;

    Color uColor = Colors.grey;
    IconData uIcon = Icons.alternate_email;
    String uHint = '';
    if (_usernameStatus == 'checking') { uColor = Colors.orange; uHint = 'Checking...'; }
    else if (_usernameStatus == 'available') { uColor = kGreen; uIcon = Icons.check_circle_outline; uHint = 'Available'; }
    else if (_usernameStatus == 'taken') { uColor = Colors.red; uIcon = Icons.cancel_outlined; uHint = 'Not available'; }
    else if (_usernameStatus == 'short') { uColor = Colors.orange; uHint = 'Minimum 3 characters'; }

    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context))),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Create Account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Join Convo today', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) _errorBox(_error!),

          _inputField('Full Name', Icons.person_outline, _nameCtrl, false, isDark, bg),
          const SizedBox(height: 14),

          // Username field
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _usernameCtrl,
              onChanged: _onUsernameChanged,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))],
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Username (letters, numbers, _)',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(uIcon, color: uColor),
                suffixIcon: _usernameStatus == 'checking'
                  ? const Padding(padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)))
                  : null,
                filled: true, fillColor: bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: uColor, width: 1.5))),
            ),
            if (uHint.isNotEmpty) Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(uHint, style: TextStyle(color: uColor, fontSize: 12))),

            // Suggestions
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Try one of these:', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: _suggestions.map((s) =>
                GestureDetector(
                  onTap: () {
                    _usernameCtrl.text = s;
                    _checkUsername(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kGreen.withOpacity(0.4))),
                    child: Text(s, style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w500))))).toList()),
            ],
          ]),
          const SizedBox(height: 14),

          _inputField('Email address', Icons.email_outlined, _emailCtrl, false, isDark, bg),
          const SizedBox(height: 14),

          TextField(
            controller: _passCtrl, obscureText: _obscure,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Password (min 6 characters)', hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
                onPressed: () => setState(() => _obscure = !_obscure)),
              filled: true, fillColor: bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 24),
          _primaryBtn('Create Account', _loading ? null : _register, loading: _loading),
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
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    _setupFCM();
  }
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
        content: Text('${n.title}: ${n.body}'), backgroundColor: kGreen,
        behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser!.uid;
    return Scaffold(
      body: IndexedStack(index: _idx, children: [
        const ChatsScreen(),
        const FriendsScreen(),
        ProfileScreen(uid: uid),
        const SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        indicatorColor: kGreen.withOpacity(0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded, color: kGreen), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded, color: kGreen), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded, color: kGreen), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded, color: kGreen), label: 'Settings'),
        ],
      ),
    );
  }
}

// ─── CHATS SCREEN ─────────────────────────────────────
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser!.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.white,
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
                  child: Text(name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));
              }))),
        title: const Text('Convo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen()))),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('chats')
          .where('participants', arrayContains: myUid)
          .orderBy('lastTimestamp', descending: true)
          .snapshots(),
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
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                icon: const Icon(Icons.people_rounded, color: Colors.white),
                label: const Text('Find Friends', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen()))),
            ]));
          }
          return ListView.separated(
            itemCount: snap.data!.docs.length,
            separatorBuilder: (_, __) => Divider(height: 0, color: Colors.grey.withOpacity(0.1), indent: 76),
            itemBuilder: (_, i) {
              final data = snap.data!.docs[i].data() as Map<String, dynamic>;
              final parts = List<String>.from(data['participants'] ?? []);
              final other = parts.firstWhere((u) => u != myUid, orElse: () => '');
              return _ChatTile(chatData: data, otherUid: other, myUid: myUid);
            });
        }),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGreen,
        child: const Icon(Icons.edit_rounded, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen(startChat: true)))),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chatData;
  final String otherUid, myUid;
  const _ChatTile({required this.chatData, required this.otherUid, required this.myUid});

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
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot>(
    stream: _db.collection('users').doc(otherUid).snapshots(),
    builder: (_, snap) {
      final u = snap.data?.data() as Map<String, dynamic>? ?? {};
      final name = u['name'] as String? ?? 'User';
      final avatar = u['avatar'] as String? ?? name[0].toUpperCase();
      final online = u['isOnline'] == true;
      final lastMsg = chatData['lastMessage'] as String? ?? '';
      final lastTs = chatData['lastTimestamp'] as Timestamp?;
      final unread = (chatData['unread_$myUid'] ?? 0) as int;
      final isMine = chatData['lastSender'] == myUid;

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(children: [
          CircleAvatar(radius: 26, backgroundColor: kGreen,
            child: Text(avatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
          if (online) Positioned(right: 0, bottom: 0, child: Container(width: 13, height: 13,
            decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
        ]),
        title: Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          Text(_timeAgo(lastTs), style: TextStyle(
            color: unread > 0 ? kGreen : Colors.grey[500], fontSize: 12,
            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
        ]),
        subtitle: Row(children: [
          if (isMine) const Icon(Icons.done_all_rounded, size: 14, color: kGreen),
          if (isMine) const SizedBox(width: 4),
          Expanded(child: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unread > 0 ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey[500],
              fontSize: 13, fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal))),
          if (unread > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(10)),
            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
        ]),
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
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _replyToId, _replyToText, _replyToSender;
  late String _chatId, _myUid;

  @override void initState() {
    super.initState();
    _myUid = _auth.currentUser!.uid;
    final ids = [_myUid, widget.otherUid]..sort();
    _chatId = ids.join('_');
    _clearUnread();
  }

  Future<void> _clearUnread() async =>
    await _db.collection('chats').doc(_chatId).set({'unread_$_myUid': 0}, SetOptions(merge: true));

  Future<void> _send(String text) async {
    final t = text.trim(); if (t.isEmpty) return;
    _msgCtrl.clear();
    final reply = _replyToId != null
      ? {'id': _replyToId, 'text': _replyToText, 'sender': _replyToSender} : null;
    setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; });
    await _db.collection('chats').doc(_chatId).collection('messages').add({
      'text': t, 'senderId': _myUid,
      'senderName': _auth.currentUser?.displayName ?? 'User',
      'timestamp': FieldValue.serverTimestamp(), 'deleted': false,
      if (reply != null) 'reply': reply,
    });
    await _db.collection('chats').doc(_chatId).set({
      'participants': [_myUid, widget.otherUid],
      'lastMessage': t, 'lastTimestamp': FieldValue.serverTimestamp(),
      'lastSender': _myUid,
      'unread_${widget.otherUid}': FieldValue.increment(1),
      'unread_$_myUid': 0,
    }, SetOptions(merge: true));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? kDark : Colors.white, titleSpacing: 0, elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        title: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: widget.otherUid))),
          child: Row(children: [
            Stack(children: [
              CircleAvatar(radius: 19, backgroundColor: kGreen,
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
                  return Text(online ? 'Online' : 'Offline',
                    style: TextStyle(color: online ? kGreen : Colors.grey, fontSize: 11));
                }),
            ]),
          ])),
        actions: [
          IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
        ],
      ),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('chats').doc(_chatId).collection('messages')
            .orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kGreen));
            final msgs = snap.data!.docs;
            if (msgs.isEmpty) return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.waving_hand_rounded, size: 48, color: kGreen),
                const SizedBox(height: 12),
                Text('Say hi to ${widget.otherName}!',
                  style: TextStyle(color: Colors.grey[500], fontSize: 15)),
              ]));
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            });
            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final data = msgs[i].data() as Map<String, dynamic>;
                final isMe = data['senderId'] == _myUid;
                final prevData = i > 0 ? msgs[i-1].data() as Map<String, dynamic> : null;
                final isFirst = prevData == null || prevData['senderId'] != data['senderId'];
                return _Bubble(
                  msgId: msgs[i].id, data: data, isMe: isMe, isFirst: isFirst,
                  chatId: _chatId,
                  onReply: (id, text, sender) => setState(() {
                    _replyToId = id; _replyToText = text; _replyToSender = sender;
                  }),
                );
              });
          })),

        // Reply preview
        if (_replyToId != null) Container(
          color: isDark ? kCard2 : Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(width: 3, height: 36, decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_replyToSender ?? '', style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; })),
          ])),

        // Input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? kCard : Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))]),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _msgCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4, minLines: 1,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Message...', hintStyle: TextStyle(color: Colors.grey[500]),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                filled: true, fillColor: isDark ? kCard2 : Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(_msgCtrl.text),
              child: Container(width: 46, height: 46,
                decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(23)),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
          ])),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String msgId, chatId;
  final Map<String, dynamic> data;
  final bool isMe, isFirst;
  final void Function(String id, String text, String sender) onReply;
  const _Bubble({required this.msgId, required this.chatId, required this.data,
    required this.isMe, required this.isFirst, required this.onReply});

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final text = data['text'] as String? ?? '';
    final deleted = data['deleted'] == true;
    final reply = data['reply'] as Map<String, dynamic>?;
    final ts = data['timestamp'] as Timestamp?;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if (!deleted && (d.primaryVelocity ?? 0) < -100)
          onReply(msgId, text, data['senderName'] ?? '');
      },
      onLongPress: () {
        if (deleted) return;
        showModalBottomSheet(context: context,
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: kGreen),
              title: const Text('Reply'),
              onTap: () { Navigator.pop(context); onReply(msgId, text, data['senderName'] ?? ''); }),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () { Navigator.pop(context); Clipboard.setData(ClipboardData(text: text)); }),
            if (isMe) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _db.collection('chats').doc(chatId).collection('messages').doc(msgId)
                  .update({'deleted': true, 'text': 'Message deleted'});
              }),
            const SizedBox(height: 12),
          ]));
      },
      child: Padding(
        padding: EdgeInsets.only(
          top: isFirst ? 8 : 2, bottom: 2,
          left: isMe ? 48 : 0, right: isMe ? 0 : 48),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isMe ? kGreen : (Theme.of(context).brightness == Brightness.dark ? kCard2 : Colors.white),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4), bottomRight: Radius.circular(isMe ? 4 : 18)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (reply != null) Container(
                      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
                        border: const Border(left: BorderSide(color: Colors.white54, width: 3))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(reply['sender'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text(reply['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ])),
                    Text(text, style: TextStyle(
                      color: deleted
                        ? (isMe ? Colors.white54 : Colors.grey[500])
                        : (isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color),
                      fontSize: 15,
                      fontStyle: deleted ? FontStyle.italic : FontStyle.normal)),
                  ]))),
              const SizedBox(height: 2),
              Text(_formatTime(ts), style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            ]))));
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
        .where('username', isLessThan: '${q.toLowerCase()}z').limit(20).get();
      setState(() => _results = snap.docs.map((d) => {...d.data(), 'uid': d.id}).toList());
    } finally { if (mounted) setState(() => _searching = false); }
  }

  Future<void> _sendRequest(String toUid, String toName) async {
    final ex = await _db.collection('friend_requests')
      .where('from', isEqualTo: _myUid).where('to', isEqualTo: toUid).get();
    if (ex.docs.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request already sent!'), backgroundColor: Colors.orange)); return;
    }
    final fd = await _db.collection('users').doc(_myUid).collection('friends').doc(toUid).get();
    if (fd.exists) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already friends!'), backgroundColor: kGreen)); return;
    }
    final my = await _db.collection('users').doc(_myUid).get();
    await _db.collection('friend_requests').add({
      'from': _myUid, 'fromName': my.data()?['name'] ?? 'User',
      'fromAvatar': my.data()?['avatar'] ?? 'U',
      'to': toUid, 'toName': toName, 'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Request sent to $toName'), backgroundColor: kGreen,
        behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  Future<void> _accept(String docId, String fromUid) async {
    await _db.collection('friend_requests').doc(docId).update({'status': 'accepted'});
    await _db.collection('users').doc(_myUid).collection('friends').doc(fromUid)
      .set({'uid': fromUid, 'since': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(fromUid).collection('friends').doc(_myUid)
      .set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend added!'), backgroundColor: kGreen,
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _decline(String docId) async =>
    await _db.collection('friend_requests').doc(docId).update({'status': 'declined'});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.startChat ? 'New Message' : 'Friends',
          style: const TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(controller: _tab, indicatorColor: kGreen, labelColor: kGreen,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.search_rounded), text: 'Search'),
            Tab(icon: Icon(Icons.notifications_outlined), text: 'Requests'),
            Tab(icon: Icon(Icons.people_rounded), text: 'Friends'),
          ])),
      body: TabBarView(controller: _tab, children: [
        // Search Tab
        Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: TextField(
            controller: _searchCtrl, onChanged: _search,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Search by username...', hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
              filled: true, fillColor: bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
          if (_searching) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: kGreen))
          else if (_results.isEmpty && _searchCtrl.text.isNotEmpty)
            Padding(padding: const EdgeInsets.all(32), child: Column(children: [
              Icon(Icons.person_search_rounded, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 12),
              Text('No users found', style: TextStyle(color: Colors.grey[500])),
            ]))
          else Expanded(child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final u = _results[i];
              if (u['uid'] == _myUid) return const SizedBox();
              return ListTile(
                leading: CircleAvatar(backgroundColor: kGreen,
                  child: Text(u['avatar'] ?? '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                title: Text(u['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('@${u['username']}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                trailing: widget.startChat
                  ? FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(otherUid: u['uid'], otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?'))),
                      child: const Text('Message'))
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: kGreen),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () => _sendRequest(u['uid'], u['name'] ?? 'User'),
                      child: const Text('Add', style: TextStyle(color: kGreen))),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: u['uid']))));
            })),
        ]),

        // Requests Tab
        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('friend_requests')
            .where('to', isEqualTo: _myUid).where('status', isEqualTo: 'pending')
            .orderBy('timestamp', descending: true).snapshots(),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_rounded, size: 48, color: Colors.grey[600]),
                const SizedBox(height: 12),
                Text('No pending requests', style: TextStyle(color: Colors.grey[500])),
              ]));
            return ListView(children: snap.data!.docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(backgroundColor: kGreen,
                  child: Text(d['fromAvatar'] ?? 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                title: Text(d['fromName'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Sent you a friend request', style: TextStyle(fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Accept
                  GestureDetector(
                    onTap: () => _accept(doc.id, d['from']),
                    child: Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: kGreen.withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: kGreen, size: 22))),
                  const SizedBox(width: 8),
                  // Reject
                  GestureDetector(
                    onTap: () => _decline(doc.id),
                    child: Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.red, size: 22))),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: d['from']))));
            }).toList());
          }),

        // My Friends Tab
        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('users').doc(_myUid).collection('friends').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[600]),
                const SizedBox(height: 12),
                Text('No friends yet', style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 4),
                const Text('Search to add friends!', style: TextStyle(color: kGreen, fontSize: 12)),
              ]));
            return ListView(children: snap.data!.docs.map((doc) =>
              StreamBuilder<DocumentSnapshot>(
                stream: _db.collection('users').doc(doc.id).snapshots(),
                builder: (_, uSnap) {
                  final u = uSnap.data?.data() as Map<String, dynamic>? ?? {};
                  final online = u['isOnline'] == true;
                  return ListTile(
                    leading: Stack(children: [
                      CircleAvatar(backgroundColor: kGreen,
                        child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      if (online) Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
                    ]),
                    title: Text(u['name'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(online ? 'Online' : '@${u['username'] ?? ''}',
                      style: TextStyle(color: online ? kGreen : Colors.grey[500], fontSize: 12)),
                    trailing: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kGreen.withOpacity(0.15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: kGreen, size: 16),
                      label: const Text('Chat', style: TextStyle(color: kGreen, fontSize: 13)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(otherUid: doc.id, otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?')))),
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

  // Social platform configs
  List<Map<String, dynamic>> get _socialPlatforms => [
    {'key': 'facebook',   'icon': Icons.facebook_rounded,   'color': const Color(0xFF1877F2), 'label': 'Facebook',  'prefix': 'https://facebook.com/'},
    {'key': 'instagram',  'icon': Icons.camera_alt_rounded,  'color': const Color(0xFFE1306C), 'label': 'Instagram', 'prefix': 'https://instagram.com/'},
    {'key': 'github',     'icon': Icons.code_rounded,        'color': const Color(0xFF333333), 'label': 'GitHub',    'prefix': 'https://github.com/'},
    {'key': 'linkedin',   'icon': Icons.work_rounded,        'color': const Color(0xFF0077B5), 'label': 'LinkedIn',  'prefix': 'https://linkedin.com/in/'},
    {'key': 'twitter',    'icon': Icons.alternate_email,     'color': const Color(0xFF1DA1F2), 'label': 'X / Twitter','prefix': 'https://twitter.com/'},
  ];

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kGreen)));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name      = _user!['name'] as String? ?? 'User';
    final username  = _user!['username'] as String? ?? '';
    final bio       = _user!['bio'] as String? ?? '';
    final city      = _user!['city'] as String? ?? '';
    final education = _user!['education'] as String? ?? '';
    final work      = _user!['work'] as String? ?? '';
    final hometown  = _user!['hometown'] as String? ?? '';
    final verified  = _user!['verified'] == true;
    final online    = _user!['isOnline'] == true;
    final social    = _user!['social'] as Map<String, dynamic>? ?? {};

    final activeSocials = _socialPlatforms.where((p) => (social[p['key']] as String? ?? '').isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isMe ? 'My Profile' : name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [if (_isMe) IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _showEdit(context))]),
      body: SingleChildScrollView(child: Column(children: [
        // Header
        Container(width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kGreen.withOpacity(0.3), Colors.transparent],
              begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Column(children: [
            const SizedBox(height: 28),
            Stack(children: [
              Container(width: 90, height: 90,
                decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 20)]),
                child: Center(child: Text(name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold)))),
              if (online) Positioned(right: 2, bottom: 2, child: Container(width: 16, height: 16,
                decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
                  border: Border.all(color: isDark ? kDark : Colors.white, width: 2)))),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              if (verified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: kGreen, size: 20)],
            ]),
            Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                color: online ? kGreen : Colors.grey, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(online ? 'Online' : 'Offline',
                style: TextStyle(color: online ? kGreen : Colors.grey[500], fontSize: 12)),
            ]),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(bio, textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5))),
            ],
            const SizedBox(height: 20),
          ])),

        // Info Section
        if (city.isNotEmpty || hometown.isNotEmpty || education.isNotEmpty || work.isNotEmpty) ...[
          _sectionTitle('About'),
          if (city.isNotEmpty) _infoRow(Icons.location_city_rounded, 'City', city),
          if (hometown.isNotEmpty) _infoRow(Icons.home_rounded, 'Hometown', hometown),
          if (education.isNotEmpty) _infoRow(Icons.school_rounded, 'Education', education),
          if (work.isNotEmpty) _infoRow(Icons.work_rounded, 'Work', work),
        ],

        // Social Links
        if (activeSocials.isNotEmpty) ...[
          _sectionTitle('Socials'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(spacing: 12, runSpacing: 12, children: activeSocials.map((p) {
              final username = social[p['key']] as String;
              return GestureDetector(
                onTap: () => launchUrl(Uri.parse('${p['prefix']}$username'), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: (p['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (p['color'] as Color).withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(p['icon'] as IconData, color: p['color'] as Color, size: 20),
                    const SizedBox(width: 8),
                    Text('@$username', style: TextStyle(color: p['color'] as Color, fontWeight: FontWeight.w600, fontSize: 13)),
                  ])));
            }).toList())),
        ],

        const SizedBox(height: 16),
        if (!_isMe) Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _primaryBtn('Send Message', () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(otherUid: widget.uid, otherName: name, otherAvatar: name[0].toUpperCase()))))),
        const SizedBox(height: 32),
      ])),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: Colors.grey.withOpacity(0.3))),
    ]));

  Widget _infoRow(IconData icon, String label, String value) => ListTile(
    dense: true,
    leading: Container(width: 38, height: 38,
      decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: kGreen, size: 18)),
    title: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
    subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)));

  void _showEdit(BuildContext context) {
    final nc = TextEditingController(text: _user?['name'] ?? '');
    final bc = TextEditingController(text: _user?['bio'] ?? '');
    final cc = TextEditingController(text: _user?['city'] ?? '');
    final hc = TextEditingController(text: _user?['hometown'] ?? '');
    final ec = TextEditingController(text: _user?['education'] ?? '');
    final wc = TextEditingController(text: _user?['work'] ?? '');
    final social = Map<String, dynamic>.from(_user?['social'] ?? {});
    final socialCtrls = <String, TextEditingController>{};
    for (final p in _socialPlatforms) {
      socialCtrls[p['key'] as String] = TextEditingController(text: social[p['key']] ?? '');
    }

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          _ef('Name', nc), const SizedBox(height: 10),
          _ef('Bio', bc, lines: 3), const SizedBox(height: 10),
          _ef('City', cc), const SizedBox(height: 10),
          _ef('Hometown', hc), const SizedBox(height: 10),
          _ef('Education', ec), const SizedBox(height: 10),
          _ef('Work / Occupation', wc), const SizedBox(height: 20),

          Align(alignment: Alignment.centerLeft,
            child: Text('Social Links', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[400]))),
          const SizedBox(height: 10),

          ...(_socialPlatforms.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: socialCtrls[p['key']],
              decoration: InputDecoration(
                hintText: '${p['label']} username',
                prefixIcon: Icon(p['icon'] as IconData, color: p['color'] as Color, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p['color'] as Color)))))).toList()),

          const SizedBox(height: 16),
          _primaryBtn('Save Changes', () async {
            final newSocial = <String, String>{};
            for (final p in _socialPlatforms) {
              newSocial[p['key'] as String] = socialCtrls[p['key']]!.text.trim();
            }
            await _db.collection('users').doc(widget.uid).update({
              'name': nc.text.trim(), 'bio': bc.text.trim(), 'city': cc.text.trim(),
              'hometown': hc.text.trim(), 'education': ec.text.trim(), 'work': wc.text.trim(),
              'social': newSocial,
              'avatar': nc.text.trim().isNotEmpty ? nc.text.trim()[0].toUpperCase() : 'U',
            });
            await _auth.currentUser?.updateDisplayName(nc.text.trim());
            if (mounted) { Navigator.pop(context); _load(); }
          }),
        ]))));
  }
  Widget _ef(String label, TextEditingController ctrl, {int lines = 1}) => TextField(
    controller: ctrl, maxLines: lines,
    decoration: InputDecoration(labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen))));
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
    final name     = _user?['name'] as String? ?? 'User';
    final username = _user?['username'] as String? ?? '';
    final verified = _user?['verified'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)), elevation: 0),
      body: ListView(children: [
        // Profile card
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid))),
          child: Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kGreen.withOpacity(0.15), kGreen.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kGreen.withOpacity(0.3))),
            child: Row(children: [
              CircleAvatar(radius: 28, backgroundColor: kGreen,
                child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (verified) ...[const SizedBox(width: 4), const Icon(Icons.verified_rounded, color: kGreen, size: 16)],
                ]),
                Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                const Text('View profile', style: TextStyle(color: kGreen, fontSize: 11)),
              ])),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
            ])),
        ),

        _sec('Account'),
        _t(Icons.person_rounded, 'Edit Profile', 'Name, bio, socials',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid)))),
        _t(Icons.lock_rounded, 'Change Password', 'Update your password', () => _changePass(context)),
        _t(Icons.verified_rounded, 'Get Verified', 'Blue badge for your profile', () => _verify(context)),

        _sec('Preferences'),
        _t(Icons.notifications_rounded, 'Notifications', 'Manage alerts', () {}),
        _t(Icons.palette_rounded, 'Appearance', 'Theme and colors', () {}),
        _t(Icons.language_rounded, 'Language', 'Bangla / English', () {}),

        _sec('Discovery'),
        SwitchListTile(
          value: _suggestions,
          onChanged: (val) async {
            setState(() => _suggestions = val);
            await _db.collection('users').doc(_myUid).update({'suggestionsEnabled': val});
          },
          activeColor: kGreen,
          secondary: _ib(Icons.person_search_rounded),
          title: const Text('Account Suggestions', style: TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text('Suggest your profile to others', style: TextStyle(color: Colors.grey[500], fontSize: 12))),

        _sec('About'),
        _t(Icons.favorite_rounded, 'Powered by TheKami', 'thekami.tech',
          () => launchUrl(Uri.parse('https://thekami.tech'), mode: LaunchMode.externalApplication)),
        _t(Icons.info_rounded, 'App Version', 'Convo v1.0.2', () {}),

        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.1), elevation: 0,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            onPressed: _signOut)),
        const SizedBox(height: 32),
      ]));
  }

  void _changePass(BuildContext context) {
    final c = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(controller: c, obscureText: true,
        decoration: InputDecoration(hintText: 'New password (min 6 chars)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () async {
            if (c.text.length >= 6) {
              await _auth.currentUser?.updatePassword(c.text);
              if (mounted) { Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated!'), backgroundColor: kGreen)); }
            }
          }, child: const Text('Update', style: TextStyle(color: Colors.white))),
      ]));
  }

  void _verify(BuildContext context) {
    showModalBottomSheet(context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Icon(Icons.verified_rounded, color: kGreen, size: 48),
        const SizedBox(height: 12),
        const Text('Get Verified', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Show everyone you are the real deal', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400])),
        const SizedBox(height: 24),
        _planTile('Monthly', '\$1.99 / month', false),
        const SizedBox(height: 10),
        _planTile('Yearly', '\$14.99 / year  — Save 37%', true),
        const SizedBox(height: 20),
        _primaryBtn('Coming Soon', () => Navigator.pop(context)),
      ])));
  }
  Widget _planTile(String t, String p, bool highlight) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      border: Border.all(color: highlight ? kGreen : Colors.grey[700]!),
      borderRadius: BorderRadius.circular(12),
      color: highlight ? kGreen.withOpacity(0.08) : Colors.transparent),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(p, style: TextStyle(color: highlight ? kGreen : Colors.grey[400], fontSize: 13))]));
  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4)));
  Widget _t(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
    leading: _ib(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(sub, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey), onTap: onTap);
  Widget _ib(IconData icon) => Container(width: 40, height: 40,
    decoration: BoxDecoration(color: kGreen.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: kGreen, size: 20));
}

// ─── HELPERS ──────────────────────────────────────────
Widget _errorBox(String msg) => Container(
  padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.red.withOpacity(0.3))),
  child: Row(children: [
    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
    const SizedBox(width: 8),
    Expanded(child: Text(msg, style: const TextStyle(color: Colors.red, fontSize: 13))),
  ]));

Widget _inputField(String hint, IconData icon, TextEditingController ctrl, bool obscure, bool isDark, Color bg) =>
  TextField(
    controller: ctrl, obscureText: obscure,
    style: TextStyle(color: isDark ? Colors.white : Colors.black),
    decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey[500]),
      prefixIcon: Icon(icon, color: Colors.grey), filled: true, fillColor: bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)));

Widget _primaryBtn(String label, VoidCallback? onTap, {bool loading = false}) => SizedBox(
  width: double.infinity, height: 54,
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    onPressed: onTap,
    child: loading
      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
      : Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))));
