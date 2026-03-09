import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const ConvoApp());
}

class ConvoApp extends StatelessWidget {
  const ConvoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Convo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00C853),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00C853),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF111111),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─── SPLASH ───────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00C853)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00C853).withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.chat_bubble_rounded,
                      color: Colors.white, size: 54),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Convo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
              const SizedBox(height: 8),
              const Text('powered by TheKami',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── LOGIN ────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int _tab = 0;
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1A1A1A) : Colors.grey[100]!;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 52),
              // Logo
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00C853)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Text('Convo',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 36),
              const Text('Welcome back 👋',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Sign in to continue chatting',
                  style: TextStyle(
                      color: Colors.grey[500], fontSize: 14)),
              const SizedBox(height: 28),

              // Email tab only
              _field('Email or Phone', Icons.person_outline,
                  false, isDark, cardBg),
              const SizedBox(height: 14),
              // Password field with toggle
              TextField(
                obscureText: _obscure,
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon:
                      const Icon(Icons.lock_outline, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: cardBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Forgot password?',
                      style: TextStyle(
                          color: Color(0xFF00C853), fontSize: 13)),
                ),
              ),
              const SizedBox(height: 8),
              // Sign In button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _goHome(),
                  child: const Text('Sign In',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 28),
              // Divider
              Row(children: [
                Expanded(
                    child: Divider(color: Colors.grey[700], thickness: 0.5)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or continue with',
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 13)),
                ),
                Expanded(
                    child: Divider(color: Colors.grey[700], thickness: 0.5)),
              ]),
              const SizedBox(height: 20),
              // GitHub button
              _socialBtn(
                'Continue with GitHub',
                Icons.code_rounded,
                isDark ? Colors.white : Colors.black,
                isDark ? const Color(0xFF1A1A1A) : Colors.grey[100]!,
                isDark ? Colors.white : Colors.black,
              ),
              const SizedBox(height: 12),
              // Google button
              _socialBtn(
                'Continue with Google',
                Icons.g_mobiledata_rounded,
                Colors.red,
                isDark ? const Color(0xFF1A1A1A) : Colors.grey[100]!,
                isDark ? Colors.white : Colors.black,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String hint, IconData icon, bool obscure,
      bool isDark, Color cardBg) {
    return TextField(
      obscureText: obscure,
      style:
          TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _socialBtn(String text, IconData icon, Color iconColor,
      Color bg, Color textColor) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[800]!, width: 0.5),
          ),
        ),
        icon: Icon(icon, color: iconColor, size: 22),
        label: Text(text,
            style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        onPressed: () => _goHome(),
      ),
    );
  }

  void _goHome() {
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const MainScreen()));
  }
}

// ─── MAIN NAV ─────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _idx = 0;
  final _screens = const [
    ChatsScreen(),
    FriendsScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        indicatorColor: const Color(0xFF00C853).withOpacity(0.2),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon:
                  Icon(Icons.chat_bubble, color: Color(0xFF00C853)),
              label: 'Chats'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon:
                  Icon(Icons.people, color: Color(0xFF00C853)),
              label: 'Friends'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon:
                  Icon(Icons.person, color: Color(0xFF00C853)),
              label: 'Profile'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon:
                  Icon(Icons.settings, color: Color(0xFF00C853)),
              label: 'Settings'),
        ],
      ),
    );
  }
}


// ─── CHATS ────────────────────────────────────────────
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  bool _searchActive = false;
  final _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg =
        isDark ? const Color(0xFF1A1A1A) : Colors.grey[100]!;

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF0A0A0A) : Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () {},
            child: const CircleAvatar(
              backgroundColor: Color(0xFF00C853),
              child: Text('A',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        title: _searchActive
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  border: InputBorder.none,
                ),
              )
            : const Text('Convo',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 24)),
        actions: [
          IconButton(
            icon: Icon(
                _searchActive ? Icons.close : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _searchActive = !_searchActive;
                if (!_searchActive) _searchCtrl.clear();
              });
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 72, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text('No conversations yet',
                style: TextStyle(
                    color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Find friends to start chatting!',
                style: TextStyle(
                    color: Color(0xFF00C853), fontSize: 14)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00C853),
        child: const Icon(Icons.edit_rounded, color: Colors.white),
        onPressed: () {},
      ),
    );
  }
}

