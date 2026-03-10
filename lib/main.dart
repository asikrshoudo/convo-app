import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage msg) async => await Firebase.initializeApp();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getInt('themeMode') ?? 1; // 0=system,1=dark,2=light
  _themeNotifier.value = [ThemeMode.system, ThemeMode.dark, ThemeMode.light][savedTheme.clamp(0,2)];
  runApp(const ConvoApp());
}

// ─── CONSTANTS ────────────────────────────────────────
const kGreen = Color(0xFF00C853);
const kDark  = Color(0xFF0A0A0A);
const kCard  = Color(0xFF1A1A1A);
const kCard2 = Color(0xFF222222);

final _db   = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;
final _themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

// ─── APP ──────────────────────────────────────────────
class ConvoApp extends StatelessWidget {
  const ConvoApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: _themeNotifier,
    builder: (_, mode, __) => MaterialApp(
      title: 'Convo', debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.dark,
        scaffoldBackgroundColor: kDark,
        navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF111111))),
      home: const SplashScreen(),
    ));
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
            boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 8))]),
          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 54))),
        const SizedBox(height: 24),
        const Text('Convo', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('powered by TheKami', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]))));
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
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) { setState(() => _error = 'Fill all fields'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signInWithEmailAndPassword(email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      await _afterLogin();
    } on FirebaseAuthException catch (e) { setState(() => _error = _err(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final gUser = await GoogleSignIn().signIn();
      if (gUser == null) { setState(() => _loading = false); return; }
      final gAuth = await gUser.authentication;
      final cred = GoogleAuthProvider.credential(accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final result = await _auth.signInWithCredential(cred);
      final isNew = await _ensureUserDoc(result.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: result.user!)));
      } else {
        await _afterLogin();
      }
    } on FirebaseAuthException catch (e) { setState(() => _error = _err(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _githubSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _auth.signInWithProvider(GithubAuthProvider());
      final isNew = await _ensureUserDoc(result.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: result.user!)));
      } else {
        await _afterLogin();
      }
    } on FirebaseAuthException catch (e) { setState(() => _error = _err(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.isEmpty) { setState(() => _error = 'Enter phone number'); return; }
    setState(() { _loading = true; _error = null; });
    await _auth.verifyPhoneNumber(
      phoneNumber: _phoneCtrl.text.trim(),
      verificationCompleted: (cred) async {
        final r = await _auth.signInWithCredential(cred);
        final isNew = await _ensureUserDoc(r.user!);
        if (isNew) {
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: r.user!)));
        } else {
          await _afterLogin();
        }
      },
      verificationFailed: (e) => setState(() { _error = _err(e.code); _loading = false; }),
      codeSent: (vId, _) => setState(() { _verificationId = vId; _otpSent = true; _loading = false; }),
      codeAutoRetrievalTimeout: (_) {});
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.isEmpty || _verificationId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otpCtrl.text.trim());
      final r = await _auth.signInWithCredential(cred);
      final isNew = await _ensureUserDoc(r.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: r.user!)));
      } else {
        await _afterLogin();
      }
    } on FirebaseAuthException catch (e) { setState(() => _error = _err(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  String _err(String code) {
    switch (code) {
      case 'user-not-found': return 'No account with this email.';
      case 'wrong-password': return 'Wrong password.';
      case 'invalid-email': return 'Invalid email.';
      case 'too-many-requests': return 'Too many attempts. Try later.';
      default: return 'Something went wrong.';
    }
  }

  // Returns true if this is a brand-new user (needs username setup)
  Future<bool> _ensureUserDoc(User user) async {
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      // New user — do NOT generate username here; let UsernameSetupScreen handle it
      return true;
    }
    return false;
  }

  Future<void> _afterLogin() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await _db.collection('users').doc(uid).update({'isOnline': true});
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  void _forgotPass() {
    final c = TextEditingController(text: _emailCtrl.text);
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(controller: c, decoration: InputDecoration(hintText: 'Email',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () async { if (c.text.isNotEmpty) { await _auth.sendPasswordResetEmail(email: c.text.trim()); Navigator.pop(context); } },
          child: const Text('Send', style: TextStyle(color: Colors.white))),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          const Text('Welcome back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Sign in to continue', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) _errorBox(_error!),

          if (!_showPhone) ...[
            _tf('Email', Icons.email_outlined, _emailCtrl, false, isDark, bg),
            const SizedBox(height: 14),
            TextField(controller: _passCtrl, obscureText: _obscure,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Password', hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
                  onPressed: () => setState(() => _obscure = !_obscure)),
                filled: true, fillColor: bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
            Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: _forgotPass, child: const Text('Forgot password?', style: TextStyle(color: kGreen, fontSize: 13)))),
            _btn('Sign In', _loading ? null : _signIn, loading: _loading),
          ],

          if (_showPhone) ...[
            if (!_otpSent) ...[
              _tf('+880 1XXXXXXXXX', Icons.phone_outlined, _phoneCtrl, false, isDark, bg, type: TextInputType.phone),
              const SizedBox(height: 14),
              _btn('Send OTP', _loading ? null : _sendOtp, loading: _loading),
            ] else ...[
              _tf('6-digit OTP', Icons.sms_outlined, _otpCtrl, false, isDark, bg, type: TextInputType.number),
              const SizedBox(height: 14),
              _btn('Verify OTP', _loading ? null : _verifyOtp, loading: _loading),
              Center(child: TextButton(onPressed: () => setState(() { _otpSent = false; _verificationId = null; }),
                child: const Text('Resend OTP', style: TextStyle(color: kGreen)))),
            ],
          ],

          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: kGreen),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: Icon(_showPhone ? Icons.email_outlined : Icons.phone_outlined, color: kGreen, size: 20),
            label: Text(_showPhone ? 'Use Email Instead' : 'Continue with Phone',
              style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600)),
            onPressed: () => setState(() { _showPhone = !_showPhone; _error = null; _otpSent = false; })),

          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Divider(color: Colors.grey[700], thickness: 0.5)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(color: Colors.grey[500], fontSize: 13))),
            Expanded(child: Divider(color: Colors.grey[700], thickness: 0.5)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _oauthBtn(Icons.g_mobiledata_rounded, const Color(0xFFDB4437), 'Google', isDark, bg, _loading ? null : _googleSignIn)),
            const SizedBox(width: 12),
            Expanded(child: _oauthBtn(Icons.code_rounded, isDark ? Colors.white : Colors.black87, 'GitHub', isDark, bg, _loading ? null : _githubSignIn)),
          ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text("Don't have an account? ", style: TextStyle(color: Colors.grey[500])),
            GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: const Text('Register', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 32),
        ]))));
  }

  Widget _oauthBtn(IconData icon, Color iconColor, String label, bool isDark, Color bg, VoidCallback? onPressed) =>
    SizedBox(height: 52, child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: bg, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey[isDark ? 700 : 300]!, width: 1))),
      onPressed: onPressed,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14, fontWeight: FontWeight.w600)),
      ])));
}

