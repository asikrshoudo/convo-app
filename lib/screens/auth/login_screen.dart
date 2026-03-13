// lib/screens/auth/login_screen.dart
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

  String  _mode    = 'email'; // 'email' | 'phone'
  bool    _obscure = true;
  bool    _loading = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailCtrl.dispose(); _phoneCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  // ── Sign in ────────────────────────────────────────────────────────────
  Future<void> _signIn() async {
    final pass = _passCtrl.text;
    if (pass.isEmpty) { _err('Enter your password'); return; }
    _begin();
    try {
      String email;
      if (_mode == 'phone') {
        final raw = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-()]'), '');
        if (raw.isEmpty) { _err('Enter your phone number'); _end(); return; }
        final snap = await db.collection('users')
            .where('phoneNormalized', isEqualTo: raw)
            .limit(1).get();
        if (snap.docs.isEmpty) {
          _err('No account found with this phone number.'); _end(); return;
        }
        email = snap.docs.first['email'] as String;
      } else {
        email = _emailCtrl.text.trim();
        if (email.isEmpty) { _err('Enter your email'); _end(); return; }
      }

      final cred = await auth.signInWithEmailAndPassword(
          email: email, password: pass);

      if (cred.user != null && !cred.user!.emailVerified) {
        _showVerifyBanner(cred.user!);
      }

      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      _err(_msg(e.code));
    } finally { _end(); }
  }

  Future<void> _googleSignIn() async {
    _begin();
    try {
      final g  = await GoogleSignIn().signIn();
      if (g == null) { _end(); return; }
      final ga = await g.authentication;
      final c  = GoogleAuthProvider.credential(
          accessToken: ga.accessToken, idToken: ga.idToken);
      final r  = await auth.signInWithCredential(c);
      await _handleOAuth(r.user!);
    } on FirebaseAuthException catch (e) { _err(_msg(e.code));
    } finally { _end(); }
  }

  Future<void> _githubSignIn() async {
    _begin();
    try {
      final r = await auth.signInWithProvider(GithubAuthProvider());
      await _handleOAuth(r.user!);
    } on FirebaseAuthException catch (e) { _err(_msg(e.code));
    } finally { _end(); }
  }

  Future<void> _handleOAuth(User user) async {
    final doc = await db.collection('users').doc(user.uid).get();
    if (!doc.exists && mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => UsernameSetupScreen(user: user)));
    } else { await _afterLogin(); }
  }

  Future<void> _afterLogin() async {
    final uid = auth.currentUser?.uid;
    if (uid != null) await db.collection('users').doc(uid).update({'isOnline': true});
    if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  void _showVerifyBanner(User user) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
      backgroundColor: kCard,
      content: const Text(
        'Email not verified. Check your inbox.',
        style: TextStyle(color: kTextPrimary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await user.sendEmailVerification();
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Verification email resent!'),
                backgroundColor: kAccent, behavior: SnackBarBehavior.floating));
            }
          },
          child: const Text('Resend', style: TextStyle(color: kAccent)),
        ),
        TextButton(
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
          child: const Text('Dismiss', style: TextStyle(color: kTextSecondary)),
        ),
      ],
    ));
  }

  void _forgotPassword() {
    final ctrl = TextEditingController(text: _emailCtrl.text);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: kTextTertiary,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Reset password', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: kTextPrimary)),
          const SizedBox(height: 6),
          const Text('Enter your email and we\'ll send a reset link.',
              style: TextStyle(color: kTextSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          PremiumField(ctrl: ctrl, hint: 'Email address',
              icon: Icons.email_outlined, type: TextInputType.emailAddress),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                if (ctrl.text.trim().isNotEmpty) {
                  await auth.sendPasswordResetEmail(email: ctrl.text.trim());
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Reset link sent!'),
                      backgroundColor: kAccent,
                      behavior: SnackBarBehavior.floating));
                  }
                }
              },
              child: const Text('Send Reset Link', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
            )),
        ]),
      ),
    );
  }

  void _begin()       => setState(() { _loading = true; _error = null; });
  void _end()         { if (mounted) setState(() => _loading = false); }
  void _err(String m) => setState(() { _error = m; _loading = false; });

  String _msg(String code) => switch (code) {
    'user-not-found'     => 'No account found with this email.',
    'wrong-password'     => 'Incorrect password.',
    'invalid-credential' => 'Invalid email or password.',
    'invalid-email'      => 'Invalid email address.',
    'too-many-requests'  => 'Too many attempts. Try again later.',
    _                    => 'Something went wrong. Please try again.',
  };

  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              const SizedBox(height: 56),

              // Logo
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: kAccent.withOpacity(0.3)),
                  ),
                  child: const Center(child: Text('C', style: TextStyle(
                      color: kAccent, fontSize: 24, fontWeight: FontWeight.w900))),
                ),
                const SizedBox(width: 12),
                const Text('Convo', style: TextStyle(
                    color: kTextPrimary, fontSize: 22,
                    fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ]),

              const SizedBox(height: 48),
              const Text('Welcome back', style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w700,
                  color: kTextPrimary, letterSpacing: -0.8, height: 1.1)),
              const SizedBox(height: 8),
              const Text('Sign in to continue', style: TextStyle(
                  fontSize: 15, color: kTextSecondary, height: 1.5)),
              const SizedBox(height: 32),

              // Toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: kCard, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  _tab('Email', 'email', Icons.email_outlined),
                  _tab('Phone', 'phone', Icons.phone_outlined),
                ]),
              ),

              const SizedBox(height: 24),

              if (_error != null) ...[
                AuthErrorBox(msg: _error!),
                const SizedBox(height: 16),
              ],

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _mode == 'email'
                    ? PremiumField(key: const ValueKey('e'),
                        ctrl: _emailCtrl, hint: 'Email address',
                        icon: Icons.email_outlined,
                        type: TextInputType.emailAddress)
                    : PremiumField(key: const ValueKey('p'),
                        ctrl: _phoneCtrl, hint: 'Phone (with country code)',
                        icon: Icons.phone_outlined,
                        type: TextInputType.phone),
              ),

              const SizedBox(height: 12),

              PremiumField(
                ctrl: _passCtrl, hint: 'Password',
                icon: Icons.lock_outline_rounded, obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                      size: 20, color: kTextSecondary),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),

              if (_mode == 'email')
                Align(alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _forgotPassword,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 0)),
                    child: const Text('Forgot password?',
                        style: TextStyle(color: kAccent, fontSize: 13)),
                  ))
              else
                const SizedBox(height: 16),

              // Sign in btn
              SizedBox(width: double.infinity, height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent, elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text('Sign In', style: TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w600)),
                )),

              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(children: [
                  Expanded(child: Container(height: 1, color: kDivider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or', style: TextStyle(
                        color: kTextTertiary, fontSize: 12))),
                  Expanded(child: Container(height: 1, color: kDivider)),
                ]),
              ),

              // OAuth
              Row(children: [
                Expanded(child: AuthOAuthBtn(
                    icon: Icons.g_mobiledata_rounded,
                    iconColor: const Color(0xFFDB4437),
                    label: 'Google',
                    onTap: _loading ? null : _googleSignIn)),
                const SizedBox(width: 12),
                Expanded(child: AuthOAuthBtn(
                    icon: Icons.code_rounded,
                    iconColor: kTextPrimary,
                    label: 'GitHub',
                    onTap: _loading ? null : _githubSignIn)),
              ]),

              const SizedBox(height: 40),
              Center(child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account?  ",
                    style: TextStyle(color: kTextSecondary, fontSize: 14)),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('Create account', style: TextStyle(
                      color: kAccent, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ])),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, String mode, IconData icon) =>
      Expanded(child: GestureDetector(
        onTap: () => setState(() { _mode = mode; _error = null; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _mode == mode ? kCard2 : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15,
                color: _mode == mode ? kTextPrimary : kTextSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
                color: _mode == mode ? kTextPrimary : kTextSecondary,
                fontSize: 13,
                fontWeight: _mode == mode ? FontWeight.w600 : FontWeight.normal)),
          ]),
        ),
      ));
}

