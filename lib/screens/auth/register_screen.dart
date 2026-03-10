import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../widgets/common_widgets.dart';
import '../main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int  _step = 0; // 0 = personal info, 1 = password
  bool _obscure1 = true, _obscure2 = true, _loading = false, _ageConfirmed = false;
  String? _error;
  String _gender = '';
  int    _passStrength = 0;

  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String _generateUsername(String name, String uid) {
    final base   = name.trim().toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .substring(0, name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').length.clamp(0, 12));
    final suffix = uid.substring(uid.length - 5);
    return '${base}_$suffix';
  }

  void _onPassChange(String val) {
    int s = 0;
    if (val.length >= 6) s++;
    if (val.length >= 10) s++;
    if (RegExp(r'[A-Z]').hasMatch(val)) s++;
    if (RegExp(r'[0-9!@#\$%^&*]').hasMatch(val)) s++;
    setState(() => _passStrength = s);
  }

  Future<void> _register() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    final conf  = _confirmCtrl.text;
    if (name.isEmpty || email.isEmpty || pass.isEmpty || conf.isEmpty) {
      setState(() => _error = 'Please fill all fields'); return;
    }
    if (!_ageConfirmed) { setState(() => _error = 'You must confirm you are 13 or older'); return; }
    if (_gender.isEmpty) { setState(() => _error = 'Please select your gender'); return; }
    if (pass.length < 6) { setState(() => _error = 'Password must be at least 6 characters'); return; }
    if (pass != conf)    { setState(() => _error = 'Passwords do not match'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final cred     = await auth.createUserWithEmailAndPassword(email: email, password: pass);
      final uid      = cred.user!.uid;
      final username = _generateUsername(name, uid);
      await db.collection('users').doc(uid).set({
        'uid': uid, 'name': name, 'username': username,
        'email': email, 'phone': _phoneCtrl.text.trim(),
        'avatar': name[0].toUpperCase(), 'gender': _gender,
        'verified': false, 'verifiedWaitlist': false,
        'suggestionsEnabled': true, 'friendsPublic': true, 'profileMode': 'friend',
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'phoneNormalized': '',
        'social': {'facebook': '', 'instagram': '', 'github': '', 'linkedin': '', 'twitter': ''},
        'followerCount': 0, 'followingCount': 0, 'friendCount': 0,
        'fcmToken': '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      FirebaseMessaging.instance.getToken().then((fcm) {
        if (fcm != null) db.collection('users').doc(uid).update({'fcmToken': fcm});
      });
      await cred.user!.updateDisplayName(name);
      if (mounted) Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      String msg = 'Registration failed';
      if (e.code == 'email-already-in-use') msg = 'This email is already registered';
      else if (e.code == 'invalid-email')   msg = 'Invalid email address';
      else if (e.code == 'weak-password')   msg = 'Password is too weak';
      setState(() => _error = msg);
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF1E1E1E) : Colors.grey[100]!;
    final strengthColors = [Colors.grey[700]!, Colors.red, Colors.orange, Colors.yellow[700]!, kGreen];
    final strengthLabels = ['', 'Weak', 'Fair', 'Good', 'Strong'];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? kDark : const Color(0xFFF5F5F5),
      body: SafeArea(child: Column(children: [
        // Top bar with back + step dots
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () {
                if (_step == 1) setState(() { _step = 0; _error = null; });
                else Navigator.pop(context);
              }),
            const Spacer(),
            Row(children: List.generate(2, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(left: 6),
              width: i == _step ? 24 : 8, height: 8,
              decoration: BoxDecoration(
                color: i <= _step ? kGreen : Colors.grey[700],
                borderRadius: BorderRadius.circular(4))))),
            const SizedBox(width: 16),
          ])),

        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kGreen.withOpacity(0.18), kGreen.withOpacity(0.04)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kGreen.withOpacity(0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 48, height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00E676), kGreen]),
                    borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 26)),
                const SizedBox(height: 16),
                Text(_step == 0 ? 'Create Account' : 'Set Password',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.1)),
                const SizedBox(height: 6),
                Text(_step == 0
                    ? 'Tell us about yourself to get started'
                    : 'Choose a strong password to secure your account',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14, height: 1.4)),
              ])),
            const SizedBox(height: 24),

            if (_error != null) ...[errorBox(_error!), const SizedBox(height: 16)],

            // ── Step 0: Personal info ────────────────────────────────────
            if (_step == 0) ...[
              _label('Full Name'),
              _field(hint: 'Enter your full name', icon: Icons.person_rounded,
                ctrl: _nameCtrl, isDark: isDark, bg: bg, type: TextInputType.name),
              const SizedBox(height: 16),
              _label('Email Address'),
              _field(hint: 'your@email.com', icon: Icons.email_rounded,
                ctrl: _emailCtrl, isDark: isDark, bg: bg, type: TextInputType.emailAddress),
              const SizedBox(height: 16),
              _label('Phone Number', optional: true),
              _field(hint: '+880 1XXXXXXXXX', icon: Icons.phone_rounded,
                ctrl: _phoneCtrl, isDark: isDark, bg: bg, type: TextInputType.phone),
              const SizedBox(height: 20),

              _label('Gender'),
              const SizedBox(height: 8),
              Row(children: ['Male', 'Female', 'Other'].map((g) {
                final sel = _gender == g;
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _gender = g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: g == 'Other' ? 0 : 10),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: sel ? kGreen : bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? kGreen : Colors.grey.withOpacity(0.25), width: sel ? 0 : 1)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(
                        g == 'Male' ? Icons.male_rounded : g == 'Female' ? Icons.female_rounded : Icons.transgender_rounded,
                        color: sel ? Colors.white : Colors.grey[500], size: 16),
                      const SizedBox(width: 5),
                      Text(g, style: TextStyle(
                        color: sel ? Colors.white : Colors.grey[400],
                        fontWeight: FontWeight.w600, fontSize: 13)),
                    ]))));
              }).toList()),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: () => setState(() => _ageConfirmed = !_ageConfirmed),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _ageConfirmed ? kGreen.withOpacity(0.08) : bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _ageConfirmed ? kGreen.withOpacity(0.4) : Colors.grey.withOpacity(0.2))),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: _ageConfirmed ? kGreen : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _ageConfirmed ? kGreen : Colors.grey[600]!, width: 2)),
                      child: _ageConfirmed
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null),
                    const SizedBox(width: 12),
                    Expanded(child: Text('I confirm that I am 13 years or older',
                      style: TextStyle(
                        color: _ageConfirmed ? kGreen : Colors.grey[400],
                        fontSize: 14, fontWeight: FontWeight.w500))),
                  ]))),
              const SizedBox(height: 28),
              _bigBtn('Continue →', () {
                final name  = _nameCtrl.text.trim();
                final email = _emailCtrl.text.trim();
                if (name.isEmpty)                    { setState(() => _error = 'Please enter your full name'); return; }
                if (email.isEmpty || !email.contains('@')) { setState(() => _error = 'Please enter a valid email'); return; }
                if (_gender.isEmpty)                 { setState(() => _error = 'Please select your gender'); return; }
                if (!_ageConfirmed)                  { setState(() => _error = 'Please confirm your age'); return; }
                setState(() { _error = null; _step = 1; });
              }),
            ],

            // ── Step 1: Password ─────────────────────────────────────────
            if (_step == 1) ...[
              _label('Password'),
              Container(
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                child: TextField(
                  controller: _passCtrl, obscureText: _obscure1, onChanged: _onPassChange,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Create a strong password', hintStyle: TextStyle(color: Colors.grey[500]),
                    prefixIcon: const Icon(Icons.lock_rounded, color: kGreen, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure1 ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        color: Colors.grey[500], size: 20),
                      onPressed: () => setState(() => _obscure1 = !_obscure1)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    filled: true, fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16)))),

              if (_passCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(children: [
                  ...List.generate(4, (i) => Expanded(child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 4, margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: i < _passStrength ? strengthColors[_passStrength] : Colors.grey[800],
                      borderRadius: BorderRadius.circular(2))))),
                  const SizedBox(width: 10),
                  Text(strengthLabels[_passStrength],
                    style: TextStyle(color: strengthColors[_passStrength], fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ],
              const SizedBox(height: 16),

              _label('Confirm Password'),
              StatefulBuilder(builder: (_, setSt2) {
                final match    = _passCtrl.text.isNotEmpty && _confirmCtrl.text.isNotEmpty && _passCtrl.text == _confirmCtrl.text;
                final mismatch = _confirmCtrl.text.isNotEmpty && _passCtrl.text != _confirmCtrl.text;
                return Container(
                  decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: match ? kGreen.withOpacity(0.5) : mismatch ? Colors.red.withOpacity(0.4) : Colors.transparent,
                      width: 1.5)),
                  child: TextField(
                    controller: _confirmCtrl, obscureText: _obscure2,
                    onChanged: (_) => setSt2(() {}),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Re-enter your password', hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.lock_outline_rounded,
                        color: match ? kGreen : mismatch ? Colors.red : Colors.grey, size: 20),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (match)    Padding(padding: const EdgeInsets.only(right: 4), child: const Icon(Icons.check_circle_rounded, color: kGreen, size: 20)),
                        if (mismatch) Padding(padding: const EdgeInsets.only(right: 4), child: const Icon(Icons.cancel_rounded, color: Colors.red, size: 20)),
                        IconButton(
                          icon: Icon(_obscure2 ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.grey[500], size: 20),
                          onPressed: () => setState(() => _obscure2 = !_obscure2)),
                      ]),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      filled: true, fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16))));
              }),

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kGreen.withOpacity(0.15))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Password tips', style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...['At least 6 characters', 'Mix uppercase & lowercase', 'Add numbers or symbols for extra strength']
                    .map((t) => Padding(padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        const Icon(Icons.circle, color: kGreen, size: 5),
                        const SizedBox(width: 8),
                        Text(t, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      ]))),
                ])),
              const SizedBox(height: 28),
              _bigBtn(_loading ? '' : 'Create Account', _loading ? null : _register, loading: _loading),
            ],
          ]))),
      ])));
  }

  // ─── Local helpers ───────────────────────────────────────────────────────
  Widget _label(String t, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      if (optional) ...[
        const SizedBox(width: 6),
        Text('(optional)', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    ]));

  Widget _field({required String hint, required IconData icon, required TextEditingController ctrl,
    required bool isDark, required Color bg, TextInputType? type}) =>
    Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: ctrl, keyboardType: type,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: Colors.grey[500]),
          prefixIcon: Icon(icon, color: kGreen, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          filled: true, fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 16))));

  Widget _bigBtn(String label, VoidCallback? onTap, {bool loading = false}) =>
    SizedBox(width: double.infinity, height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: kGreen, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          shadowColor: kGreen.withOpacity(0.4)),
        onPressed: onTap,
        child: loading
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))));
}
