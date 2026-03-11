import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/constants.dart';
import '../main_screen.dart';
import 'register_screen.dart';
import 'username_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool   _obscure = true, _loading = false;
  bool   _showPhone = false, _otpSent = false;
  final  _emailCtrl = TextEditingController();
  final  _passCtrl  = TextEditingController();
  final  _phoneCtrl = TextEditingController();
  final  _otpCtrl   = TextEditingController();
  String? _error, _verificationId;
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── Email sign-in ─────────────────────────────────────────────────────────
  Future<void> _signIn() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Fill all fields'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await auth.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim());
      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _errMsg(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Google sign-in ────────────────────────────────────────────────────────
  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final gUser = await GoogleSignIn().signIn();
      if (gUser == null) { setState(() => _loading = false); return; }
      final gAuth  = await gUser.authentication;
      final cred   = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final result = await auth.signInWithCredential(cred);
      final isNew  = await _isNewUser(result.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) =>
            UsernameSetupScreen(user: result.user!)));
      } else { await _afterLogin(); }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _errMsg(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── GitHub sign-in ────────────────────────────────────────────────────────
  Future<void> _githubSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await auth.signInWithProvider(GithubAuthProvider());
      final isNew  = await _isNewUser(result.user!);
      if (isNew) {
        if (mounted) Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) =>
            UsernameSetupScreen(user: result.user!)));
      } else { await _afterLogin(); }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _errMsg(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Phone OTP ─────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.isEmpty) {
      setState(() => _error = 'Enter phone number'); return;
    }
    setState(() { _loading = true; _error = null; });
    await auth.verifyPhoneNumber(
      phoneNumber: _phoneCtrl.text.trim(),
      verificationCompleted: (cred) async {
        final r    = await auth.signInWithCredential(cred);
        final isNew = await _isNewUser(r.user!);
        if (isNew) {
          if (mounted) Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) =>
              UsernameSetupScreen(user: r.user!)));
        } else { await _afterLogin(); }
      },
      verificationFailed: (e) =>
        setState(() { _error = _errMsg(e.code); _loading = false; }),
      codeSent: (vId, _) =>
        setState(() { _verificationId = vId; _otpSent = true; _loading = false; }),
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
          MaterialPageRoute(builder: (_) =>
            UsernameSetupScreen(user: r.user!)));
      } else { await _afterLogin(); }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _errMsg(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _errMsg(String code) {
    switch (code) {
      case 'user-not-found':    return 'No account with this email.';
      case 'wrong-password':    return 'Wrong password.';
      case 'invalid-credential':return 'Invalid email or password.';
      case 'invalid-email':     return 'Invalid email address.';
      case 'too-many-requests': return 'Too many attempts. Try later.';
      default:                  return 'Something went wrong.';
    }
  }

  Future<bool> _isNewUser(User user) async {
    final doc = await db.collection('users').doc(user.uid).get();
    return !doc.exists;
  }

  Future<void> _afterLogin() async {
    final uid = auth.currentUser?.uid;
    if (uid != null) {
      await db.collection('users').doc(uid).update({'isOnline': true});
    }
    if (mounted) Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  void _forgotPass() {
    final c = TextEditingController(text: _emailCtrl.text);
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Reset Password',
        style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(
        controller: c,
        decoration: InputDecoration(
          hintText: 'Your email address',
          prefixIcon: const Icon(Icons.email_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGreen)))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kGreen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
          onPressed: () async {
            if (c.text.isNotEmpty) {
              await auth.sendPasswordResetEmail(email: c.text.trim());
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Reset link sent to your email'),
                  backgroundColor: kGreen));
              }
            }
          },
          child: const Text('Send', style: TextStyle(color: Colors.white))),
      ]));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size   = MediaQuery.of(context).size;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : Colors.white,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          child: Column(children: [
            // ── Header with gradient ─────────────────────────────────────
            Container(
              width: double.infinity,
              height: size.height * 0.32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [
                    kGreen.withOpacity(isDark ? 0.3 : 0.9),
                    kGreen.withOpacity(isDark ? 0.1 : 0.5),
                    isDark ? kDark : Colors.white,
                  ],
                  stops: const [0.0, 0.6, 1.0])),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo circle
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3), width: 2)),
                      child: const Center(
                        child: Text('C',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900)))),
                    const SizedBox(height: 12),
                    const Text('Convo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text('Connect with everyone',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13)),
                  ]))),

            // ── Form area ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [

                Text(_showPhone ? 'Sign in with Phone' : 'Welcome back',
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_showPhone
                  ? 'Enter your phone number to continue'
                  : 'Sign in to your account',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                const SizedBox(height: 20),

                // Error
                if (_error != null) ...[
                  _errorBox(_error!),
                  const SizedBox(height: 12),
                ],

                // ── Email/password fields ─────────────────────────────
                if (!_showPhone) ...[
                  _inputField(
                    hint: 'Email address',
                    icon: Icons.email_outlined,
                    ctrl: _emailCtrl,
                    isDark: isDark,
                    type: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _passField(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPass,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 0)),
                      child: const Text('Forgot password?',
                        style: TextStyle(
                          color: kGreen, fontSize: 13)))),
                  const SizedBox(height: 4),
                  _primaryBtn(
                    label: 'Sign In',
                    onTap: _loading ? null : _signIn,
                    loading: _loading),
                ],

                // ── Phone OTP ─────────────────────────────────────────
                if (_showPhone && !_otpSent) ...[
                  _inputField(
                    hint: '+880 1XXXXXXXXX',
                    icon: Icons.phone_outlined,
                    ctrl: _phoneCtrl,
                    isDark: isDark,
                    type: TextInputType.phone),
                  const SizedBox(height: 16),
                  _primaryBtn(
                    label: 'Send OTP',
                    onTap: _loading ? null : _sendOtp,
                    loading: _loading),
                ],

                if (_showPhone && _otpSent) ...[
                  // OTP sent info
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kGreen.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.sms_rounded, color: kGreen, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        'OTP sent to ${_phoneCtrl.text}',
                        style: const TextStyle(
                          color: kGreen, fontSize: 13))),
                    ])),
                  const SizedBox(height: 12),
                  _inputField(
                    hint: '6-digit OTP',
                    icon: Icons.lock_outline,
                    ctrl: _otpCtrl,
                    isDark: isDark,
                    type: TextInputType.number),
                  const SizedBox(height: 16),
                  _primaryBtn(
                    label: 'Verify & Sign In',
                    onTap: _loading ? null : _verifyOtp,
                    loading: _loading),
                  const SizedBox(height: 8),
                  Center(child: TextButton(
                    onPressed: () => setState(() {
                      _otpSent = false; _verificationId = null;
                    }),
                    child: const Text('Resend OTP',
                      style: TextStyle(color: kGreen)))),
                ],

                const SizedBox(height: 12),

                // ── Toggle phone/email ────────────────────────────────
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kGreen),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
                  icon: Icon(
                    _showPhone ? Icons.email_outlined : Icons.phone_outlined,
                    color: kGreen, size: 18),
                  label: Text(
                    _showPhone ? 'Use Email Instead' : 'Continue with Phone',
                    style: const TextStyle(
                      color: kGreen, fontWeight: FontWeight.w600,
                      fontSize: 14)),
                  onPressed: () => setState(() {
                    _showPhone = !_showPhone;
                    _error = null; _otpSent = false;
                  })),

                // ── Divider ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(children: [
                    Expanded(child: Divider(
                      color: isDark ? Colors.white12 : Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('or continue with',
                        style: TextStyle(
                          color: Colors.grey[500], fontSize: 12))),
                    Expanded(child: Divider(
                      color: isDark ? Colors.white12 : Colors.grey.shade300)),
                  ])),

                // ── OAuth buttons ─────────────────────────────────────
                Row(children: [
                  Expanded(child: _oauthBtn(
                    icon: Icons.g_mobiledata_rounded,
                    iconColor: const Color(0xFFDB4437),
                    label: 'Google',
                    isDark: isDark,
                    onTap: _loading ? null : _googleSignIn)),
                  const SizedBox(width: 12),
                  Expanded(child: _oauthBtn(
                    icon: Icons.code_rounded,
                    iconColor: isDark ? Colors.white : Colors.black87,
                    label: 'GitHub',
                    isDark: isDark,
                    onTap: _loading ? null : _githubSignIn)),
                ]),

                // ── Register link ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(top: 28, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text("Don't have an account? ",
                      style: TextStyle(
                        color: Colors.grey[500], fontSize: 14)),
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen())),
                      child: const Text('Create account',
                        style: TextStyle(
                          color: kGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 14))),
                  ])),
              ])),
          ]))));
  }

  // ── Widget helpers ────────────────────────────────────────────────────────
  Widget _inputField({
    required String hint,
    required IconData icon,
    required TextEditingController ctrl,
    required bool isDark,
    TextInputType? type,
  }) {
    final bg = isDark ? kCard : Colors.grey.shade100;
    return Container(
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[500]),
          prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 16))));
  }

  Widget _passField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? kCard : Colors.grey.shade100;
    return Container(
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: _passCtrl,
        obscureText: _obscure,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87, fontSize: 15),
        onSubmitted: (_) => _signIn(),
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: TextStyle(color: Colors.grey[500]),
          prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[500], size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: Colors.grey[500], size: 20),
            onPressed: () => setState(() => _obscure = !_obscure)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 16))));
  }

  Widget _primaryBtn({
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
  }) => SizedBox(
    width: double.infinity, height: 54,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: kGreen,
        elevation: 0,
        shadowColor: kGreen.withOpacity(0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14))),
      onPressed: onTap,
      child: loading
        ? const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2.5))
        : Text(label, style: const TextStyle(
            color: Colors.white,
            fontSize: 16, fontWeight: FontWeight.bold))));

  Widget _oauthBtn({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool isDark,
    required VoidCallback? onTap,
  }) => SizedBox(
    height: 52,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isDark ? kCard : Colors.grey.shade100,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300))),
      onPressed: onTap,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 14, fontWeight: FontWeight.w600)),
      ])));

  Widget _errorBox(String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(msg,
        style: const TextStyle(color: Colors.red, fontSize: 13))),
    ]));
}