// ─── REGISTER ─────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 0;
  bool _obscure = true, _loading = false, _ageConfirmed = false;
  String? _error, _uStatus = '';
  String _gender = '';
  final List<String> _suggestions = [];
  final Map<String, String> _uCache = {}; // cache: username → 'ok'|'taken'
  int _reqId = 0; // increments on every keystroke; stale responses are dropped

  final _nameCtrl  = TextEditingController();
  final _uCtrl     = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();

  void _onUChange(String val) {
    if (val.isEmpty) { setState(() { _uStatus = ''; _suggestions.clear(); }); return; }
    final clean = val.trim().toLowerCase();
    // Instant local checks — zero network needed
    if (!RegExp(r'^[a-z0-9_]*$').hasMatch(clean)) { setState(() { _uStatus = 'invalid'; _suggestions.clear(); }); return; }
    if (clean.length < 3) { setState(() { _uStatus = 'short'; _suggestions.clear(); }); return; }
    if (clean.length > 20) { setState(() { _uStatus = 'long'; _suggestions.clear(); }); return; }
    // Cache hit → show result immediately, zero wait
    if (_uCache.containsKey(clean)) { _applyResult(clean, _uCache[clean]!); return; }
    // Fire Firestore immediately, no debounce
    setState(() => _uStatus = 'checking');
    _checkU(clean);
  }

  void _applyResult(String clean, String result) {
    if (result == 'ok') {
      setState(() { _uStatus = 'ok'; _suggestions.clear(); });
    } else {
      final base = clean.replaceAll(RegExp(r'\d+$'), '');
      setState(() { _uStatus = 'taken'; _suggestions
        ..clear()
        ..addAll(['${base}_official', '${base}x', '${base}real', '${base}${DateTime.now().year % 100}', '${base}__']); });
    }
  }

  Future<void> _checkU(String clean) async {
    if (_uCache.containsKey(clean)) { _applyResult(clean, _uCache[clean]!); return; }
    final myId = ++_reqId;
    final snap = await _db.collection('users').where('username', isEqualTo: clean)
      .limit(1).get(const GetOptions(source: Source.serverAndCache));
    if (!mounted || myId != _reqId) return;
    final result = snap.docs.isEmpty ? 'ok' : 'taken';
    _uCache[clean] = result;
    _applyResult(clean, result);
  }

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _uCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Fill all required fields'); return;
    }
    if (!_ageConfirmed) { setState(() => _error = 'You must be 13 or older'); return; }
    if (_gender.isEmpty) { setState(() => _error = 'Select your gender'); return; }
    if (_uStatus == 'taken') { setState(() => _error = 'Username taken'); return; }
    if (_uStatus != 'ok') { setState(() => _error = 'Choose a valid username'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      await cred.user!.sendEmailVerification();
      // Save user doc immediately (fast) — FCM token fetched in background
      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid, 'name': _nameCtrl.text.trim(),
        'username': _uCtrl.text.trim().toLowerCase(),
        'email': _emailCtrl.text.trim(), 'phone': _phoneCtrl.text.trim(),
        'avatar': _nameCtrl.text.trim()[0].toUpperCase(), 'gender': _gender,
        'verified': false, 'verifiedWaitlist': false,
        'suggestionsEnabled': true, 'friendsPublic': true,
        'profileMode': 'friend',
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'phoneNormalized': '',
        'social': {'facebook': '', 'instagram': '', 'github': '', 'linkedin': '', 'twitter': ''},
        'followerCount': 0, 'followingCount': 0, 'friendCount': 0,
        'fcmToken': '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Update FCM token in background — don't block account creation
      FirebaseMessaging.instance.getToken().then((fcm) {
        if (fcm != null) _db.collection('users').doc(cred.user!.uid).update({'fcmToken': fcm});
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

    Color uColor = Colors.grey; IconData uIcon = Icons.alternate_email; String uHint = '';
    if (_uStatus == 'checking') { uColor = Colors.orange; uHint = 'Checking...'; }
    else if (_uStatus == 'ok') { uColor = kGreen; uIcon = Icons.check_circle_outline; uHint = 'Available'; }
    else if (_uStatus == 'taken') { uColor = Colors.red; uIcon = Icons.cancel_outlined; uHint = 'Not available'; }
    else if (_uStatus == 'short') { uColor = Colors.orange; uHint = 'Minimum 3 characters'; }
    else if (_uStatus == 'long') { uColor = Colors.red; uHint = 'Maximum 20 characters'; }
    else if (_uStatus == 'invalid') { uColor = Colors.red; uHint = 'Only a-z, 0-9 and _ allowed'; }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () {
          if (_step == 1) setState(() => _step = 0);
          else Navigator.pop(context);
        })),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_step == 0 ? 'About You' : 'Account Setup', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(_step == 0 ? 'Tell us a bit about yourself' : 'Choose your username and password',
            style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) _errorBox(_error!),

          if (_step == 0) ...[
            _tf('Full Name *', Icons.person_outline, _nameCtrl, false, isDark, bg),
            const SizedBox(height: 14),
            _tf('Email address *', Icons.email_outlined, _emailCtrl, false, isDark, bg, type: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _tf('Phone number (optional)', Icons.phone_outlined, _phoneCtrl, false, isDark, bg, type: TextInputType.phone),
            const SizedBox(height: 20),
            Text('Gender *', style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(children: ['Male', 'Female', 'Other'].map((g) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => setState(() => _gender = g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _gender == g ? kGreen : bg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _gender == g ? kGreen : Colors.grey.withOpacity(0.3))),
                  child: Text(g, style: TextStyle(color: _gender == g ? Colors.white : Colors.grey[400], fontWeight: FontWeight.w600))))
            )).toList()),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => setState(() => _ageConfirmed = !_ageConfirmed),
              child: Row(children: [
                AnimatedContainer(duration: const Duration(milliseconds: 200),
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: _ageConfirmed ? kGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _ageConfirmed ? kGreen : Colors.grey)),
                  child: _ageConfirmed ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null),
                const SizedBox(width: 10),
                Text('I confirm I am 13 years or older', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              ])),
            const SizedBox(height: 28),
            _btn('Continue', () {
              if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty) { setState(() => _error = 'Fill required fields'); return; }
              if (_gender.isEmpty) { setState(() => _error = 'Select your gender'); return; }
              if (!_ageConfirmed) { setState(() => _error = 'Confirm your age to continue'); return; }
              setState(() { _error = null; _step = 1; });
            }),
          ],

          if (_step == 1) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: _uCtrl, onChanged: _onUChange,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))],
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Username', hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(uIcon, color: uColor),
                  suffixIcon: _uStatus == 'checking' ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))) : null,
                  filled: true, fillColor: bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: uColor, width: 1.5)))),
              if (uHint.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(uHint, style: TextStyle(color: uColor, fontSize: 12))),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: _suggestions.map((s) =>
                  GestureDetector(onTap: () { _uCtrl.text = s; _checkU(s); },
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kGreen.withOpacity(0.4))),
                      child: Text(s, style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w500))))).toList()),
              ],
            ]),
            const SizedBox(height: 14),
            TextField(controller: _passCtrl, obscureText: _obscure,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Password (min 6 chars)', hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
                  onPressed: () => setState(() => _obscure = !_obscure)),
                filled: true, fillColor: bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
            const SizedBox(height: 24),
            _btn('Create Account', _loading ? null : _register, loading: _loading),
          ],
          const SizedBox(height: 32),
        ]))));
  }
}

// ─── USERNAME SETUP (OAuth / Phone new users) ─────────
class UsernameSetupScreen extends StatefulWidget {
  final User user;
  const UsernameSetupScreen({super.key, required this.user});
  @override State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}