// ─── FRIENDS ──────────────────────────────────────────
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg =
        isDark ? const Color(0xFF1A1A1A) : Colors.grey[100]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Search by username...',
              hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: cardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline,
                    size: 72, color: Colors.grey[700]),
                const SizedBox(height: 16),
                Text('No friends yet',
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 16)),
                const SizedBox(height: 8),
                const Text('Search username to add friends',
                    style: TextStyle(
                        color: Color(0xFF00C853), fontSize: 14)),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── PROFILE ──────────────────────────────────────────
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg =
        isDark ? const Color(0xFF1A1A1A) : Colors.grey[100]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.edit_outlined), onPressed: () {})
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          // Cover + avatar
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00C853).withOpacity(0.7),
                      const Color(0xFF004D20),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                bottom: -44,
                child: Stack(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: isDark
                                ? const Color(0xFF0A0A0A)
                                : Colors.white,
                            width: 4),
                      ),
                      child: const Center(
                        child: Text('A',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 56),
          // Name + username
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('asikrshoudo',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('@asikrshoudo',
              style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 16),
          // Verified badge promo
          GestureDetector(
            onTap: () => _showVerifyDialog(context),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFF007A33)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.verified_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Get Verified Badge ✓',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('0', 'Friends'),
              Container(
                  height: 32,
                  width: 1,
                  color: Colors.grey[800]),
              _stat('0', 'Groups'),
              Container(
                  height: 32,
                  width: 1,
                  color: Colors.grey[800]),
              _stat('0', 'Chats'),
            ],
          ),
          const SizedBox(height: 24),
          // Options
          _tile(context, Icons.edit_outlined, 'Change Name',
              'Update your display name', () {}),
          _tile(context, Icons.alternate_email,
              'Change Username', 'Unique @username', () {}),
          _tile(context, Icons.language, 'Language',
              'Bangla / English', () {}),
          _tile(context, Icons.lock_outline, 'Privacy',
              'Control who sees your info', () {}),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _stat(String val, String label) {
    return Column(children: [
      Text(val,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
    ]);
  }

  Widget _tile(BuildContext ctx, IconData icon, String title,
      String sub, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF00C853).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF00C853), size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(sub,
          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showVerifyDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded,
                color: Color(0xFF00C853), size: 48),
            const SizedBox(height: 16),
            const Text('Get Verified',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                'Show everyone you\'re the real deal with a blue checkmark',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 24),
            _planTile('Monthly', '\$1.99/month', false),
            const SizedBox(height: 10),
            _planTile('Yearly', '\$14.99/year  🔥 Save 37%', true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Coming Soon',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planTile(String title, String price, bool highlight) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(
            color: highlight
                ? const Color(0xFF00C853)
                : Colors.grey[700]!),
        borderRadius: BorderRadius.circular(12),
        color: highlight
            ? const Color(0xFF00C853).withOpacity(0.1)
            : Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(price,
              style: TextStyle(
                  color: highlight
                      ? const Color(0xFF00C853)
                      : Colors.grey[400],
                  fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── SETTINGS ─────────────────────────────────────────
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () {},
            child: const CircleAvatar(
              backgroundColor: Color(0xFF00C853),
              child: Text('A',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
      body: ListView(children: [
        // Profile card
        GestureDetector(
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF1A1A1A) : Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFF00C853),
                child: Text('A',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('asikrshoudo',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('@asikrshoudo',
                          style: TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ]),
          ),
        ),
        _section('Preferences'),
        _tile(Icons.notifications_outlined, 'Notifications',
            'Manage alerts', () {}),
        _tile(Icons.lock_outline, 'Privacy & Security',
            'Control your data', () {}),
        _tile(Icons.palette_outlined, 'Appearance',
            'Theme, colors', () {}),
        _tile(Icons.language_outlined, 'Language',
            'Bangla / English', () {}),
        _section('Account'),
        _tile(Icons.verified_outlined, 'Get Verified',
            'Monthly or yearly plan', () {}),
        _tile(Icons.block_outlined, 'Blocked Users',
            'Manage blocked list', () {}),
        _tile(Icons.delete_outline, 'Delete Account',
            'Permanently remove account', () {}),
        _section('About'),
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF00C853).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline,
                color: Color(0xFF00C853), size: 20),
          ),
          title: const Text('App Version'),
          subtitle: const Text('Convo v1.0.0.3',
              style: TextStyle(color: Colors.grey)),
          trailing:
              const Icon(Icons.chevron_right, color: Colors.grey),
        ),
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF00C853).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.favorite_outline,
                color: Color(0xFF00C853), size: 20),
          ),
          title: const Text('Powered by TheKami'),
          trailing: const Icon(Icons.open_in_new,
              size: 16, color: Colors.grey),
          onTap: () => _openLink('https://www.thekami.tech'),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              color: Color(0xFF00C853),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4)),
    );
  }

  Widget _tile(IconData icon, String title, String sub,
      VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF00C853).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF00C853), size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(sub,
          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      trailing:
          const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