// ── Shared auth widgets (used by login + register) ─────────────────────────

class PremiumField extends StatefulWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final TextInputType? type;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final String? label;

  const PremiumField({
    super.key,
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.type,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.label,
  });

  @override State<PremiumField> createState() => _PremiumFieldState();
}

class _PremiumFieldState extends State<PremiumField> {
  late final FocusNode _fn;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _fn = FocusNode()
      ..addListener(() {
        if (mounted) setState(() => _focused = _fn.hasFocus);
      });
  }

  @override
  void dispose() { _fn.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.label != null) ...[
        Text(widget.label!, style: const TextStyle(
            color: kTextSecondary, fontSize: 12,
            fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        const SizedBox(height: 8),
      ],
      AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? kAccent.withOpacity(0.65) : kDivider,
            width: _focused ? 1.5 : 1,
          ),
        ),
        child: TextField(
          controller: widget.ctrl,
          focusNode: _fn,
          obscureText: widget.obscure,
          keyboardType: widget.type,
          onChanged: widget.onChanged,
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
      ),
    ]);
  }
}

class AuthErrorBox extends StatelessWidget {
  final String msg;
  const AuthErrorBox({super.key, required this.msg});

  @override
  Widget build(BuildContext context) => Container(
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

class AuthOAuthBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  const AuthOAuthBtn({
    super.key,
    required this.icon, required this.iconColor,
    required this.label, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
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
            color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