class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final _uCtrl = TextEditingController();
  String? _uStatus = '';
  final List<String> _suggestions = [];
  final Map<String, String> _uCache = {};
  int _reqId = 0;
  bool _loading = false;
  String? _error;

  void _onUChange(String val) {
    if (val.isEmpty) { setState(() { _uStatus = ''; _suggestions.clear(); }); return; }
    final clean = val.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]*$').hasMatch(clean)) { setState(() { _uStatus = 'invalid'; _suggestions.clear(); }); return; }
    if (clean.length < 3) { setState(() { _uStatus = 'short'; _suggestions.clear(); }); return; }
    if (clean.length > 20) { setState(() { _uStatus = 'long'; _suggestions.clear(); }); return; }
    if (_uCache.containsKey(clean)) { _applyResult(clean, _uCache[clean]!); return; }
    setState(() => _uStatus = 'checking');
    _checkU(clean);
  }

  void _applyResult(String clean, String result) {
    if (result == 'ok') {
      setState(() { _uStatus = 'ok'; _suggestions.clear(); });
    } else {
      final base = clean.replaceAll(RegExp(r'\d+$'), '');
      setState(() { _uStatus = 'taken'; _suggestions
        ..clear()
        ..addAll(['${base}_official', '${base}x', '${base}real', '${base}${DateTime.now().year % 100}', '${base}__']); });
    }
  }

  Future<void> _checkU(String clean) async {
    if (_uCache.containsKey(clean)) { _applyResult(clean, _uCache[clean]!); return; }
    final myId = ++_reqId;
    final snap = await _db.collection('users').where('username', isEqualTo: clean)
      .limit(1).get(const GetOptions(source: Source.serverAndCache));
    if (!mounted || myId != _reqId) return;
    final result = snap.docs.isEmpty ? 'ok' : 'taken';
    _uCache[clean] = result;
    _applyResult(clean, result);
  }

  Future<void> _save() async {
    final clean = _uCtrl.text.trim().toLowerCase();
    if (_uStatus != 'ok') { setState(() => _error = 'Choose a valid, available username'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final u = widget.user;
      final name = u.displayName ?? u.email?.split('@').first ?? u.phoneNumber ?? 'User';
      await _db.collection('users').doc(u.uid).set({
        'uid': u.uid, 'name': name,
        'username': clean,
        'email': u.email ?? '', 'phone': u.phoneNumber ?? '',
        'avatar': name[0].toUpperCase(), 'gender': '',
        'verified': false, 'verifiedWaitlist': false,
        'suggestionsEnabled': true, 'friendsPublic': true,
        'profileMode': 'friend',
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'phoneNormalized': '',
        'social': {'facebook': '', 'instagram': '', 'github': '', 'linkedin': '', 'twitter': ''},
        'followerCount': 0, 'followingCount': 0, 'friendCount': 0,
        'fcmToken': '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      // FCM token in background — don't slow down first login
      FirebaseMessaging.instance.getToken().then((fcm) {
        if (fcm != null) _db.collection('users').doc(u.uid).update({'fcmToken': fcm});
      });
      await _db.collection('users').doc(u.uid).update({'isOnline': true});
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } catch (e) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override void dispose() { _uCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;

    Color uColor = Colors.grey; IconData uIcon = Icons.alternate_email; String uHint = '';
    if (_uStatus == 'checking') { uColor = Colors.orange; uHint = 'Checking...'; }
    else if (_uStatus == 'ok')   { uColor = kGreen; uIcon = Icons.check_circle_outline; uHint = 'Available ✓'; }
    else if (_uStatus == 'taken') { uColor = Colors.red; uIcon = Icons.cancel_outlined; uHint = 'Already taken'; }
    else if (_uStatus == 'short') { uColor = Colors.orange; uHint = 'Minimum 3 characters'; }
    else if (_uStatus == 'long')  { uColor = Colors.red; uHint = 'Maximum 20 characters'; }
    else if (_uStatus == 'invalid') { uColor = Colors.red; uHint = 'Only a-z, 0-9 and _ allowed'; }

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
          const Text('Choose your username', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Pick a unique username. You can change it later in settings.',
            style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) _errorBox(_error!),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _uCtrl, onChanged: _onUChange,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))],
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'username', hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(uIcon, color: uColor),
                suffixIcon: _uStatus == 'checking'
                  ? const Padding(padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)))
                  : null,
                filled: true, fillColor: bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: uColor, width: 1.5)))),
            if (uHint.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(uHint, style: TextStyle(color: uColor, fontSize: 12))),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: _suggestions.map((s) =>
                GestureDetector(onTap: () { _uCtrl.text = s; _checkU(s); },
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kGreen.withOpacity(0.4))),
                    child: Text(s, style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w500))))).toList()),
            ],
          ]),
          const SizedBox(height: 24),
          _btn('Continue', _loading ? null : _save, loading: _loading),
          const SizedBox(height: 32),
        ]))));
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
        content: Row(children: [
          const Icon(Icons.notifications_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
            if (n.body != null) Text(n.body!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
        ]),
        backgroundColor: kGreen, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser!.uid;
    return Scaffold(
      body: IndexedStack(index: _idx, children: [
        const ChatsScreen(), const FriendsScreen(), ProfileScreen(uid: uid), const SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx, onDestinationSelected: (i) => setState(() => _idx = i),
        indicatorColor: kGreen.withOpacity(0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded, color: kGreen), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded, color: kGreen), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded, color: kGreen), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded, color: kGreen), label: 'Settings'),
        ]));
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
                  child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));
              }))),
        title: const Text('Convo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          // Message requests badge
          StreamBuilder<QuerySnapshot>(
            stream: _db.collection('message_requests').where('to', isEqualTo: myUid).where('status', isEqualTo: 'pending').snapshots(),
            builder: (_, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(children: [
                IconButton(icon: const Icon(Icons.inbox_rounded),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessageRequestsScreen()))),
                if (count > 0) Positioned(right: 6, top: 6, child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Center(child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))))),
              ]);
            }),
          IconButton(icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen(startChat: true)))),
        ]),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('chats').where('participants', arrayContains: myUid).snapshots(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: kGreen));
          if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 80, height: 80, decoration: BoxDecoration(color: kGreen.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: kGreen)),
            const SizedBox(height: 16),
            const Text('No conversations yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Find friends and start chatting!', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ]));

          final docs = snap.data!.docs.toList()..sort((a, b) {
            final aTs = (a.data() as Map)['lastTimestamp'];
            final bTs = (b.data() as Map)['lastTimestamp'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1; if (bTs == null) return -1;
            return (bTs as dynamic).compareTo(aTs);
          });

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(height: 0, color: Colors.grey.withOpacity(0.08), indent: 76),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final parts = List<String>.from(data['participants'] ?? []);
              final other = parts.firstWhere((u) => u != myUid, orElse: () => '');
              return _ChatTile(chatData: data, otherUid: other, myUid: myUid, chatId: docs[i].id);
            });
        }));
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chatData;
  final String otherUid, myUid, chatId;
  const _ChatTile({required this.chatData, required this.otherUid, required this.myUid, required this.chatId});

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
      final nickname = chatData['nickname_$myUid'] as String?;
      final displayName = nickname ?? name;

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(children: [
          CircleAvatar(radius: 26, backgroundColor: kGreen,
            child: Text(avatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
          if (online) Positioned(right: 0, bottom: 0, child: Container(width: 13, height: 13,
            decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
        ]),
        title: Row(children: [
          Expanded(child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          Text(_timeAgo(lastTs), style: TextStyle(color: unread > 0 ? kGreen : Colors.grey[500], fontSize: 12,
            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
        ]),
        subtitle: Row(children: [
          if (isMine) const Icon(Icons.done_all_rounded, size: 14, color: kGreen),
          if (isMine) const SizedBox(width: 4),
          Expanded(child: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: unread > 0 ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey[500],
              fontSize: 13, fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal))),
          if (unread > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(10)),
            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatScreen(otherUid: otherUid, otherName: name, otherAvatar: avatar, chatId: chatId))));
    });
}

// ─── MESSAGE REQUESTS SCREEN ──────────────────────────
class MessageRequestsScreen extends StatelessWidget {
  const MessageRequestsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Message Requests', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('message_requests').where('to', isEqualTo: myUid).where('status', isEqualTo: 'pending').orderBy('timestamp', descending: true).snapshots(),
        builder: (_, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text('No message requests', style: TextStyle(color: Colors.grey[500])),
          ]));
          return ListView(children: snap.data!.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return ListTile(
              leading: CircleAvatar(backgroundColor: kGreen,
                child: Text(d['fromAvatar'] ?? 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              title: Text(d['fromName'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(d['lastMessage'] ?? 'Wants to send you a message', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () async {
                    await _db.collection('message_requests').doc(doc.id).update({'status': 'accepted'});
                    // Also make friends
                    await _db.collection('users').doc(myUid).collection('friends').doc(d['from']).set({'uid': d['from'], 'since': FieldValue.serverTimestamp()});
                    await _db.collection('users').doc(d['from']).collection('friends').doc(myUid).set({'uid': myUid, 'since': FieldValue.serverTimestamp()});
                    // Open chat
                    final ids = [myUid, d['from'] as String]..sort();
                    final chatId = ids.join('_');
                    if (context.mounted) Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatScreen(otherUid: d['from'], otherName: d['fromName'] ?? 'User', otherAvatar: d['fromAvatar'] ?? 'U', chatId: chatId)));
                  },
                  child: Container(width: 38, height: 38, decoration: BoxDecoration(color: kGreen.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: kGreen, size: 22))),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _db.collection('message_requests').doc(doc.id).update({'status': 'declined'}),
                  child: Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.red, size: 22))),
              ]),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: d['from']))));
          }).toList());
        }));
  }
}

