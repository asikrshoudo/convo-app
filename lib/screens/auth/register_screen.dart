// lib/screens/auth/register_screen.dart
// ═══════════════════════════════════════════════════════════════════════════
//  Convo — Premium Registration  (5-step flow)
//  Step 0 → Names | 1 → Birthday | 2 → Contact | 3 → Password | 4 → OTP
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants.dart';
import '../main_screen.dart';

// ── Country model ──────────────────────────────────────────────────────────
class _Country {
  final String name, dialCode;
  const _Country(this.name, this.dialCode);
}

const _kCountries = [
  _Country('Bangladesh',           '+880'),
  _Country('India',                '+91'),
  _Country('Pakistan',             '+92'),
  _Country('United States',        '+1'),
  _Country('United Kingdom',       '+44'),
  _Country('Canada',               '+1'),
  _Country('Australia',            '+61'),
  _Country('UAE',                  '+971'),
  _Country('Saudi Arabia',         '+966'),
  _Country('Qatar',                '+974'),
  _Country('Kuwait',               '+965'),
  _Country('Bahrain',              '+973'),
  _Country('Oman',                 '+968'),
  _Country('Malaysia',             '+60'),
  _Country('Singapore',            '+65'),
  _Country('Indonesia',            '+62'),
  _Country('Philippines',          '+63'),
  _Country('Thailand',             '+66'),
  _Country('Vietnam',              '+84'),
  _Country('Myanmar',              '+95'),
  _Country('Nepal',                '+977'),
  _Country('Sri Lanka',            '+94'),
  _Country('Maldives',             '+960'),
  _Country('China',                '+86'),
  _Country('Japan',                '+81'),
  _Country('South Korea',          '+82'),
  _Country('Hong Kong',            '+852'),
  _Country('Taiwan',               '+886'),
  _Country('Germany',              '+49'),
  _Country('France',               '+33'),
  _Country('Italy',                '+39'),
  _Country('Spain',                '+34'),
  _Country('Netherlands',          '+31'),
  _Country('Sweden',               '+46'),
  _Country('Norway',               '+47'),
  _Country('Denmark',              '+45'),
  _Country('Finland',              '+358'),
  _Country('Switzerland',          '+41'),
  _Country('Austria',              '+43'),
  _Country('Belgium',              '+32'),
  _Country('Poland',               '+48'),
  _Country('Russia',               '+7'),
  _Country('Ukraine',              '+380'),
  _Country('Turkey',               '+90'),
  _Country('Egypt',                '+20'),
  _Country('Nigeria',              '+234'),
  _Country('South Africa',         '+27'),
  _Country('Kenya',                '+254'),
  _Country('Ethiopia',             '+251'),
  _Country('Ghana',                '+233'),
  _Country('Tanzania',             '+255'),
  _Country('Brazil',               '+55'),
  _Country('Mexico',               '+52'),
  _Country('Argentina',            '+54'),
  _Country('Colombia',             '+57'),
  _Country('Chile',                '+56'),
  _Country('Peru',                 '+51'),
  _Country('Venezuela',            '+58'),
  _Country('Morocco',              '+212'),
  _Country('Tunisia',              '+216'),
  _Country('Algeria',              '+213'),
  _Country('Libya',                '+218'),
  _Country('Jordan',               '+962'),
  _Country('Lebanon',              '+961'),
  _Country('Iraq',                 '+964'),
  _Country('Iran',                 '+98'),
  _Country('Syria',                '+963'),
  _Country('Israel',               '+972'),
  _Country('Palestine',            '+970'),
  _Country('Afghanistan',          '+93'),
  _Country('Kazakhstan',           '+7'),
  _Country('Uzbekistan',           '+998'),
  _Country('Azerbaijan',           '+994'),
  _Country('Georgia',              '+995'),
  _Country('Cambodia',             '+855'),
  _Country('New Zealand',          '+64'),
  _Country('Ireland',              '+353'),
  _Country('Portugal',             '+351'),
  _Country('Czech Republic',       '+420'),
  _Country('Hungary',              '+36'),
  _Country('Romania',              '+40'),
  _Country('Bulgaria',             '+359'),
  _Country('Croatia',              '+385'),
  _Country('Serbia',               '+381'),
  _Country('Greece',               '+30'),
  _Country('Sudan',                '+249'),
  _Country('Zimbabwe',             '+263'),
];

