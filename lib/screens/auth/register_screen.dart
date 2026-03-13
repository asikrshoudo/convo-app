// lib/screens/auth/register_screen.dart
// ═══════════════════════════════════════════════════════════════════════════
//  5-step premium registration
//  Names → Birthday → Phone + Email → Password → Done (Firebase sends mail)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../main_screen.dart';
import 'login_screen.dart';

// ── Country model ──────────────────────────────────────────────────────────
class Country {
  final String name, code;
  const Country(this.name, this.code);
}

const kCountries = [
  Country('Bangladesh',      '+880'),
  Country('India',           '+91'),
  Country('Pakistan',        '+92'),
  Country('United States',   '+1'),
  Country('United Kingdom',  '+44'),
  Country('Canada',          '+1'),
  Country('Australia',       '+61'),
  Country('UAE',             '+971'),
  Country('Saudi Arabia',    '+966'),
  Country('Qatar',           '+974'),
  Country('Kuwait',          '+965'),
  Country('Bahrain',         '+973'),
  Country('Oman',            '+968'),
  Country('Malaysia',        '+60'),
  Country('Singapore',       '+65'),
  Country('Indonesia',       '+62'),
  Country('Philippines',     '+63'),
  Country('Thailand',        '+66'),
  Country('Myanmar',         '+95'),
  Country('Nepal',           '+977'),
  Country('Sri Lanka',       '+94'),
  Country('China',           '+86'),
  Country('Japan',           '+81'),
  Country('South Korea',     '+82'),
  Country('Germany',         '+49'),
  Country('France',          '+33'),
  Country('Italy',           '+39'),
  Country('Spain',           '+34'),
  Country('Netherlands',     '+31'),
  Country('Sweden',          '+46'),
  Country('Norway',          '+47'),
  Country('Turkey',          '+90'),
  Country('Russia',          '+7'),
  Country('Egypt',           '+20'),
  Country('Nigeria',         '+234'),
  Country('South Africa',    '+27'),
  Country('Kenya',           '+254'),
  Country('Brazil',          '+55'),
  Country('Mexico',          '+52'),
  Country('Argentina',       '+54'),
  Country('Morocco',         '+212'),
  Country('Jordan',          '+962'),
  Country('Lebanon',         '+961'),
  Country('Iraq',            '+964'),
  Country('Iran',            '+98'),
  Country('Afghanistan',     '+93'),
  Country('Kazakhstan',      '+7'),
  Country('New Zealand',     '+64'),
  Country('Ireland',         '+353'),
  Country('Portugal',        '+351'),
  Country('Poland',          '+48'),
  Country('Greece',          '+30'),
  Country('Vietnam',         '+84'),
  Country('Cambodia',        '+855'),
  Country('Ghana',           '+233'),
  Country('Tanzania',        '+255'),
  Country('Ethiopia',        '+251'),
  Country('Israel',          '+972'),
  Country('Palestine',       '+970'),
  Country('Maldives',        '+960'),
];