// ─── CHAT SCREEN ──────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String otherUid, otherName, otherAvatar, chatId;
  const ChatScreen({super.key, required this.otherUid, required this.otherName, required this.otherAvatar, required this.chatId});
  @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _replyToId, _replyToText, _replyToSender;
  int? _disappearSeconds; // null = off
  late String _myUid;
  Timer? _typingTimer;
  bool _isTyping = false;

  static const _disappearOptions = [
    {'label': 'Off', 'seconds': null},
    {'label': '12 hours', 'seconds': 43200},
    {'label': '24 hours', 'seconds': 86400},
    {'label': '7 days', 'seconds': 604800},
  ];

  @override void initState() {
    super.initState();
    _myUid = _auth.currentUser!.uid;
    _clearUnread();
    _loadDisappearSetting();
    _msgCtrl.addListener(_onTyping);
  }

  @override void dispose() {
    _setTyping(false);
    _msgCtrl.removeListener(_onTyping);
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDisappearSetting() async {
    final doc = await _db.collection('chats').doc(widget.chatId).get();
    if (doc.exists && mounted) {
      setState(() => _disappearSeconds = (doc.data() as Map?)?['disappearSeconds']);
    }
  }

  void _onTyping() {
    _typingTimer?.cancel();
    _setTyping(true);
    _typingTimer = Timer(const Duration(seconds: 3), () => _setTyping(false));
  }

  Future<void> _setTyping(bool v) async {
    _isTyping = v;
    await _db.collection('chats').doc(widget.chatId).collection('typing').doc(_myUid).set({
      'isTyping': v, 'ts': FieldValue.serverTimestamp()});
  }

  Future<void> _clearUnread() async =>
    await _db.collection('chats').doc(widget.chatId).set({'unread_$_myUid': 0}, SetOptions(merge: true));

  Future<void> _send(String text) async {
    final t = text.trim(); if (t.isEmpty) return;
    _msgCtrl.clear(); _setTyping(false);
    final reply = _replyToId != null ? {'id': _replyToId, 'text': _replyToText, 'sender': _replyToSender} : null;
    setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; });

    final expiresAt = _disappearSeconds != null
      ? Timestamp.fromDate(DateTime.now().add(Duration(seconds: _disappearSeconds!))) : null;

    await _db.collection('chats').doc(widget.chatId).collection('messages').add({
      'text': t, 'senderId': _myUid,
      'senderName': _auth.currentUser?.displayName ?? 'User',
      'timestamp': FieldValue.serverTimestamp(), 'deleted': false,
      if (reply != null) 'reply': reply,
      if (expiresAt != null) 'expiresAt': expiresAt,
    });
    await _db.collection('chats').doc(widget.chatId).set({
      'participants': [_myUid, widget.otherUid],
      'lastMessage': t, 'lastTimestamp': FieldValue.serverTimestamp(), 'lastSender': _myUid,
      'unread_${widget.otherUid}': FieldValue.increment(1), 'unread_$_myUid': 0,
    }, SetOptions(merge: true));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _showChatSettings() {
    showModalBottomSheet(context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Chat Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft,
            child: Text('Disappearing Messages', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          const SizedBox(height: 10),
          ..._disappearOptions.map((opt) => RadioListTile<int?>(
            value: opt['seconds'] as int?,
            groupValue: _disappearSeconds,
            activeColor: kGreen,
            title: Text(opt['label'] as String),
            onChanged: (v) async {
              setSt(() {});
              setState(() => _disappearSeconds = v);
              await _db.collection('chats').doc(widget.chatId).set({'disappearSeconds': v}, SetOptions(merge: true));
            })).toList(),
          const SizedBox(height: 8),
          // Nickname option
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: kGreen),
            title: const Text('Set Nickname'),
            subtitle: const Text('Give this chat a nickname'),
            onTap: () {
              Navigator.pop(context);
              final c = TextEditingController();
              showDialog(context: context, builder: (_) => AlertDialog(
                title: const Text('Set Nickname'),
                content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Nickname...')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kGreen),
                    onPressed: () async {
                      await _db.collection('chats').doc(widget.chatId).set({'nickname_$_myUid': c.text.trim()}, SetOptions(merge: true));
                      if (context.mounted) Navigator.pop(context);
                    }, child: const Text('Save', style: TextStyle(color: Colors.white))),
                ]));
            }),
        ]))));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
                stream: _db.collection('chats').doc(widget.chatId).collection('typing').doc(widget.otherUid).snapshots(),
                builder: (_, tSnap) {
                  final isTyping = tSnap.data?.get('isTyping') == true;
                  if (isTyping) return Row(children: [
                    const _TypingDots(),
                    const SizedBox(width: 4),
                    Text('typing...', style: TextStyle(color: kGreen, fontSize: 11)),
                  ]);
                  return StreamBuilder<DocumentSnapshot>(
                    stream: _db.collection('users').doc(widget.otherUid).snapshots(),
                    builder: (_, snap) {
                      final online = snap.data?.get('isOnline') == true;
                      return Text(online ? 'Online' : 'Offline', style: TextStyle(color: online ? kGreen : Colors.grey, fontSize: 11));
                    });
                }),
            ]),
          ])),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _showChatSettings),
        ]),
      body: Column(children: [
        if (_disappearSeconds != null) Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6),
          color: kGreen.withOpacity(0.1),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.timer_outlined, color: kGreen, size: 14),
            const SizedBox(width: 4),
            Text('Disappearing messages: ${_disappearOptions.firstWhere((o) => o['seconds'] == _disappearSeconds)['label']}',
              style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w500)),
          ])),

        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('chats').doc(widget.chatId).collection('messages').orderBy('timestamp').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kGreen));
            // Filter expired messages client-side
            final now = Timestamp.now();
            final msgs = snap.data!.docs.where((d) {
              final exp = (d.data() as Map)['expiresAt'] as Timestamp?;
              return exp == null || exp.compareTo(now) > 0;
            }).toList();

            if (msgs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.waving_hand_rounded, size: 48, color: kGreen),
              const SizedBox(height: 12),
              Text('Say hi to ${widget.otherName}!', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
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
                  msgId: msgs[i].id, data: data, isMe: isMe, isFirst: isFirst, chatId: widget.chatId,
                  onReply: (id, text, sender) => setState(() { _replyToId = id; _replyToText = text; _replyToSender = sender; }));
              });
          })),

        if (_replyToId != null) Container(
          color: isDark ? kCard2 : Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(width: 3, height: 36, decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_replyToSender ?? '', style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() { _replyToId = null; _replyToText = null; _replyToSender = null; })),
          ])),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(color: isDark ? kCard : Colors.white,
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
      ]));
  }
}

// ─── TYPING DOTS ANIMATION ────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override State<_TypingDots> createState() => _TypingDotsState();
}
class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  @override void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true, period: Duration(milliseconds: 900 + i * 150)));
  }
  @override void dispose() { for (final c in _ctrls) c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) =>
    Padding(padding: const EdgeInsets.only(right: 2),
      child: AnimatedBuilder(animation: _ctrls[i], builder: (_, __) => Transform.translate(
        offset: Offset(0, -3 * _ctrls[i].value),
        child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle)))))));
}