// ═══════════════════════════════════════════════════════════════════════════
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {

  final _pageCtrl = PageController();
  int  _page      = 0;
  bool _loading   = false;
  String? _error;

  // ── Step 0 — Names ─────────────────────────────────────────────────────
  final _firstCtrl  = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl   = TextEditingController();

  // ── Step 1 — Birthday ──────────────────────────────────────────────────
  DateTime? _birthday;

  // ── Step 2 — Contact ───────────────────────────────────────────────────
  _Country _country = _kCountries[0]; // Bangladesh default
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // ── Step 3 — Password ──────────────────────────────────────────────────
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _ob1 = true, _ob2 = true;
  int  _strength = 0;

  // ── Step 4 — OTP ───────────────────────────────────────────────────────
  String? _sentCode;
  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpFocus = List.generate(6, (_) => FocusNode());
  bool _cooldown = false;

  // ── Dispose ────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _pageCtrl.dispose();
    _firstCtrl.dispose(); _middleCtrl.dispose(); _lastCtrl.dispose();
    _phoneCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose();  _confirmCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────
  void _next() {
    _pageCtrl.animateToPage(_page + 1,
        duration: const Duration(milliseconds: 380), curve: Curves.easeInOutCubic);
    setState(() { _page++; _error = null; });
  }

  void _back() {
    if (_page == 0) { Navigator.pop(context); return; }
    _pageCtrl.animateToPage(_page - 1,
        duration: const Duration(milliseconds: 320), curve: Curves.easeInOutCubic);
    setState(() { _page--; _error = null; });
  }

  // ── Validations ────────────────────────────────────────────────────────
  void _step0() {
    if (_firstCtrl.text.trim().isEmpty) { _setErr('First name is required'); return; }
    if (_lastCtrl.text.trim().isEmpty)  { _setErr('Last name is required');  return; }
    _next();
  }

  void _step1() {
    if (_birthday == null) { _setErr('Please select your date of birth'); return; }
    final age = DateTime.now().difference(_birthday!).inDays ~/ 365;
    if (age < 13) { _setErr('You must be at least 13 years old'); return; }
    _next();
  }

  void _step2() {
    if (_phoneCtrl.text.trim().isEmpty) {
      _setErr('Phone number is required'); return;
    }
    final e = _emailCtrl.text.trim();
    if (e.isEmpty || !e.contains('@') || !e.contains('.')) {
      _setErr('Enter a valid email address'); return;
    }
    _next();
  }

  void _step3() {
    if (_passCtrl.text.length < 6) {
      _setErr('Password must be at least 6 characters'); return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      _setErr('Passwords do not match'); return;
    }
    _sendOtp();
  }

  void _setErr(String msg) => setState(() => _error = msg);

  // ── OTP ────────────────────────────────────────────────────────────────
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
          'code' : code,
          'name' : _firstCtrl.text.trim(),
        }),
      );
      if (res.statusCode == 200) {
        _next();
      } else {
        _setErr('Failed to send code. Try again.');
      }
    } catch (_) {
      _setErr('Network error. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _cooldown = true);
    await _sendOtp();
    await Future.delayed(const Duration(seconds: 30));
    if (mounted) setState(() => _cooldown = false);
  }

  Future<void> _createAccount() async {
    final entered = _otpCtrls.map((c) => c.text).join();
    if (entered.length < 6)       { _setErr('Enter the 6-digit code');     return; }
    if (entered != _sentCode)     {
      _setErr('Incorrect code. Check your email.');
      for (final c in _otpCtrls) c.clear();
      _otpFocus[0].requestFocus();
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final first  = _firstCtrl.text.trim();
      final middle = _middleCtrl.text.trim();
      final last   = _lastCtrl.text.trim();
      final full   = [first, if (middle.isNotEmpty) middle, last].join(' ');
      final email  = _emailCtrl.text.trim();
      final pass   = _passCtrl.text;
      final phone  = '${_country.dialCode}${_phoneCtrl.text.trim()}';

      final cred     = await auth.createUserWithEmailAndPassword(email: email, password: pass);
      final uid      = cred.user!.uid;
      final username = _genUsername(full, uid);

      await db.collection('users').doc(uid).set({
        'uid': uid, 'name': full, 'nameLower': full.toLowerCase(),
        'firstName': first, 'middleName': middle, 'lastName': last,
        'username': username, 'email': email,
        'phone': phone,
        'phoneNormalized': phone.replaceAll(RegExp(r'[\s\-()]'), ''),
        'birthday': _birthday?.toIso8601String(),
        'avatar': first[0].toUpperCase(),
        'gender': '',
        'verified': false, 'verifiedWaitlist': false,
        'suggestionsEnabled': true, 'friendsPublic': true,
        'profileMode': 'friend',
        'bio': '', 'city': '', 'education': '', 'work': '', 'hometown': '',
        'social': {
          'facebook': '', 'instagram': '', 'github': '',
          'linkedin': '', 'twitter': '',
        },
        'followerCount': 0, 'followingCount': 0, 'friendCount': 0,
        'fcmToken': '', 'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      FirebaseMessaging.instance.getToken().then((fcm) {
        if (fcm != null) db.collection('users').doc(uid).update({'fcmToken': fcm});
      });
      await cred.user!.updateDisplayName(full);

      if (mounted) Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));

    } on FirebaseAuthException catch (e) {
      String msg = 'Registration failed. Try again.';
      if (e.code == 'email-already-in-use') msg = 'This email is already registered.';
      if (e.code == 'invalid-email')        msg = 'Invalid email address.';
      if (e.code == 'weak-password')        msg = 'Password is too weak.';
      _setErr(msg);
      if (e.code == 'email-already-in-use' || e.code == 'invalid-email') {
        _pageCtrl.animateToPage(2,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
        setState(() => _page = 2);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _genUsername(String name, String uid) {
    final base   = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')
        .substring(0, name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').length.clamp(0, 12));
    final suffix = uid.substring(uid.length - 5);
    return '${base}_$suffix';
  }

  void _onPassChange(String v) {
    int s = 0;
    if (v.length >= 6)                          s++;
    if (v.length >= 10)                         s++;
    if (RegExp(r'[A-Z]').hasMatch(v))           s++;
    if (RegExp(r'[0-9!@#\$%^&*]').hasMatch(v)) s++;
    setState(() => _strength = s);
  }

  // ── Date picker ────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18),
      firstDate: DateTime(1924),
      lastDate: now.subtract(const Duration(days: 365 * 13)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: kAccent, surface: kCard),
          dialogBackgroundColor: kCard,
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() { _birthday = picked; _error = null; });
  }

  // ── Country picker ─────────────────────────────────────────────────────
  void _pickCountry() {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          final q        = searchCtrl.text.toLowerCase();
          final filtered = _kCountries
              .where((c) => c.name.toLowerCase().contains(q) || c.dialCode.contains(q))
              .toList();
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: kTextTertiary,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchCtrl,
                  onChanged: (_) => setSt(() {}),
                  autofocus: true,
                  style: const TextStyle(color: kTextPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search country...',
                    hintStyle: const TextStyle(color: kTextSecondary),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: kTextSecondary, size: 20),
                    filled: true, fillColor: kCard2,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(filtered[i].name,
                      style: const TextStyle(color: kTextPrimary, fontSize: 14)),
                  trailing: Text(filtered[i].dialCode,
                      style: const TextStyle(color: kAccent,
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  onTap: () {
                    setState(() => _country = filtered[i]);
                    Navigator.pop(ctx);
                  },
                ),
              )),
            ]),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _namesPage(),
              _birthdayPage(),
              _contactPage(),
              _passwordPage(),
              _otpPage(),
            ],
          )),
        ]),
      ),
    );
  }

  // ── Header bar ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    const total = 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 20, 12),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: kTextPrimary),
          onPressed: _back,
        ),
        Expanded(
          child: Row(
            children: List.generate(total, (i) {
              final filled = i <= _page;
              return Expanded(child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: 3,
                decoration: BoxDecoration(
                  color: filled ? kAccent : kCard2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ));
            }),
          ),
        ),
      ]),
    );
  }

  // ── Step 0: Names ──────────────────────────────────────────────────────
  Widget _namesPage() => _Page(
    step: '01',
    title: 'What\'s your name?',
    subtitle: 'This is how others will see you on Convo.',
    error: _error,
    btnLabel: 'Continue',
    loading: _loading,
    onContinue: _step0,
    children: [
      _Field(label: 'First Name',   ctrl: _firstCtrl,  hint: 'Enter your first name'),
      const SizedBox(height: 16),
      _Field(label: 'Middle Name',  ctrl: _middleCtrl, hint: 'Optional', optional: true),
      const SizedBox(height: 16),
      _Field(label: 'Last Name',    ctrl: _lastCtrl,   hint: 'Enter your last name'),
    ],
  );

  // ── Step 1: Birthday ───────────────────────────────────────────────────
  Widget _birthdayPage() {
    final hasDob = _birthday != null;
    final label  = hasDob
        ? '${_birthday!.day} ${_mon(_birthday!.month)} ${_birthday!.year}'
        : 'Select your date of birth';
    final age = hasDob
        ? DateTime.now().difference(_birthday!).inDays ~/ 365
        : 0;

    return _Page(
      step: '02',
      title: 'When were you born?',
      subtitle: 'You need to be at least 13 years old to use Convo.',
      error: _error,
      btnLabel: 'Continue',
      loading: _loading,
      onContinue: _step1,
      children: [
        GestureDetector(
          onTap: _pickDate,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasDob ? kAccent.withOpacity(0.65) : kDivider,
                width: hasDob ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded,
                  color: hasDob ? kAccent : kTextSecondary, size: 20),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(
                color: hasDob ? kTextPrimary : kTextSecondary,
                fontSize: 15,
                fontWeight: hasDob ? FontWeight.w500 : FontWeight.normal,
              )),
              const Spacer(),
              if (!hasDob)
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: kTextTertiary),
            ]),
          ),
        ),
        if (hasDob) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kAccent.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: kAccent, size: 16),
              const SizedBox(width: 8),
              Text('Age: $age years', style: const TextStyle(
                  color: kAccent, fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ],
    );
  }

  String _mon(int m) => const ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

  // ── Step 2: Contact ────────────────────────────────────────────────────
  Widget _contactPage() => _Page(
    step: '03',
    title: 'How can we reach you?',
    subtitle: 'We\'ll use these to secure your account.',
    error: _error,
    btnLabel: 'Continue',
    loading: _loading,
    onContinue: _step2,
    children: [
      // Phone
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _FieldLabel('Phone Number'),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Country code button
          GestureDetector(
            onTap: _pickCountry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: kCard, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kDivider, width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_country.dialCode, style: const TextStyle(
                    color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: kTextSecondary, size: 18),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _Field(ctrl: _phoneCtrl, hint: 'Phone number',
              type: TextInputType.phone)),
        ]),
      ]),
      const SizedBox(height: 18),
      _Field(label: 'Email Address', ctrl: _emailCtrl,
          hint: 'your@email.com', type: TextInputType.emailAddress),
    ],
  );

  // ── Step 3: Password ───────────────────────────────────────────────────
  Widget _passwordPage() {
    final match    = _passCtrl.text.isNotEmpty &&
        _confirmCtrl.text.isNotEmpty &&
        _passCtrl.text == _confirmCtrl.text;
    final mismatch = _confirmCtrl.text.isNotEmpty &&
        _passCtrl.text != _confirmCtrl.text;

    return _Page(
      step: '04',
      title: 'Secure your account',
      subtitle: 'Choose a strong password. Don\'t share it with anyone.',
      error: _error,
      btnLabel: _loading ? '' : 'Send Verification Code',
      loading: _loading,
      onContinue: _loading ? null : _step3,
      children: [
        _Field(
          label: 'Password', ctrl: _passCtrl,
          hint: 'Create a strong password',
          obscure: _ob1, onChanged: _onPassChange,
          suffix: IconButton(
            icon: Icon(_ob1 ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
                size: 20, color: kTextSecondary),
            onPressed: () => setState(() => _ob1 = !_ob1),
          ),
        ),
        if (_passCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          _strengthBar(),
        ],
        const SizedBox(height: 16),
        _Field(
          label: 'Confirm Password', ctrl: _confirmCtrl,
          hint: 'Re-enter your password',
          obscure: _ob2, onChanged: (_) => setState(() {}),
          suffix: Row(mainAxisSize: MainAxisSize.min, children: [
            if (match)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle_rounded, color: kAccent, size: 18)),
            if (mismatch)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.cancel_rounded, color: kRed, size: 18)),
            IconButton(
              icon: Icon(_ob2 ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
                  size: 20, color: kTextSecondary),
              onPressed: () => setState(() => _ob2 = !_ob2),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _strengthBar() {
    const colors = [kDivider, kRed, kOrange,
      Color(0xFFFFD60A), Color(0xFF34C759)];
    const labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
    return Row(children: [
      ...List.generate(4, (i) => Expanded(child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 3,
        margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
        decoration: BoxDecoration(
          color: i < _strength ? colors[_strength] : kCard2,
          borderRadius: BorderRadius.circular(2),
        ),
      ))),
      const SizedBox(width: 10),
      SizedBox(
        width: 40,
        child: Text(labels[_strength], style: TextStyle(
            color: colors[_strength], fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  // ── Step 4: OTP ────────────────────────────────────────────────────────
  Widget _otpPage() => _Page(
    step: '05',
    title: 'Verify your email',
    subtitle: 'Enter the 6-digit code sent to\n${_emailCtrl.text.trim()}',
    error: _error,
    btnLabel: _loading ? '' : 'Create Account',
    loading: _loading,
    onContinue: _loading ? null : _createAccount,
    children: [
      // Sent confirmation chip
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAccent.withOpacity(0.2)),
        ),
        child: Row(children: [
          const Icon(Icons.mark_email_read_rounded, color: kAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Code sent!', style: TextStyle(
                color: kAccent, fontWeight: FontWeight.w600, fontSize: 13)),
            Text('Check ${_emailCtrl.text.trim()}',
                style: const TextStyle(color: kTextSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
      const SizedBox(height: 28),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, _otpBox),
      ),
      const SizedBox(height: 20),
      Center(child: _cooldown
          ? const Text('Resend available in 30s',
          style: TextStyle(color: kTextSecondary, fontSize: 13))
          : TextButton.icon(
        icon: const Icon(Icons.refresh_rounded, color: kAccent, size: 16),
        label: const Text('Resend code',
            style: TextStyle(color: kAccent, fontSize: 13)),
        onPressed: _resendOtp,
      )),
    ],
  );

  Widget _otpBox(int i) => Container(
    width: 46, height: 56,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: kCard, borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _otpCtrls[i].text.isNotEmpty ? kAccent : kDivider,
        width: _otpCtrls[i].text.isNotEmpty ? 1.5 : 1,
      ),
    ),
    child: TextField(
      controller: _otpCtrls[i], focusNode: _otpFocus[i],
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number, maxLength: 1,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
          color: kTextPrimary),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(counterText: '', border: InputBorder.none),
      onChanged: (v) {
        setState(() {});
        if (v.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus();
        if (v.isEmpty  && i > 0)   _otpFocus[i - 1].requestFocus();
        if (i == 5 && v.isNotEmpty) {
          final all = _otpCtrls.map((c) => c.text).join();
          if (all.length == 6) _createAccount();
        }
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Reusable step page wrapper
// ═══════════════════════════════════════════════════════════════════════════
class _Page extends StatelessWidget {
  final String step, title, subtitle, btnLabel;
  final String?        error;
  final bool           loading;
  final VoidCallback?  onContinue;
  final List<Widget>   children;

  const _Page({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.error,
    required this.loading,
    required this.btnLabel,
    required this.onContinue,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Step chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: kAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kAccent.withOpacity(0.3)),
          ),
          child: Text('Step $step', style: const TextStyle(
              color: kAccent, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        const SizedBox(height: 16),

        // Title
        Text(title, style: const TextStyle(
            fontSize: 26, fontWeight: FontWeight.w700,
            color: kTextPrimary, letterSpacing: -0.5, height: 1.2)),
        const SizedBox(height: 8),

        // Subtitle
        Text(subtitle, style: const TextStyle(
            fontSize: 14, color: kTextSecondary, height: 1.55)),
        const SizedBox(height: 28),

        // Error
        if (error != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: kRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kRed.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: kRed, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(error!,
                  style: const TextStyle(color: kRed, fontSize: 13))),
            ]),
          ),
          const SizedBox(height: 18),
        ],

        // Content
        ...children,
        const SizedBox(height: 36),

        // Continue button
        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent, elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onContinue,
            child: loading
                ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
                : Text(btnLabel, style: const TextStyle(
                color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Premium animated input field
// ═══════════════════════════════════════════════════════════════════════════
class _Field extends StatefulWidget {
  final String? label, hint;
  final TextEditingController ctrl;
  final bool obscure, optional;
  final TextInputType? type;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  const _Field({
    this.label, this.hint, required this.ctrl,
    this.obscure = false, this.optional = false,
    this.type, this.onChanged, this.suffix,
  });

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
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
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.label != null) ...[
        Row(children: [
          _FieldLabel(widget.label!),
          if (widget.optional) ...[
            const SizedBox(width: 6),
            const Text('optional', style: TextStyle(
                color: kTextTertiary, fontSize: 11)),
          ],
        ]),
        const SizedBox(height: 8),
      ],
      AnimatedContainer(
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
          onChanged: widget.onChanged,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: kTextPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: kTextSecondary, fontSize: 15),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            suffixIcon: widget.suffix,
          ),
        ),
      ),
    ]);
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: kTextSecondary, fontSize: 12,
          fontWeight: FontWeight.w600, letterSpacing: 0.4));
}
