import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/constants.dart';
import '../../widgets/common_widgets.dart';
import '../main_screen.dart';
import 'register_screen.dart';
import 'username_setup_screen.dart';

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

  // ─── Email sign-in ───────────────────────────────────────────────────────
  Future<void> _signIn() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Fill all fields'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await auth.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      await _afterLogin();
    } on FirebaseAuthException catch (e) { setState(() => _error = _errMsg(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  // ─── Google sign-in ──────────────────────────────────────────────────────
  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final gUser = await GoogleSignIn().signIn();
      if (gUser == null) { setState(() => _loading = false); return; }
      final gAuth = await gUser.authentication;
      final cred  = GoogleAuthProvider.credential(
          accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final result = await auth.signInWithCredential(cred);
      final isNew  = await _isNewUser(result.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: result.user!)));
      } else { await _afterLogin(); }
    } on FirebaseAuthException catch (e) { setState(() => _error = _errMsg(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  // ─── GitHub sign-in ──────────────────────────────────────────────────────
  Future<void> _githubSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await auth.signInWithProvider(GithubAuthProvider());
      final isNew  = await _isNewUser(result.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: result.user!)));
      } else { await _afterLogin(); }
    } on FirebaseAuthException catch (e) { setState(() => _error = _errMsg(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  // ─── Phone OTP ───────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.isEmpty) { setState(() => _error = 'Enter phone number'); return; }
    setState(() { _loading = true; _error = null; });
    await auth.verifyPhoneNumber(
      phoneNumber: _phoneCtrl.text.trim(),
      verificationCompleted: (cred) async {
        final r    = await auth.signInWithCredential(cred);
        final isNew = await _isNewUser(r.user!);
        if (isNew) {
          if (mounted) Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: r.user!)));
        } else { await _afterLogin(); }
      },
      verificationFailed: (e) => setState(() { _error = _errMsg(e.code); _loading = false; }),
      codeSent: (vId, _) => setState(() { _verificationId = vId; _otpSent = true; _loading = false; }),
      codeAutoRetrievalTimeout: (_) {});
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.isEmpty || _verificationId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final cred = PhoneAuthProvider.credential(
          verificationId: _verificationId!, smsCode: _otpCtrl.text.trim());
      final r    = await auth.signInWithCredential(cred);
      final isNew = await _isNewUser(r.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: r.user!)));
      } else { await _afterLogin(); }
    } on FirebaseAuthException catch (e) { setState(() => _error = _errMsg(e.code)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────
  String _errMsg(String code) {
    switch (code) {
      case 'user-not-found':    return 'No account with this email.';
      case 'wrong-password':    return 'Wrong password.';
      case 'invalid-email':     return 'Invalid email.';
      case 'too-many-requests': return 'Too many attempts. Try later.';
      default:                  return 'Something went wrong.';
    }
  }

  /// Returns true if user doc doesn't exist yet (brand new account).
  Future<bool> _isNewUser(User user) async {
    final doc = await db.collection('users').doc(user.uid).get();
    return !doc.exists;
  }

  Future<void> _afterLogin() async {
    final uid = auth.currentUser?.uid;
    if (uid != null) await db.collection('users').doc(uid).update({'isOnline': true});
    if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  void _forgotPass() {
    final c = TextEditingController(text: _emailCtrl.text);
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(controller: c, decoration: InputDecoration(
        hintText: 'Email',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGreen)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () async {
            if (c.text.isNotEmpty) {
              await auth.sendPasswordResetEmail(email: c.text.trim());
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Send', style: TextStyle(color: Colors.white))),
      ]));
  }

  // ─── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? kCard : Colors.grey[100]!;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : Colors.white,
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 52),
          // Logo
          Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF00E676), kGreen]),
                borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SvgPicture.asset('assets/white_logo.svg', fit: BoxFit.contain))),
            const SizedBox(width: 12),
            const Text('Convo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 36),
          const Text('Welcome back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Sign in to continue', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 28),
          if (_error != null) errorBox(_error!),

          // Email / password fields
          if (!_showPhone) ...[
            inputField('Email', Icons.email_outlined, _emailCtrl, false, isDark, bg),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
            Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: _forgotPass,
                child: const Text('Forgot password?', style: TextStyle(color: kGreen, fontSize: 13)))),
            primaryButton('Sign In', _loading ? null : _signIn, loading: _loading),
          ],

          // Phone OTP fields
          if (_showPhone) ...[
            if (!_otpSent) ...[
              inputField('+880 1XXXXXXXXX', Icons.phone_outlined, _phoneCtrl, false, isDark, bg,
                  type: TextInputType.phone),
              const SizedBox(height: 14),
              primaryButton('Send OTP', _loading ? null : _sendOtp, loading: _loading),
            ] else ...[
              inputField('6-digit OTP', Icons.sms_outlined, _otpCtrl, false, isDark, bg,
                  type: TextInputType.number),
              const SizedBox(height: 14),
              primaryButton('Verify OTP', _loading ? null : _verifyOtp, loading: _loading),
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
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: const Text('Register', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 32),
        ]))));
  }

  Widget _oauthBtn(IconData icon, Color iconColor, String label, bool isDark, Color bg, VoidCallback? onPressed) =>
    SizedBox(height: 52, child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: bg, elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey[isDark ? 700 : 300]!, width: 1))),
      onPressed: onPressed,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14, fontWeight: FontWeight.w600)),
      ])));
}
