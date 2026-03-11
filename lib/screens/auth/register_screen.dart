import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants.dart';
import '../../widgets/common_widgets.dart';
import '../main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // 0 = personal info  |  1 = password  |  2 = email verification
  int  _step = 0;
  bool _obscure1 = true, _obscure2 = true;
  bool _loading = false, _ageConfirmed = false;
  bool _resendCooldown = false;
  String? _error;
  String _gender = '';
  int    _passStrength = 0;

  // OTP
  String? _sentCode;
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  late AnimationController _animCtrl;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(
        begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    for (final c in _otpCtrls) { c.dispose(); }
    for (final f in _otpFocus)  { f.dispose(); }
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    _animCtrl.reset();
    _animCtrl.forward();
    setState(() { _step++; _error = null; });
  }

  // ── Generate + send OTP ───────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    setState(() { _loading = true; _error = null; });
    final code = (100000 + Random().nextInt(900000)).toString();
    _sentCode = code;
    try {
      final res = await http.post(
        Uri.parse('https://convo-notify.onrender.com/send-email-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailCtrl.text.trim(),
          'code':  code,
          'name':  _nameCtrl.text.trim(),
        }));
      if (res.statusCode == 200) {
        _nextStep();
      } else {
        setState(() => _error = 'Failed to send code. Try again.');
      }
    } catch (_) {
      setState(() => _error = 'Network error. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() { _resendCooldown = true; });
    await _sendOtp();
    await Future.delayed(const Duration(seconds: 30));
    if (mounted) setState(() => _resendCooldown = false);
  }

  // ── Verify code + create account ──────────────────────────────────────────
  Future<void> _verifyAndRegister() async {
    final entered = _otpCtrls.map((c) => c.text).join();
    if (entered.length < 6) {
      setState(() => _error = 'Enter the full 6-digit code');
      return;
    }
    if (entered != _sentCode) {
      setState(() => _error = 'Incorrect code. Check your email and try again.');
      // Shake OTP fields
      for (final c in _otpCtrls) { c.clear(); }
      _otpFocus[0].requestFocus();
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final email = _emailCtrl.text.trim();
      final pass  = _passCtrl.text;
      final name  = _nameCtrl.text.trim();

      final cred     = await auth.createUserWithEmailAndPassword(
          email: email, password: pass);
      final uid      = cred.user!.uid;
      final username = _generateUsername(name, uid);

      await db.collection('users').doc(uid).set({
        'uid': uid, 'name': name, 'username': username,
        'email': email,
        'phone': _phoneCtrl.text.trim(),
        'phoneNormalized':
            _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-()]'), ''),
        'avatar': name[0].toUpperCase(), 'gender': _gender,
        'verified': false, 'verifiedWaitlist': false,
        'suggestionsEnabled': true, 'friendsPublic': true,
        'profileMode': 'friend',
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'social': {
          'facebook': '', 'instagram': '', 'github': '',
          'linkedin': '', 'twitter': ''},
        'followerCount': 0, 'followingCount': 0, 'friendCount': 0,
        'fcmToken': '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      FirebaseMessaging.instance.getToken().then((fcm) {
        if (fcm != null) {
          db.collection('users').doc(uid).update({'fcmToken': fcm});
        }
      });

      await cred.user!.updateDisplayName(name);
      if (mounted) Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      String msg = 'Registration failed. Try again.';
      if (e.code == 'email-already-in-use') msg = 'This email is already registered.';
      else if (e.code == 'invalid-email')   msg = 'Invalid email address.';
      else if (e.code == 'weak-password')   msg = 'Password is too weak.';
      setState(() => _error = msg);
      // Go back to step 0 if email issue
      if (e.code == 'email-already-in-use' || e.code == 'invalid-email') {
        setState(() => _step = 0);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _generateUsername(String name, String uid) {
    final base   = name.trim().toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .substring(0, name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
            .length.clamp(0, 12));
    final suffix = uid.substring(uid.length - 5);
    return '${base}_$suffix';
  }

  void _onPassChange(String val) {
    int s = 0;
    if (val.length >= 6)  s++;
    if (val.length >= 10) s++;
    if (RegExp(r'[A-Z]').hasMatch(val)) s++;
    if (RegExp(r'[0-9!@#\$%^&*]').hasMatch(val)) s++;
    setState(() => _passStrength = s);
  }

  // ── Step 0 validation ─────────────────────────────────────────────────────
  void _validateStep0() {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name'); return;
    }
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email'); return;
    }
    if (_gender.isEmpty) {
      setState(() => _error = 'Please select your gender'); return;
    }
    if (!_ageConfirmed) {
      setState(() => _error = 'Please confirm your age'); return;
    }
    setState(() { _error = null; });
    _nextStep();
  }

  // ── Step 1 validation ─────────────────────────────────────────────────────
  void _validateStep1() {
    final pass = _passCtrl.text;
    final conf = _confirmCtrl.text;
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters'); return;
    }
    if (pass != conf) {
      setState(() => _error = 'Passwords do not match'); return;
    }
    setState(() { _error = null; });
    _sendOtp(); // sends OTP then moves to step 2
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? kCard : Colors.grey[100]!;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : const Color(0xFFF8F8F8),
      body: SafeArea(child: Column(children: [

        // ── Top bar ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () {
                if (_step > 0) {
                  setState(() { _step--; _error = null; });
                } else {
                  Navigator.pop(context);
                }
              }),
            const Spacer(),
            // Step dots
            Row(children: List.generate(3, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(left: 6),
              width: i == _step ? 28 : 8, height: 8,
              decoration: BoxDecoration(
                color: i <= _step ? kGreen : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                borderRadius: BorderRadius.circular(4))))),
          ])),

        // ── Body ───────────────────────────────────────────────────────────
        Expanded(child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Header card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kGreen.withOpacity(0.18), kGreen.withOpacity(0.04)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kGreen.withOpacity(0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20)),
                      child: Text('Step ${_step + 1} of 3',
                        style: const TextStyle(
                          color: kGreen, fontSize: 12,
                          fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    _step == 0 ? 'Create Account'
                      : _step == 1 ? 'Set Password'
                      : 'Verify Email',
                    style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    _step == 0 ? 'Tell us a bit about yourself'
                      : _step == 1 ? 'Choose a strong password'
                      : 'Enter the 6-digit code sent to\n${_emailCtrl.text.trim()}',
                    style: TextStyle(
                      color: Colors.grey[500], fontSize: 14, height: 1.5)),
                ])),

              const SizedBox(height: 20),

              if (_error != null) ...[
                errorBox(_error!),
                const SizedBox(height: 12),
              ],

              // ── Step 0: Personal info ──────────────────────────────────
              if (_step == 0) ...[
                _label('Full Name'),
                _field(hint: 'Your full name', icon: Icons.person_rounded,
                  ctrl: _nameCtrl, isDark: isDark, bg: bg,
                  type: TextInputType.name),
                const SizedBox(height: 14),

                _label('Email Address'),
                _field(hint: 'your@email.com', icon: Icons.email_rounded,
                  ctrl: _emailCtrl, isDark: isDark, bg: bg,
                  type: TextInputType.emailAddress),
                const SizedBox(height: 14),

                _label('Phone Number', optional: true),
                _field(hint: '+880 1XXXXXXXXX', icon: Icons.phone_rounded,
                  ctrl: _phoneCtrl, isDark: isDark, bg: bg,
                  type: TextInputType.phone),
                const SizedBox(height: 18),

                _label('Gender'),
                const SizedBox(height: 8),
                Row(children: ['Male', 'Female', 'Other'].map((g) {
                  final sel = _gender == g;
                  return Expanded(child: GestureDetector(
                    onTap: () => setState(() => _gender = g),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(right: g == 'Other' ? 0 : 10),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: sel ? kGreen : bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? kGreen : Colors.grey.withOpacity(0.2),
                          width: sel ? 0 : 1)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            g == 'Male' ? Icons.male_rounded
                              : g == 'Female' ? Icons.female_rounded
                              : Icons.transgender_rounded,
                            color: sel ? Colors.white : Colors.grey[500],
                            size: 16),
                          const SizedBox(width: 5),
                          Text(g, style: TextStyle(
                            color: sel ? Colors.white : Colors.grey[400],
                            fontWeight: FontWeight.w600, fontSize: 13)),
                        ]))));
                }).toList()),
                const SizedBox(height: 16),

                // Age confirm
                GestureDetector(
                  onTap: () => setState(() => _ageConfirmed = !_ageConfirmed),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _ageConfirmed
                        ? kGreen.withOpacity(0.08) : bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _ageConfirmed
                          ? kGreen.withOpacity(0.4)
                          : Colors.grey.withOpacity(0.2))),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: _ageConfirmed ? kGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _ageConfirmed
                              ? kGreen : Colors.grey[600]!, width: 2)),
                        child: _ageConfirmed
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 14)
                          : null),
                      const SizedBox(width: 12),
                      Expanded(child: Text(
                        'I confirm I am 13 years or older',
                        style: TextStyle(
                          color: _ageConfirmed ? kGreen : Colors.grey[400],
                          fontSize: 14, fontWeight: FontWeight.w500))),
                    ]))),
                const SizedBox(height: 28),
                _bigBtn('Continue', _validateStep0),
              ],

              // ── Step 1: Password ───────────────────────────────────────
              if (_step == 1) ...[
                _label('Password'),
                Container(
                  decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(14)),
                  child: TextField(
                    controller: _passCtrl,
                    obscureText: _obscure1,
                    onChanged: _onPassChange,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Create a strong password',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: const Icon(Icons.lock_rounded,
                        color: kGreen, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure1 ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                          color: Colors.grey[500], size: 20),
                        onPressed: () =>
                          setState(() => _obscure1 = !_obscure1)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                      filled: true, fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16)))),

                if (_passCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _strengthBar(),
                ],
                const SizedBox(height: 14),

                _label('Confirm Password'),
                StatefulBuilder(builder: (_, setSt2) {
                  final match    = _passCtrl.text.isNotEmpty
                    && _confirmCtrl.text.isNotEmpty
                    && _passCtrl.text == _confirmCtrl.text;
                  final mismatch = _confirmCtrl.text.isNotEmpty
                    && _passCtrl.text != _confirmCtrl.text;
                  return Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: match ? kGreen.withOpacity(0.5)
                          : mismatch ? Colors.red.withOpacity(0.4)
                          : Colors.transparent,
                        width: 1.5)),
                    child: TextField(
                      controller: _confirmCtrl,
                      obscureText: _obscure2,
                      onChanged: (_) => setSt2(() {}),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Re-enter password',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.lock_outline_rounded,
                          color: match ? kGreen
                            : mismatch ? Colors.red
                            : Colors.grey,
                          size: 20),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min, children: [
                          if (match)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.check_circle_rounded,
                                color: kGreen, size: 20)),
                          if (mismatch)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.cancel_rounded,
                                color: Colors.red, size: 20)),
                          IconButton(
                            icon: Icon(
                              _obscure2 ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                              color: Colors.grey[500], size: 20),
                            onPressed: () =>
                              setState(() => _obscure2 = !_obscure2)),
                        ]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                        filled: true, fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16))));
                }),
                const SizedBox(height: 14),

                // Tips
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGreen.withOpacity(0.15))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Password tips',
                      style: TextStyle(
                        color: Colors.grey[400], fontSize: 12,
                        fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...[
                      'At least 6 characters',
                      'Mix uppercase & lowercase',
                      'Add numbers or symbols for extra strength',
                    ].map((t) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Icon(Icons.circle, color: kGreen, size: 5),
                        const SizedBox(width: 8),
                        Text(t, style: TextStyle(
                          color: Colors.grey[500], fontSize: 12)),
                      ]))),
                  ])),
                const SizedBox(height: 28),
                _bigBtn(
                  _loading ? '' : 'Send Verification Code',
                  _loading ? null : _validateStep1,
                  loading: _loading,
                  icon: Icons.send_rounded),
              ],

              // ── Step 2: Email OTP ──────────────────────────────────────
              if (_step == 2) ...[
                // Email indicator
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kGreen.withOpacity(0.2))),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kGreen.withOpacity(0.15),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.mark_email_read_rounded,
                        color: kGreen, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Code sent!',
                        style: TextStyle(
                          color: kGreen, fontWeight: FontWeight.bold,
                          fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('Check ${_emailCtrl.text.trim()}',
                        style: TextStyle(
                          color: Colors.grey[500], fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    ])),
                  ])),
                const SizedBox(height: 28),

                const Center(child: Text('Enter 6-digit code',
                  style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15))),
                const SizedBox(height: 16),

                // OTP boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) => _otpBox(i, isDark))),
                const SizedBox(height: 28),

                _bigBtn(
                  _loading ? '' : 'Verify & Create Account',
                  _loading ? null : _verifyAndRegister,
                  loading: _loading,
                  icon: Icons.verified_user_rounded),
                const SizedBox(height: 16),

                // Resend
                Center(child: _resendCooldown
                  ? Text('Resend available in 30s',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13))
                  : TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded,
                        color: kGreen, size: 16),
                      label: const Text('Resend code',
                        style: TextStyle(color: kGreen, fontSize: 13)),
                      onPressed: _resendOtp)),

                const SizedBox(height: 8),
                Center(child: TextButton(
                  onPressed: () =>
                    setState(() { _step = 0; _error = null; }),
                  child: Text('Change email address',
                    style: TextStyle(
                      color: Colors.grey[500], fontSize: 12)))),
              ],

            ]))))
      ])));
  }

  // ── OTP single box ────────────────────────────────────────────────────────
  Widget _otpBox(int i, bool isDark) {
    return Container(
      width: 46, height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? kCard : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _otpCtrls[i].text.isNotEmpty
            ? kGreen : Colors.grey.withOpacity(0.3),
          width: 1.5)),
      child: TextField(
        controller: _otpCtrls[i],
        focusNode: _otpFocus[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none),
        onChanged: (val) {
          setState(() {});
          if (val.isNotEmpty && i < 5) {
            _otpFocus[i + 1].requestFocus();
          }
          if (val.isEmpty && i > 0) {
            _otpFocus[i - 1].requestFocus();
          }
          // Auto submit when all filled
          if (i == 5 && val.isNotEmpty) {
            final all = _otpCtrls.map((c) => c.text).join();
            if (all.length == 6) _verifyAndRegister();
          }
        }));
  }

  // ── Password strength bar ─────────────────────────────────────────────────
  Widget _strengthBar() {
    final colors = [
      Colors.grey[700]!, Colors.red, Colors.orange,
      Colors.yellow[700]!, kGreen];
    final labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
    return Row(children: [
      ...List.generate(4, (i) => Expanded(child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 4,
        margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
        decoration: BoxDecoration(
          color: i < _passStrength
            ? colors[_passStrength]
            : (Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]! : Colors.grey[300]!),
          borderRadius: BorderRadius.circular(2))))),
      const SizedBox(width: 10),
      Text(labels[_passStrength],
        style: TextStyle(
          color: colors[_passStrength], fontSize: 12,
          fontWeight: FontWeight.w600)),
    ]);
  }

  // ── Local helpers ─────────────────────────────────────────────────────────
  Widget _label(String t, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(t, style: const TextStyle(
        fontWeight: FontWeight.w600, fontSize: 14)),
      if (optional) ...[
        const SizedBox(width: 6),
        Text('(optional)',
          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    ]));

  Widget _field({
    required String hint, required IconData icon,
    required TextEditingController ctrl, required bool isDark,
    required Color bg, TextInputType? type,
  }) => Container(
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(14)),
    child: TextField(
      controller: ctrl, keyboardType: type,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint, hintStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: kGreen, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
        filled: true, fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(vertical: 16))));

  Widget _bigBtn(String label, VoidCallback? onTap,
      {bool loading = false, IconData? icon}) =>
    SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen, elevation: 0,
          shadowColor: kGreen.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16))),
        onPressed: onTap,
        child: loading
          ? const SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2.5))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: const TextStyle(
                color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.bold)),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 18),
              ],
            ])));
}