// ─── BUBBLE ───────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final String msgId, chatId;
  final Map<String, dynamic> data;
  final bool isMe, isFirst;
  final void Function(String, String, String) onReply;
  const _Bubble({required this.msgId, required this.chatId, required this.data, required this.isMe, required this.isFirst, required this.onReply});

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = data['text'] as String? ?? '';
    final deleted = data['deleted'] == true;
    final reply = data['reply'] as Map<String, dynamic>?;
    final ts = data['timestamp'] as Timestamp?;
    final expiresAt = data['expiresAt'] as Timestamp?;

    return GestureDetector(
      onHorizontalDragEnd: (d) { if (!deleted && (d.primaryVelocity ?? 0) < -100) onReply(msgId, text, data['senderName'] ?? ''); },
      onLongPress: () {
        if (deleted) return;
        showModalBottomSheet(context: context,
          backgroundColor: isDark ? kCard : Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(leading: const Icon(Icons.reply_rounded, color: kGreen), title: const Text('Reply'),
              onTap: () { Navigator.pop(context); onReply(msgId, text, data['senderName'] ?? ''); }),
            ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy'),
              onTap: () { Navigator.pop(context); Clipboard.setData(ClipboardData(text: text)); }),
            if (isMe) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.red), title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _db.collection('chats').doc(chatId).collection('messages').doc(msgId).update({'deleted': true, 'text': 'Message deleted'}); }),
            const SizedBox(height: 12),
          ]));
      },
      child: Padding(
        padding: EdgeInsets.only(top: isFirst ? 8 : 2, bottom: 2, left: isMe ? 56 : 0, right: isMe ? 0 : 56),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Container(
              decoration: BoxDecoration(
                color: isMe ? kGreen : (isDark ? kCard2 : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4), bottomRight: Radius.circular(isMe ? 4 : 18)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (reply != null) Container(
                    margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
                      border: const Border(left: BorderSide(color: Colors.white54, width: 3))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(reply['sender'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(reply['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ])),
                  Text(text, style: TextStyle(
                    color: deleted ? (isMe ? Colors.white54 : Colors.grey[500]) : (isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color),
                    fontSize: 15, fontStyle: deleted ? FontStyle.italic : FontStyle.normal)),
                ]))),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_fmt(ts), style: TextStyle(color: Colors.grey[500], fontSize: 10)),
              if (expiresAt != null) ...[const SizedBox(width: 4), const Icon(Icons.timer_outlined, size: 10, color: Colors.grey)],
            ]),
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

  Future<void> _sendRequest(String toUid, String toName, String toAvatar) async {
    // Check if already friends
    final fd = await _db.collection('users').doc(_myUid).collection('friends').doc(toUid).get();
    if (fd.exists) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already friends!'), backgroundColor: kGreen)); return; }

    // Check mode of target user
    final targetDoc = await _db.collection('users').doc(toUid).get();
    final targetMode = targetDoc.data()?['profileMode'] ?? 'friend';

    if (targetMode == 'follow') {
      // Just follow
      await _db.collection('users').doc(_myUid).collection('following').doc(toUid).set({'uid': toUid, 'since': FieldValue.serverTimestamp()});
      await _db.collection('users').doc(toUid).collection('followers').doc(_myUid).set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
      await _db.collection('users').doc(toUid).update({'followerCount': FieldValue.increment(1)});
      await _db.collection('users').doc(_myUid).update({'followingCount': FieldValue.increment(1)});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Now following $toName'), backgroundColor: kGreen));
    } else {
      // Send friend request
      final ex = await _db.collection('friend_requests').where('from', isEqualTo: _myUid).where('to', isEqualTo: toUid).where('status', isEqualTo: 'pending').get();
      if (ex.docs.isNotEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request already sent!'))); return; }
      final my = await _db.collection('users').doc(_myUid).get();
      await _db.collection('friend_requests').add({
        'from': _myUid, 'fromName': my.data()?['name'] ?? 'User', 'fromAvatar': my.data()?['avatar'] ?? 'U',
        'to': toUid, 'toName': toName, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request sent to $toName'), backgroundColor: kGreen));
    }
  }

  Future<void> _accept(String docId, String fromUid) async {
    await _db.collection('friend_requests').doc(docId).update({'status': 'accepted'});
    await _db.collection('users').doc(_myUid).collection('friends').doc(fromUid).set({'uid': fromUid, 'since': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(fromUid).collection('friends').doc(_myUid).set({'uid': _myUid, 'since': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(_myUid).update({'friendCount': FieldValue.increment(1)});
    await _db.collection('users').doc(fromUid).update({'friendCount': FieldValue.increment(1)});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend added!'), backgroundColor: kGreen));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? kCard : Colors.grey[100]!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.startChat ? 'New Message' : 'Friends', style: const TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(controller: _tab, indicatorColor: kGreen, labelColor: kGreen, unselectedLabelColor: Colors.grey,
          tabs: const [Tab(icon: Icon(Icons.search_rounded), text: 'Search'), Tab(icon: Icon(Icons.notifications_outlined), text: 'Requests'), Tab(icon: Icon(Icons.people_rounded), text: 'Friends')])),
      body: TabBarView(controller: _tab, children: [
        Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: TextField(
            controller: _searchCtrl, onChanged: _search,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(hintText: 'Search by username...', hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey), filled: true, fillColor: bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
          if (_searching) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: kGreen))
          else Expanded(child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final u = _results[i]; if (u['uid'] == _myUid) return const SizedBox();
              return ListTile(
                leading: CircleAvatar(backgroundColor: kGreen,
                  child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                title: Text(u['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('@${u['username']}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                trailing: widget.startChat
                  ? FilledButton(style: FilledButton.styleFrom(backgroundColor: kGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        final ids = [_myUid, u['uid'] as String]..sort();
                        final chatId = ids.join('_');
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(otherUid: u['uid'], otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?', chatId: chatId)));
                      }, child: const Text('Message'))
                  : StreamBuilder<DocumentSnapshot>(
                      stream: _db.collection('users').doc(_myUid).collection('friends').doc(u['uid'] as String).snapshots(),
                      builder: (_, friendSnap) {
                        if (friendSnap.data?.exists == true) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Text('Friends', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)));
                        }
                        return OutlinedButton(style: OutlinedButton.styleFrom(side: const BorderSide(color: kGreen), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          onPressed: () => _sendRequest(u['uid'], u['name'] ?? 'User', u['avatar'] ?? 'U'),
                          child: Text(u['profileMode'] == 'follow' ? 'Follow' : 'Add', style: const TextStyle(color: kGreen)));
                      }),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: u['uid']))));
            })),
        ]),

        // Requests tab
        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('friend_requests')
            .where('to', isEqualTo: _myUid)
            .where('status', isEqualTo: 'pending')
            .snapshots(),
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}', style: const TextStyle(color: Colors.red)));
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.inbox_rounded, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 12),
              Text('No pending requests', style: TextStyle(color: Colors.grey[500])),
            ]));
            // Sort client-side (newest first) — avoids Firestore composite index requirement
            final docs = snap.data!.docs.toList()..sort((a, b) {
              final aTs = (a.data() as Map)['timestamp'];
              final bTs = (b.data() as Map)['timestamp'];
              if (aTs == null && bTs == null) return 0;
              if (aTs == null) return 1; if (bTs == null) return -1;
              return (bTs as dynamic).compareTo(aTs);
            });
            return ListView(children: docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(backgroundColor: kGreen,
                  child: Text(d['fromAvatar'] ?? 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                title: Text(d['fromName'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Sent you a friend request', style: TextStyle(fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(onTap: () => _accept(doc.id, d['from']),
                    child: Container(width: 38, height: 38, decoration: BoxDecoration(color: kGreen.withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: kGreen, size: 22))),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => _db.collection('friend_requests').doc(doc.id).update({'status': 'declined'}),
                    child: Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.red, size: 22))),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: d['from']))));
            }).toList());
          }),

        // My Friends tab
        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('users').doc(_myUid).collection('friends').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 12),
              Text('No friends yet', style: TextStyle(color: Colors.grey[500])),
            ]));
            return ListView(children: snap.data!.docs.map((doc) =>
              StreamBuilder<DocumentSnapshot>(
                stream: _db.collection('users').doc(doc.id).snapshots(),
                builder: (_, uSnap) {
                  final u = uSnap.data?.data() as Map<String, dynamic>? ?? {};
                  final online = u['isOnline'] == true;
                  final ids = [_myUid, doc.id]..sort();
                  final chatId = ids.join('_');
                  return ListTile(
                    leading: Stack(children: [
                      CircleAvatar(backgroundColor: kGreen,
                        child: Text(u['avatar'] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      if (online) Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
                    ]),
                    title: Text(u['name'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(online ? 'Online' : '@${u['username'] ?? ''}', style: TextStyle(color: online ? kGreen : Colors.grey[500], fontSize: 12)),
                    trailing: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kGreen.withOpacity(0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: kGreen, size: 16),
                      label: const Text('Chat', style: TextStyle(color: kGreen, fontSize: 13)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(otherUid: doc.id, otherName: u['name'] ?? 'User', otherAvatar: u['avatar'] ?? '?', chatId: chatId)))),
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

  // kept for _showEdit which needs a one-time snapshot reference
  Future<void> _load() async {
    final doc = await _db.collection('users').doc(widget.uid).get();
    if (mounted) setState(() => _user = doc.data() ?? {});
  }

  @override void initState() { super.initState(); _load(); }

  final _socialPlatforms = [
    {'key': 'facebook',  'icon': Icons.facebook_rounded,  'color': const Color(0xFF1877F2), 'label': 'Facebook',   'prefix': 'https://facebook.com/'},
    {'key': 'instagram', 'icon': Icons.camera_alt_rounded, 'color': const Color(0xFFE1306C), 'label': 'Instagram',  'prefix': 'https://instagram.com/'},
    {'key': 'github',    'icon': Icons.code_rounded,       'color': const Color(0xFF333333), 'label': 'GitHub',     'prefix': 'https://github.com/'},
    {'key': 'linkedin',  'icon': Icons.work_rounded,       'color': const Color(0xFF0077B5), 'label': 'LinkedIn',   'prefix': 'https://linkedin.com/in/'},
    {'key': 'twitter',   'icon': Icons.alternate_email,    'color': const Color(0xFF1DA1F2), 'label': 'X/Twitter',  'prefix': 'https://twitter.com/'},
  ];

  @override
  Widget build(BuildContext context) {
    // Show loading only on very first paint; after that StreamBuilder drives UI
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(widget.uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: kGreen)));
        }
        final data = snap.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Profile')),
            body: const Center(child: Text('User not found')));
        }
        // keep _user in sync for _showEdit
        if (_user == null || _user != data) {
          WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _user = data); });
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final name      = data['name'] as String? ?? 'User';
        final username  = data['username'] as String? ?? '';
        final bio       = data['bio'] as String? ?? '';
        final city      = data['city'] as String? ?? '';
        final education = data['education'] as String? ?? '';
        final work      = data['work'] as String? ?? '';
        final hometown  = data['hometown'] as String? ?? '';
        final verified  = data['verified'] == true;
        final online    = data['isOnline'] == true;
        final social    = data['social'] as Map<String, dynamic>? ?? {};
        final friendCount   = data['friendCount'] ?? 0;
        final followerCount = data['followerCount'] ?? 0;
        final followingCount = data['followingCount'] ?? 0;
        final friendsPublic = data['friendsPublic'] != false;
        final profileMode   = data['profileMode'] as String? ?? 'friend';
        final activeSocials = _socialPlatforms.where((p) => (social[p['key']] as String? ?? '').isNotEmpty).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(_isMe ? 'My Profile' : name, style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [if (_isMe) IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _showEdit(context))]),
          body: SingleChildScrollView(child: Column(children: [
            Container(width: double.infinity,
              decoration: BoxDecoration(gradient: LinearGradient(
                colors: [kGreen.withOpacity(0.25), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              child: Column(children: [
                const SizedBox(height: 28),
                Stack(children: [
                  Container(width: 90, height: 90,
                    decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 20)]),
                    child: Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold)))),
                  if (online) Positioned(right: 2, bottom: 2, child: Container(width: 16, height: 16,
                    decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: isDark ? kDark : Colors.white, width: 2)))),
                ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (verified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: kGreen, size: 20)],
                ]),
                Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? kGreen : Colors.grey, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(online ? 'Online' : 'Offline', style: TextStyle(color: online ? kGreen : Colors.grey[500], fontSize: 12)),
                ]),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(bio, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5))),
                ],
                const SizedBox(height: 16),
                // Stats row
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _statBox(followerCount.toString(), 'Followers', true),
                  Container(width: 1, height: 36, color: Colors.grey.withOpacity(0.3)),
                  if (friendsPublic || _isMe)
                    _statBox(friendCount.toString(), 'Friends', true),
                  if (!friendsPublic && !_isMe)
                    _statBox('—', 'Friends', false),
                  Container(width: 1, height: 36, color: Colors.grey.withOpacity(0.3)),
                  _statBox(followingCount.toString(), 'Following', true),
                ]),
                // ── Action buttons right after stats ──
                if (!_isMe) ...[
                  const SizedBox(height: 16),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: _db.collection('users').doc(_auth.currentUser!.uid).collection('friends').doc(widget.uid).snapshots(),
                      builder: (_, friendSnap) {
                        final isFriend = friendSnap.data?.exists == true;
                        final myUid = _auth.currentUser!.uid;
                        final ids = [myUid, widget.uid]..sort();
                        final chatId = ids.join('_');
                        if (isFriend) {
                          // Already friends — show Chat button
                          return _btn('Send Message', () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                            otherUid: widget.uid, otherName: name,
                            otherAvatar: name[0].toUpperCase(), chatId: chatId))));
                        }
                        // Not yet friends — show Add / Follow button
                        return StreamBuilder<QuerySnapshot>(
                          stream: _db.collection('friend_requests')
                            .where('from', isEqualTo: myUid).where('to', isEqualTo: widget.uid)
                            .where('status', isEqualTo: 'pending').snapshots(),
                          builder: (_, reqSnap) {
                            final requestSent = (reqSnap.data?.docs.isNotEmpty) == true;
                            return Row(children: [
                              Expanded(child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: requestSent ? Colors.grey : kGreen),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                icon: Icon(requestSent ? Icons.hourglass_top_rounded : (profileMode == 'follow' ? Icons.person_add_rounded : Icons.person_add_alt_1_rounded),
                                  color: requestSent ? Colors.grey : kGreen, size: 18),
                                label: Text(requestSent ? 'Requested' : (profileMode == 'follow' ? 'Follow' : 'Add Friend'),
                                  style: TextStyle(color: requestSent ? Colors.grey : kGreen, fontWeight: FontWeight.bold)),
                                onPressed: requestSent ? null : () async {
                                  if (profileMode == 'follow') {
                                    await _db.collection('users').doc(myUid).collection('following').doc(widget.uid).set({'uid': widget.uid, 'since': FieldValue.serverTimestamp()});
                                    await _db.collection('users').doc(widget.uid).collection('followers').doc(myUid).set({'uid': myUid, 'since': FieldValue.serverTimestamp()});
                                    await _db.collection('users').doc(widget.uid).update({'followerCount': FieldValue.increment(1)});
                                    await _db.collection('users').doc(myUid).update({'followingCount': FieldValue.increment(1)});
                                  } else {
                                    final my = await _db.collection('users').doc(myUid).get();
                                    await _db.collection('friend_requests').add({
                                      'from': myUid, 'fromName': my.data()?['name'] ?? 'User', 'fromAvatar': my.data()?['avatar'] ?? 'U',
                                      'to': widget.uid, 'toName': name, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
                                    });
                                  }
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(profileMode == 'follow' ? 'Following $name' : 'Friend request sent!'), backgroundColor: kGreen));
                                })),
                              const SizedBox(width: 10),
                              Expanded(child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 18),
                                label: const Text('Message', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                                  otherUid: widget.uid, otherName: name,
                                  otherAvatar: name[0].toUpperCase(), chatId: chatId))))),
                            ]);
                          });
                      })),
                ],
                const SizedBox(height: 16),
              ])),

            if (city.isNotEmpty || hometown.isNotEmpty || education.isNotEmpty || work.isNotEmpty) ...[
              _secTitle('About'),
              if (city.isNotEmpty) _infoRow(Icons.location_city_rounded, 'City', city),
              if (hometown.isNotEmpty) _infoRow(Icons.home_rounded, 'Hometown', hometown),
              if (education.isNotEmpty) _infoRow(Icons.school_rounded, 'Education', education),
              if (work.isNotEmpty) _infoRow(Icons.work_rounded, 'Work', work),
            ],

            if (activeSocials.isNotEmpty) ...[
              _secTitle('Socials'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(spacing: 10, runSpacing: 10, children: activeSocials.map((p) {
                  final uname = social[p['key']] as String;
                  return GestureDetector(
                    onTap: () => launchUrl(Uri.parse('${p['prefix']}$uname'), mode: LaunchMode.externalApplication),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: (p['color'] as Color).withOpacity(0.1), borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (p['color'] as Color).withOpacity(0.3))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(p['icon'] as IconData, color: p['color'] as Color, size: 18),
                        const SizedBox(width: 7),
                        Text('@$uname', style: TextStyle(color: p['color'] as Color, fontWeight: FontWeight.w600, fontSize: 12)),
                      ])));
                }).toList())),
            ],

            const SizedBox(height: 32),
          ])));
      });
  }

  Widget _statBox(String val, String label, bool visible) => SizedBox(width: 90,
    child: Column(children: [
      Text(visible ? val : '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
    ]));

  Widget _secTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: Colors.grey.withOpacity(0.3))),
    ]));

  Widget _infoRow(IconData icon, String label, String value) => ListTile(dense: true,
    leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
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
    final socialCtrls = {for (final p in _socialPlatforms) p['key'] as String: TextEditingController(text: social[p['key']] ?? '')};

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
          _ef('Work', wc), const SizedBox(height: 20),
          Align(alignment: Alignment.centerLeft, child: Text('Social Links', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[400]))),
          const SizedBox(height: 10),
          ...(_socialPlatforms.map((p) => Padding(padding: const EdgeInsets.only(bottom: 10),
            child: TextField(controller: socialCtrls[p['key']],
              decoration: InputDecoration(hintText: '${p['label']} username',
                prefixIcon: Icon(p['icon'] as IconData, color: p['color'] as Color, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p['color'] as Color)))))).toList()),
          const SizedBox(height: 16),
          _btn('Save Changes', () async {
            final newSocial = {for (final p in _socialPlatforms) p['key'] as String: socialCtrls[p['key']]!.text.trim()};
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
  Widget _ef(String label, TextEditingController ctrl, {int lines = 1}) => TextField(controller: ctrl, maxLines: lines,
    decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen))));
}

