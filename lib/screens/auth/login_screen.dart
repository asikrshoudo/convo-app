// lib/screens/auth/login_screen.dart
// ═══════════════════════════════════════════════════════════════════════════
//  Convo — Premium Login Screen
//  Supports: Email/pass · Google · GitHub · Phone OTP
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/constants.dart';
import '../main_screen.dart';
import 'register_screen.dart';
import 'username_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────────────
  bool _obscure  = true;
  bool _loading  = false;
  bool _usePhone = false;
  bool _otpSent  = false;
  String? _error, _verificationId;

  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
        begin: const Offset(0, 0.06), end: Offset.zero).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose(); _passCtrl.dispose();
    _phoneCtrl.dispose(); _otpCtrl.dispose();
    super.dispose();
  }

  // ── Auth methods ───────────────────────────────────────────────────────
  Future<void> _emailSignIn() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      _err('Please fill in all fields'); return;
    }
    _begin();
    try {
      await auth.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _passCtrl.text);
      await _done();
    } on FirebaseAuthException catch (e) {
      _err(_authErr(e.code));
    } finally { _end(); }
  }

  Future<void> _googleSignIn() async {
    _begin();
    try {
      final g     = await GoogleSignIn().signIn();
      if (g == null) { _end(); return; }
      final gAuth = await g.authentication;
      final cred  = GoogleAuthProvider.credential(
          accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final res   = await auth.signInWithCredential(cred);
      await _handleOAuth(res.user!);
    } on FirebaseAuthException catch (e) {
      _err(_authErr(e.code));
    } finally { _end(); }
  }

  Future<void> _githubSignIn() async {
    _begin();
    try {
      final res = await auth.signInWithProvider(GithubAuthProvider());
      await _handleOAuth(res.user!);
    } on FirebaseAuthException catch (e) {
      _err(_authErr(e.code));
    } finally { _end(); }
  }

  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      _err('Enter your phone number'); return;
    }
    _begin();
    await auth.verifyPhoneNumber(
      phoneNumber: _phoneCtrl.text.trim(),
      verificationCompleted: (cred) async {
        final r = await auth.signInWithCredential(cred);
        await _handleOAuth(r.user!);
      },
      verificationFailed: (e) {
        _err(_authErr(e.code)); _end();
      },
      codeSent: (vId, _) {
        setState(() { _verificationId = vId; _otpSent = true; });
        _end();
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.isEmpty || _verificationId == null) return;
    _begin();
    try {
      final cred = PhoneAuthProvider.credential(
          verificationId: _verificationId!, smsCode: _otpCtrl.text.trim());
      final r = await auth.signInWithCredential(cred);
      await _handleOAuth(r.user!);
    } on FirebaseAuthException catch (e) {
      _err(_authErr(e.code));
    } finally { _end(); }
  }

  Future<void> _handleOAuth(User user) async {
    final doc = await db.collection('users').doc(user.uid).get();
    if (!doc.exists && mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: user)));
    } else {
      await _done();
    }
  }

  Future<void> _done() async {
    final uid = auth.currentUser?.uid;
    if (uid != null) {
      await db.collection('users').doc(uid).update({'isOnline': true});
    }
    if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  void _begin()       { if (mounted) setState(() { _loading = true;  _error = null; }); }
  void _end()         { if (mounted) setState(() => _loading = false); }
  void _err(String m) { if (mounted) setState(() { _error = m; _loading = false; }); }

  String _authErr(String code) => switch (code) {
    'user-not-found'     => 'No account found with this email.',
    'wrong-password'     => 'Incorrect password.',
    'invalid-credential' => 'Invalid email or password.',
    'invalid-email'      => 'Invalid email address.',
    'too-many-requests'  => 'Too many attempts. Please try again later.',
    _                    => 'Something went wrong. Please try again.',
  };

  void _forgotPassword() {
    final ctrl = TextEditingController(text: _emailCtrl.text);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetRadius))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: kTextTertiary,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Reset password', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: kTextPrimary)),
          const SizedBox(height: 6),
          const Text('Enter your email to receive a reset link.',
              style: TextStyle(color: kTextSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          _inputField(ctrl: ctrl, hint: 'Email address',
              icon: Icons.email_outlined, type: TextInputType.emailAddress),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                if (ctrl.text.isNotEmpty) {
                  await auth.sendPasswordResetEmail(email: ctrl.text.trim());
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Reset link sent to your email'),
                          backgroundColor: kAccent,
                          behavior: SnackBarBehavior.floating));
                  }
                }
              },
              child: const Text('Send Reset Link',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [

                const SizedBox(height: 52),

                // ── Brand ──────────────────────────────────────────────
                _brand(),
                const SizedBox(height: 48),

                // ── Mode title ─────────────────────────────────────────
                Text(
                  _usePhone ? 'Sign in with phone' : 'Welcome back',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700,
                      color: kTextPrimary, letterSpacing: -0.5, height: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  _usePhone
                      ? 'Enter your phone number to continue'
                      : 'Sign in to your account',
                  style: const TextStyle(
                      fontSize: 14, color: kTextSecondary, height: 1.5),
                ),
                const SizedBox(height: 28),

                // ── Error ──────────────────────────────────────────────
                if (_error != null) ...[
                  _errorCard(_error!),
                  const SizedBox(height: 16),
                ],

                // ── Email form ─────────────────────────────────────────
                if (!_usePhone) ...[
                  _inputField(
                    ctrl: _emailCtrl, hint: 'Email address',
                    icon: Icons.email_outlined,
                    type: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _inputField(
                    ctrl: _passCtrl, hint: 'Password',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20, color: kTextSecondary),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 0)),
                      child: const Text('Forgot password?',
                          style: TextStyle(color: kAccent, fontSize: 13)),
                    ),
                  ),
                  _primaryBtn(
                      label: 'Sign In',
                      onTap: _loading ? null : _emailSignIn),
                ],

                // ── Phone form ─────────────────────────────────────────
                if (_usePhone && !_otpSent) ...[
                  _inputField(
                    ctrl: _phoneCtrl, hint: '+880 1XXXXXXXXX',
                    icon: Icons.phone_outlined,
                    type: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  _primaryBtn(
                      label: 'Send OTP',
                      onTap: _loading ? null : _sendOtp),
                ],

                if (_usePhone && _otpSent) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kAccent.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.sms_rounded, color: kAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Code sent to ${_phoneCtrl.text}',
                          style: const TextStyle(
                              color: kAccent, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _inputField(
                    ctrl: _otpCtrl, hint: '6-digit OTP',
                    icon: Icons.pin_outlined,
                    type: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  _primaryBtn(
                      label: 'Verify & Sign In',
                      onTap: _loading ? null : _verifyOtp),
                  Center(child: TextButton(
                    onPressed: () => setState(() {
                      _otpSent = false; _verificationId = null;
                    }),
                    child: const Text('Resend OTP',
                        style: TextStyle(color: kAccent, fontSize: 13)),
                  )),
                ],

                const SizedBox(height: 14),

                // ── Toggle phone/email ─────────────────────────────────
                _ghostBtn(
                  icon: _usePhone
                      ? Icons.email_outlined : Icons.phone_outlined,
                  label: _usePhone
                      ? 'Use email instead' : 'Continue with phone',
                  onTap: () => setState(() {
                    _usePhone = !_usePhone;
                    _error = null; _otpSent = false;
                  }),
                ),

                // ── Divider ────────────────────────────────────────────
                _orDivider(),

                // ── OAuth buttons ──────────────────────────────────────
                Row(children: [
                  Expanded(child: _oauthBtn(
                    icon: Icons.g_mobiledata_rounded,
                    iconColor: const Color(0xFFDB4437),
                    label: 'Google',
                    onTap: _loading ? null : _googleSignIn,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _oauthBtn(
                    icon: Icons.code_rounded,
                    iconColor: kTextPrimary,
                    label: 'GitHub',
                    onTap: _loading ? null : _githubSignIn,
                  )),
                ]),

                // ── Register link ──────────────────────────────────────
                const SizedBox(height: 36),
                Center(child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("Don't have an account?  ",
                      style: TextStyle(color: kTextSecondary, fontSize: 14)),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen())),
                    child: const Text('Create account',
                        style: TextStyle(
                            color: kAccent,
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ])),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Brand widget ───────────────────────────────────────────────────────
  Widget _brand() => Row(children: [
    Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: kAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAccent.withOpacity(0.3)),
      ),
      child: const Center(
        child: Text('C', style: TextStyle(
            color: kAccent, fontSize: 22, fontWeight: FontWeight.w900)),
      ),
    ),
    const SizedBox(width: 12),
    const Text('Convo', style: TextStyle(
        color: kTextPrimary, fontSize: 22,
        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
  ]);

  // ── Input field ────────────────────────────────────────────────────────
  Widget _inputField({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    TextInputType? type,
    bool obscure = false,
    Widget? suffix,
  }) {
    return _FocusField(
      ctrl: ctrl, hint: hint, icon: icon,
      type: type, obscure: obscure, suffix: suffix,
    );
  }

  Widget _primaryBtn({required String label, required VoidCallback? onTap}) =>
      SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccent, elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onTap,
          child: _loading
              ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5))
              : Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 16,
              fontWeight: FontWeight.w600)),
        ),
      );

  Widget _ghostBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) =>
      SizedBox(
        width: double.infinity, height: 50,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: kDivider),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(icon, color: kTextSecondary, size: 18),
          label: Text(label, style: const TextStyle(
              color: kTextSecondary, fontSize: 14,
              fontWeight: FontWeight.w500)),
          onPressed: onTap,
        ),
      );

  Widget _oauthBtn({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback? onTap,
  }) =>
      SizedBox(
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kCard, elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: kDivider),
            ),
          ),
          onPressed: onTap,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(
                color: kTextPrimary, fontSize: 14,
                fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _orDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Row(children: [
      Expanded(child: Container(height: 1, color: kDivider)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Text('or', style: TextStyle(
            color: kTextTertiary, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
      Expanded(child: Container(height: 1, color: kDivider)),
    ]),
  );

  Widget _errorCard(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: kRed.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kRed.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: kRed, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg,
          style: const TextStyle(color: kRed, fontSize: 13))),
    ]),
  );
}

// ── Focus-aware animated input ─────────────────────────────────────────────
class _FocusField extends StatefulWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final TextInputType? type;
  final bool obscure;
  final Widget? suffix;

  const _FocusField({
    required this.ctrl, required this.hint, required this.icon,
    this.type, this.obscure = false, this.suffix,
  });

  @override
  State<_FocusField> createState() => _FocusFieldState();
}

class _FocusFieldState extends State<_FocusField> {
  late final FocusNode _fn;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _fn = FocusNode()..addListener(() {
      if (mounted) setState(() => _focused = _fn.hasFocus);
    });
  }

  @override
  void dispose() { _fn.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: _focused ? kAccent.withOpacity(0.7) : kDivider,
        width: _focused ? 1.5 : 1,
      ),
    ),
    child: TextField(
      controller: widget.ctrl,
      focusNode: _fn,
      obscureText: widget.obscure,
      keyboardType: widget.type,
      style: const TextStyle(color: kTextPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(color: kTextSecondary, fontSize: 15),
        prefixIcon: Icon(widget.icon, color: kTextSecondary, size: 20),
        suffixIcon: widget.suffix,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  );
}