// ═══════════════════════════════════════════════════════════════════════════
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {

  final _pageCtrl = PageController();
  int     _page    = 0;
  bool    _loading = false;
  String? _error;

  // Step 0 — Names
  final _firstCtrl  = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl   = TextEditingController();

  // Step 1 — Birthday
  DateTime? _dob;

  // Step 2 — Contact
  Country  _country = kCountries[0];
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Step 3 — Password
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _ob1 = true, _ob2 = true;
  int  _strength = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _firstCtrl.dispose(); _middleCtrl.dispose(); _lastCtrl.dispose();
    _phoneCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose();  _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────
  void _next() {
    _pageCtrl.animateToPage(_page + 1,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic);
    setState(() { _page++; _error = null; });
  }

  void _back() {
    if (_page == 0) { Navigator.pop(context); return; }
    _pageCtrl.animateToPage(_page - 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic);
    setState(() { _page--; _error = null; });
  }

  // ── Step validations ───────────────────────────────────────────────────
  void _step0() {
    if (_firstCtrl.text.trim().isEmpty) { _err('First name is required'); return; }
    if (_lastCtrl.text.trim().isEmpty)  { _err('Last name is required');  return; }
    _next();
  }

  void _step1() {
    if (_dob == null) { _err('Please select your date of birth'); return; }
    final age = DateTime.now().difference(_dob!).inDays ~/ 365;
    if (age < 13) { _err('You must be at least 13 years old'); return; }
    _next();
  }

  void _step2() {
    final e = _emailCtrl.text.trim();
    if (_phoneCtrl.text.trim().isEmpty) { _err('Phone number is required'); return; }
    if (e.isEmpty || !e.contains('@') || !e.contains('.')) {
      _err('Enter a valid email address'); return;
    }
    _next();
  }

  void _step3() {
    if (_passCtrl.text.length < 6) {
      _err('Password must be at least 6 characters'); return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      _err('Passwords do not match'); return;
    }
    _createAccount();
  }

  // ── Create account ─────────────────────────────────────────────────────
  Future<void> _createAccount() async {
    setState(() { _loading = true; _error = null; });
    try {
      final first  = _firstCtrl.text.trim();
      final middle = _middleCtrl.text.trim();
      final last   = _lastCtrl.text.trim();
      final full   = [first, if (middle.isNotEmpty) middle, last].join(' ');
      final email  = _emailCtrl.text.trim();
      final pass   = _passCtrl.text;
      final phone  = '${_country.code}${_phoneCtrl.text.trim()}';

      final cred     = await auth.createUserWithEmailAndPassword(
          email: email, password: pass);
      final uid      = cred.user!.uid;
      final username = _genUsername(full, uid);

      await db.collection('users').doc(uid).set({
        'uid': uid, 'name': full, 'nameLower': full.toLowerCase(),
        'firstName': first, 'middleName': middle, 'lastName': last,
        'username': username, 'email': email,
        'phone': phone,
        'phoneNormalized': phone.replaceAll(RegExp(r'[\s\-()]'), ''),
        'birthday': _dob?.toIso8601String(),
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

      // Firebase automatically sends verification email
      await cred.user!.sendEmailVerification();

      if (mounted) _next(); // go to success page (page 4)

    } on FirebaseAuthException catch (e) {
      String msg = 'Registration failed. Try again.';
      if (e.code == 'email-already-in-use') msg = 'This email is already registered.';
      if (e.code == 'invalid-email')        msg = 'Invalid email address.';
      if (e.code == 'weak-password')        msg = 'Password is too weak.';
      _err(msg);
      if (e.code == 'email-already-in-use' || e.code == 'invalid-email') {
        _pageCtrl.animateToPage(2,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
        setState(() => _page = 2);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _genUsername(String name, String uid) {
    final base = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')
        .substring(0, name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .length.clamp(0, 12));
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

  void _err(String m) => setState(() { _error = m; _loading = false; });

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
    if (picked != null) setState(() { _dob = picked; _error = null; });
  }

  // ── Country picker ─────────────────────────────────────────────────────
  void _pickCountry() {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetRadius))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          final q   = searchCtrl.text.toLowerCase();
          final list = kCountries
              .where((c) => c.name.toLowerCase().contains(q) ||
              c.code.contains(q))
              .toList();
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(children: [
              const SizedBox(height: 12),
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: kTextTertiary,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PremiumField(
                  ctrl: searchCtrl, hint: 'Search country...',
                  icon: Icons.search_rounded,
                  // rebuild on change
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: StatefulBuilder(
                builder: (_, ss) => ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(list[i].name,
                        style: const TextStyle(
                            color: kTextPrimary, fontSize: 14)),
                    trailing: Text(list[i].code,
                        style: const TextStyle(
                            color: kAccent, fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    onTap: () {
                      setState(() => _country = list[i]);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              )),
            ]),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _namesPage(),
              _birthdayPage(),
              _contactPage(),
              _passwordPage(),
              _successPage(),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 20, 10),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 20, color: kTextPrimary),
        onPressed: _page < 4 ? _back : null,
      ),
      Expanded(child: Row(
        children: List.generate(4, (i) {
          final active = i <= _page && _page < 4;
          return Expanded(child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 3,
            decoration: BoxDecoration(
              color: active ? kAccent : kCard2,
              borderRadius: BorderRadius.circular(2),
            ),
          ));
        }),
      )),
    ]),
  );

  // ── Page wrapper ───────────────────────────────────────────────────────
  Widget _wrap({
    required String stepNum,
    required String title,
    required String subtitle,
    required String btnLabel,
    required VoidCallback? onContinue,
    required List<Widget> children,
  }) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Step chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kAccent.withOpacity(0.3)),
            ),
            child: Text('Step $stepNum of 4', style: const TextStyle(
                color: kAccent, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          const SizedBox(height: 16),

          Text(title, style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700,
              color: kTextPrimary, letterSpacing: -0.5, height: 1.2)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(
              fontSize: 14, color: kTextSecondary, height: 1.55)),
          const SizedBox(height: 28),

          if (_error != null) ...[
            AuthErrorBox(msg: _error!),
            const SizedBox(height: 18),
          ],

          ...children,
          const SizedBox(height: 36),

          SizedBox(width: double.infinity, height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: onContinue,
              child: _loading
                  ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
                  : Text(btnLabel, style: const TextStyle(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w600)),
            )),
        ]),
      );

  // ── Pages ──────────────────────────────────────────────────────────────

  Widget _namesPage() => _wrap(
    stepNum: '01', title: 'What\'s your name?',
    subtitle: 'This is how others will see you on Convo.',
    btnLabel: 'Continue', onContinue: _step0,
    children: [
      PremiumField(label: 'First Name', ctrl: _firstCtrl,
          hint: 'Enter your first name'),
      const SizedBox(height: 16),
      PremiumField(label: 'Middle Name (optional)', ctrl: _middleCtrl,
          hint: 'Optional'),
      const SizedBox(height: 16),
      PremiumField(label: 'Last Name', ctrl: _lastCtrl,
          hint: 'Enter your last name'),
    ],
  );

  Widget _birthdayPage() {
    final hasDob = _dob != null;
    final label  = hasDob
        ? '${_dob!.day} ${_mon(_dob!.month)} ${_dob!.year}'
        : 'Tap to select';
    final age = hasDob
        ? DateTime.now().difference(_dob!).inDays ~/ 365 : 0;

    return _wrap(
      stepNum: '02', title: 'When were you born?',
      subtitle: 'You must be at least 13 years old to use Convo.',
      btnLabel: 'Continue', onContinue: _step1,
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
                color: hasDob ? kAccent.withOpacity(0.6) : kDivider,
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
                  fontWeight: hasDob ? FontWeight.w500 : FontWeight.normal)),
              const Spacer(),
              if (!hasDob) const Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: kTextTertiary),
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
              const Icon(Icons.check_circle_rounded, color: kAccent, size: 15),
              const SizedBox(width: 8),
              Text('Age: $age years', style: const TextStyle(
                  color: kAccent, fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ],
    );
  }

  String _mon(int m) => const [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ][m - 1];

  Widget _contactPage() => _wrap(
    stepNum: '03', title: 'How can we reach you?',
    subtitle: 'Your phone and email are used to secure your account.',
    btnLabel: 'Continue', onContinue: _step2,
    children: [
      // Phone row
      const Text('Phone Number', style: TextStyle(
          color: kTextSecondary, fontSize: 12,
          fontWeight: FontWeight.w600, letterSpacing: 0.4)),
      const SizedBox(height: 8),
      Row(children: [
        GestureDetector(
          onTap: _pickCountry,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kDivider),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_country.code, style: const TextStyle(
                  color: kTextPrimary, fontWeight: FontWeight.w600,
                  fontSize: 15)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: kTextSecondary, size: 16),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: PremiumField(
          ctrl: _phoneCtrl, hint: 'Phone number',
          icon: Icons.phone_outlined, type: TextInputType.phone,
        )),
      ]),
      const SizedBox(height: 18),
      PremiumField(
        label: 'Email Address', ctrl: _emailCtrl,
        hint: 'your@email.com', icon: Icons.email_outlined,
        type: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kCard2, borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded,
              color: kTextTertiary, size: 14),
          const SizedBox(width: 8),
          const Expanded(child: Text(
            'A verification link will be sent to your email after registration.',
            style: TextStyle(color: kTextSecondary, fontSize: 12, height: 1.4),
          )),
        ]),
      ),
    ],
  );

  Widget _passwordPage() {
    final match    = _passCtrl.text.isNotEmpty &&
        _confirmCtrl.text.isNotEmpty &&
        _passCtrl.text == _confirmCtrl.text;
    final mismatch = _confirmCtrl.text.isNotEmpty &&
        _passCtrl.text != _confirmCtrl.text;

    return _wrap(
      stepNum: '04', title: 'Secure your account',
      subtitle: 'Choose a strong password. Don\'t share it with anyone.',
      btnLabel: _loading ? '' : 'Create Account',
      onContinue: _loading ? null : _step3,
      children: [
        PremiumField(
          label: 'Password', ctrl: _passCtrl,
          hint: 'Create a strong password',
          icon: Icons.lock_outline_rounded,
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
        PremiumField(
          label: 'Confirm Password', ctrl: _confirmCtrl,
          hint: 'Re-enter your password',
          icon: Icons.lock_outline_rounded,
          obscure: _ob2, onChanged: (_) => setState(() {}),
          suffix: Row(mainAxisSize: MainAxisSize.min, children: [
            if (match) const Padding(padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle_rounded, color: kAccent, size: 18)),
            if (mismatch) const Padding(padding: EdgeInsets.only(right: 4),
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
      SizedBox(width: 40, child: Text(labels[_strength],
          style: TextStyle(color: colors[_strength], fontSize: 11,
              fontWeight: FontWeight.w600))),
    ]);
  }

  // ── Success page ───────────────────────────────────────────────────────
  Widget _successPage() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
    child: Column(children: [
      // Animated check circle
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFF34C759).withOpacity(0.12),
          shape: BoxShape.circle,
          border: Border.all(
              color: const Color(0xFF34C759).withOpacity(0.4), width: 2),
        ),
        child: const Icon(Icons.check_rounded,
            color: Color(0xFF34C759), size: 44),
      ),
      const SizedBox(height: 28),
      const Text('Account created!', style: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w700,
          color: kTextPrimary, letterSpacing: -0.5)),
      const SizedBox(height: 12),
      Text(
        'We\'ve sent a verification link to\n${_emailCtrl.text.trim()}',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: kTextSecondary, fontSize: 15, height: 1.6),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAccent.withOpacity(0.2)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: kAccent, size: 15),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Verify your email to unlock all features. '
                'You can still sign in without verification.',
            style: TextStyle(color: kAccent, fontSize: 12, height: 1.5),
          )),
        ]),
      ),
      const SizedBox(height: 48),
      SizedBox(width: double.infinity, height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: kAccent, elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
                (_) => false,
          ),
          child: const Text('Go to Convo', style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        )),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () async {
          await auth.currentUser?.sendEmailVerification();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Verification email resent!'),
                backgroundColor: kAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: const Text('Resend verification email',
            style: TextStyle(color: kTextSecondary, fontSize: 13)),
      ),
    ]),
  );
}