// ─── SETTINGS ─────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  bool _suggestions = true, _friendsPublic = true;
  String _profileMode = 'friend';
  Map<String, dynamic>? _user;
  final _myUid = _auth.currentUser!.uid;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final doc = await _db.collection('users').doc(_myUid).get();
    if (mounted) setState(() {
      _user = doc.data();
      _suggestions = doc.data()?['suggestionsEnabled'] ?? true;
      _friendsPublic = doc.data()?['friendsPublic'] ?? true;
      _profileMode = doc.data()?['profileMode'] ?? 'friend';
    });
  }

  Future<void> _signOut() async {
    await _db.collection('users').doc(_myUid).update({'isOnline': false});
    await _auth.signOut();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _update(Map<String, dynamic> data) async => await _db.collection('users').doc(_myUid).update(data);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = _user?['verified'] == true;
    final onWaitlist = _user?['verifiedWaitlist'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)), elevation: 0),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _db.collection('users').doc(_myUid).snapshots(),
        builder: (_, snap) {
          // Update local state from stream so phone/name always reflect latest
          if (snap.hasData && snap.data!.exists) {
            final d = snap.data!.data() as Map<String, dynamic>;
            if (_user == null || d['name'] != _user!['name'] || d['phone'] != _user!['phone']) {
              // schedule update after build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {
                  _user = d;
                  _suggestions = d['suggestionsEnabled'] ?? true;
                  _friendsPublic = d['friendsPublic'] ?? true;
                  _profileMode = d['profileMode'] ?? 'friend';
                });
              });
            }
          }
          final name     = snap.data?.get('name') as String? ?? _user?['name'] as String? ?? 'User';
          final username = snap.data?.get('username') as String? ?? _user?['username'] as String? ?? '';
          final phone    = snap.data?.get('phone') as String? ?? _user?['phone'] as String? ?? '';
          final isVerified = snap.data?.get('verified') == true || verified;

          return ListView(children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid))),
            child: Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [kGreen.withOpacity(0.15), kGreen.withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(16), border: Border.all(color: kGreen.withOpacity(0.3))),
              child: Row(children: [
                CircleAvatar(radius: 28, backgroundColor: kGreen,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified_rounded, color: kGreen, size: 16)],
                  ]),
                  if (username.isNotEmpty) Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  const Text('View profile', style: TextStyle(color: kGreen, fontSize: 11)),
                ])),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
              ])),
          ),

          _sec('Account'),
          _t(Icons.person_rounded, 'Edit Profile', 'Name, bio, socials', () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: _myUid)))),
          _t(Icons.phone_rounded, 'Phone Number', phone.isNotEmpty ? phone : 'Add phone number', () => _addPhone(context)),
          _t(Icons.contacts_rounded, 'Sync Contacts', 'Find friends from your contacts', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactSyncScreen()))),
          _t(Icons.lock_rounded, 'Change Password', 'Update your password', () => _changePass(context)),
          _t(Icons.verified_rounded, 'Get Verified', isVerified ? 'You are verified!' : (onWaitlist ? 'On waitlist' : 'Join the waitlist'), () => _verify(context)),

          _sec('Profile Mode'),
          Container(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: isDark ? kCard : Colors.grey[100], borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () { setState(() => _profileMode = 'friend'); _update({'profileMode': 'friend'}); },
                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _profileMode == 'friend' ? kGreen : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text('Friend Mode', style: TextStyle(color: _profileMode == 'friend' ? Colors.white : Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)))))),
              Expanded(child: GestureDetector(
                onTap: () { setState(() => _profileMode = 'follow'); _update({'profileMode': 'follow'}); },
                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _profileMode == 'follow' ? kGreen : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text('Follow Mode', style: TextStyle(color: _profileMode == 'follow' ? Colors.white : Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)))))),
            ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_profileMode == 'friend' ? 'Others can send you friend requests and message you.' : 'Others can follow you. Use for public/creator profiles.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12))),

          _sec('Privacy'),
          SwitchListTile(value: _friendsPublic, onChanged: (v) { setState(() => _friendsPublic = v); _update({'friendsPublic': v}); },
            activeColor: kGreen, secondary: _ib(Icons.people_rounded),
            title: const Text('Public Friends List', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('Show your friends on your profile', style: TextStyle(color: Colors.grey[500], fontSize: 12))),

          _sec('Discovery'),
          SwitchListTile(value: _suggestions, onChanged: (v) { setState(() => _suggestions = v); _update({'suggestionsEnabled': v}); },
            activeColor: kGreen, secondary: _ib(Icons.person_search_rounded),
            title: const Text('Account Suggestions', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('Suggest your profile to others', style: TextStyle(color: Colors.grey[500], fontSize: 12))),

          _sec('Preferences'),
          _t(Icons.notifications_rounded, 'Notifications', 'Manage push alerts', () {}),
          _t(Icons.palette_rounded, 'Appearance', 'Theme and colors', () => _showThemeDialog(context)),
          _t(Icons.language_rounded, 'Language', 'Bangla / English', () {}),

          _sec('About'),
          _t(Icons.favorite_rounded, 'Powered by TheKami', 'thekami.tech', () => launchUrl(Uri.parse('https://thekami.tech'), mode: LaunchMode.externalApplication)),
          _t(Icons.info_rounded, 'App Version', 'Convo v1.0.2', () {}),

          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), elevation: 0,
                minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              icon: const Icon(Icons.logout_rounded, color: Colors.red),
              label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onPressed: _signOut)),
          const SizedBox(height: 32),
        ]);
        }
      ));
  }

  void _showThemeDialog(BuildContext context) {
    showModalBottomSheet(context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Appearance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...[
            [ThemeMode.dark,   Icons.dark_mode_rounded,  'Dark'],
            [ThemeMode.light,  Icons.light_mode_rounded, 'Light'],
            [ThemeMode.system, Icons.brightness_auto_rounded, 'System Default'],
          ].map((opt) {
            final mode  = opt[0] as ThemeMode;
            final icon  = opt[1] as IconData;
            final label = opt[2] as String;
            final selected = _themeNotifier.value == mode;
            return ListTile(
              leading: Icon(icon, color: selected ? kGreen : Colors.grey),
              title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              trailing: selected ? const Icon(Icons.check_circle_rounded, color: kGreen) : null,
              onTap: () async {
                _themeNotifier.value = mode;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('themeMode', [ThemeMode.system, ThemeMode.dark, ThemeMode.light].indexOf(mode));
                setSt(() {});
              });
          }).toList(),
          const SizedBox(height: 8),
        ]))));
  }

  void _addPhone(BuildContext context) {
    final ctrl = TextEditingController(text: _user?['phone'] ?? '');
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Phone Number'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrl, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '+880 1XXXXXXXXX',
            prefixIcon: Icon(Icons.phone_rounded),
            border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Text('Optional. Used so your contacts can find you on Convo.',
          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          final phone = ctrl.text.trim();
          final normalized = phone.replaceAll(RegExp(r'[\s\-()]'), '');
          await _db.collection('users').doc(_myUid).update({'phone': phone, 'phoneNormalized': normalized});
          if (mounted) { Navigator.pop(context); _load(); }
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone number saved!'), backgroundColor: kGreen));
        }, child: const Text('Save', style: TextStyle(color: kGreen))),
      ]));
  }

  void _changePass(BuildContext context) {
    final c = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(controller: c, obscureText: true,
        decoration: InputDecoration(hintText: 'New password (min 6)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () async { if (c.text.length >= 6) { await _auth.currentUser?.updatePassword(c.text); Navigator.pop(context); } },
          child: const Text('Update', style: TextStyle(color: Colors.white))),
      ]));
  }

  void _verify(BuildContext context) {
    final onWaitlist = _user?['verifiedWaitlist'] == true;
    final verified = _user?['verified'] == true;
    showModalBottomSheet(context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? kCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Icon(Icons.verified_rounded, color: kGreen, size: 48),
        const SizedBox(height: 12),
        Text(verified ? 'You are Verified!' : 'Get Verified', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(verified ? 'Your account has a blue badge.'
          : onWaitlist ? 'You are on the waitlist. We will notify you!'
          : 'Join the waitlist to get your blue badge.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400])),
        const SizedBox(height: 24),
        if (!verified && !onWaitlist) _btn('Join Waitlist', () async {
          await _db.collection('users').doc(_myUid).update({'verifiedWaitlist': true});
          await _db.collection('verify_waitlist').doc(_myUid).set({'uid': _myUid, 'name': _user?['name'], 'username': _user?['username'], 'joinedAt': FieldValue.serverTimestamp()});
          if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to waitlist!'), backgroundColor: kGreen)); _load(); }
        }),
        if (verified || onWaitlist) _btn(verified ? 'Awesome!' : 'On Waitlist', () => Navigator.pop(context)),
      ])));
  }

  Widget _sec(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
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
    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18), const SizedBox(width: 8),
    Expanded(child: Text(msg, style: const TextStyle(color: Colors.red, fontSize: 13))),
  ]));

Widget _tf(String hint, IconData icon, TextEditingController ctrl, bool obscure, bool isDark, Color bg, {TextInputType? type}) =>
  TextField(controller: ctrl, obscureText: obscure, keyboardType: type,
    style: TextStyle(color: isDark ? Colors.white : Colors.black),
    decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey[500]),
      prefixIcon: Icon(icon, color: Colors.grey), filled: true, fillColor: bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)));

Widget _btn(String label, VoidCallback? onTap, {bool loading = false}) => SizedBox(
  width: double.infinity, height: 54,
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    onPressed: onTap,
    child: loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
      : Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))));

// ════════════════════════════════════════════════════════
// ─── CONTACT SYNC SCREEN ───────────────────────────────
// ════════════════════════════════════════════════════════
class ContactSyncScreen extends StatefulWidget {
  const ContactSyncScreen({super.key});
  @override State<ContactSyncScreen> createState() => _ContactSyncScreenState();
}
class _ContactSyncScreenState extends State<ContactSyncScreen> {
  final _myUid = _auth.currentUser!.uid;
  bool _loading = false, _permissionDenied = false, _synced = false;
  List<_ContactResult> _results = [];

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('880') && digits.length == 13) return '+$digits';
    if (digits.startsWith('0') && digits.length == 11) return '+88$digits';
    if (digits.length == 10) return '+880$digits';
    if (digits.length > 7) return '+$digits';
    return '';
  }

  Future<void> _sync() async {
    setState(() { _loading = true; _permissionDenied = false; });
    try {
      final status = await Permission.contacts.request();
      if (!status.isGranted) {
        setState(() { _permissionDenied = true; _loading = false; }); return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final Map<String, String> phoneToName = {};
      for (final c in contacts) {
        for (final p in c.phones) {
          final norm = _normalizePhone(p.number);
          if (norm.isNotEmpty) phoneToName[norm] = c.displayName;
        }
      }
      final List<_ContactResult> found = [];
      if (phoneToName.isNotEmpty) {
        final keys = phoneToName.keys.toList();
        for (int i = 0; i < keys.length; i += 10) {
          final batch = keys.sublist(i, (i + 10).clamp(0, keys.length));
          final snap = await _db.collection('users').where('phoneNormalized', whereIn: batch).get();
          for (final doc in snap.docs) {
            if (doc.id == _myUid) continue;
            final d = doc.data();
            found.add(_ContactResult(
              uid: doc.id,
              name: d['name'] ?? 'User',
              username: d['username'] ?? '',
              avatar: d['avatar'] ?? '?',
              contactName: phoneToName[d['phoneNormalized'] ?? ''] ?? '',
              isOnline: d['isOnline'] == true));
          }
        }
      }
      setState(() { _results = found; _synced = true; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _addFriend(String uid, String name) async {
    final fd = await _db.collection('users').doc(_myUid).collection('friends').doc(uid).get();
    if (fd.exists) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already friends!'), backgroundColor: kGreen)); return; }
    final ex = await _db.collection('friend_requests').where('from', isEqualTo: _myUid).where('to', isEqualTo: uid).where('status', isEqualTo: 'pending').get();
    if (ex.docs.isNotEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request already sent!'))); return; }
    final my = await _db.collection('users').doc(_myUid).get();
    await _db.collection('friend_requests').add({
      'from': _myUid, 'fromName': my.data()?['name'] ?? 'User', 'fromAvatar': my.data()?['avatar'] ?? 'U',
      'to': uid, 'toName': name, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Friend request sent to $name ✅'), backgroundColor: kGreen));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts on Convo', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        // Header card
        Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kGreen.withOpacity(0.15), kGreen.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kGreen.withOpacity(0.2))),
          child: Column(children: [
            const Icon(Icons.contacts_rounded, color: kGreen, size: 44),
            const SizedBox(height: 12),
            const Text('Find Friends from Contacts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Convo checks which contacts are on the app. Your contact list is never uploaded or stored.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sync_rounded, color: Colors.white),
                label: Text(_loading ? 'Scanning...' : (_synced ? 'Sync Again' : 'Sync Contacts'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: _loading ? null : _sync)),
          ])),
        const SizedBox(height: 16),

        if (_permissionDenied) Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.block_rounded, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text('Permission denied. Go to Settings → Apps → Convo → Permissions → Contacts → Allow',
              style: TextStyle(color: Colors.grey[400], fontSize: 12))),
          ])),

        if (_synced && !_loading) ...[
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: Text(
            _results.isEmpty ? 'None of your contacts are on Convo yet' : '${_results.length} contact${_results.length == 1 ? '' : 's'} found on Convo',
            style: TextStyle(color: Colors.grey[400], fontSize: 13))),
          const SizedBox(height: 8),
        ],

        Expanded(child: _results.isEmpty && _synced && !_loading
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.person_search_rounded, size: 64, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text('None of your contacts are on Convo yet', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 8),
              const Text('Invite them! 🚀', style: TextStyle(color: kGreen, fontSize: 13)),
            ]))
          : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => Divider(height: 0, color: Colors.grey.withOpacity(0.08), indent: 72),
              itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  leading: Stack(children: [
                    CircleAvatar(radius: 24, backgroundColor: kGreen,
                      child: Text(r.avatar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                    Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12,
                      decoration: BoxDecoration(color: r.isOnline ? kGreen : Colors.grey[600], shape: BoxShape.circle,
                        border: Border.all(color: isDark ? kDark : Colors.white, width: 2)))),
                  ]),
                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('@${r.username}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    if (r.contactName.isNotEmpty)
                      Text('Saved as: ${r.contactName}', style: const TextStyle(color: kGreen, fontSize: 11)),
                  ]),
                  trailing: StreamBuilder<DocumentSnapshot>(
                    stream: _db.collection('users').doc(_myUid).collection('friends').doc(r.uid).snapshots(),
                    builder: (_, snap) {
                      if (snap.data?.exists == true)
                        return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: const Text('Friends', style: TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w600)));
                      return TextButton(
                        style: TextButton.styleFrom(backgroundColor: kGreen.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        onPressed: () => _addFriend(r.uid, r.name),
                        child: const Text('Add', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)));
                    }),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: r.uid))));
              })),
      ])));
  }
}

class _ContactResult {
  final String uid, name, username, avatar, contactName;
  final bool isOnline;
  const _ContactResult({required this.uid, required this.name, required this.username, required this.avatar, required this.contactName, required this.isOnline});
}
