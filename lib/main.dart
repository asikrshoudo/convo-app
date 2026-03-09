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
        scaffoldBackgroundColor: Colors.black,
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
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
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 50),
              ),
              const SizedBox(height: 20),
              const Text('Convo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C853),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                const Text('Convo',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 32),
              const Text('Welcome back',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Sign in to continue',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              const SizedBox(height: 28),
              // Tab selector
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C1C)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: ['Email', 'GitHub', 'Google']
                      .asMap()
                      .entries
                      .map((e) => Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _tab = e.key),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 200),
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                                decoration: BoxDecoration(
                                  color: _tab == e.key
                                      ? const Color(0xFF00C853)
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(9),
                                ),
                                child: Text(e.value,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _tab == e.key
                                          ? Colors.white
                                          : Colors.grey,
                                    )),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 24),
              if (_tab == 0) _emailForm(isDark),
              if (_tab == 1) _oauthButton(
                  'Continue with GitHub',
                  Icons.code,
                  Colors.white,
                  Colors.black),
              if (_tab == 2) _oauthButton(
                  'Continue with Google',
                  Icons.g_mobiledata_rounded,
                  Colors.white,
                  Colors.red),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context,
                      MaterialPageRoute(
                          builder: (_) => const MainScreen())),
                  child: const Text('Continue as Guest',
                      style: TextStyle(color: Color(0xFF00C853))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emailForm(bool isDark) {
    return Column(children: [
      _field('Email or Phone', Icons.person_outline, false, isDark),
      const SizedBox(height: 14),
      _field('Password', Icons.lock_outline, true, isDark),
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
          onPressed: () => Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const MainScreen())),
          child: const Text('Sign In',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    ]);
  }

  Widget _field(
      String hint, IconData icon, bool obscure, bool isDark) {
    return TextField(
      obscureText: obscure,
      style: TextStyle(
          color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor:
            isDark ? const Color(0xFF1C1C1C) : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _oauthButton(
      String text, IconData icon, Color fg, Color bg) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, color: fg),
        label: Text(text,
            style: TextStyle(
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        onPressed: () => Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const MainScreen())),
      ),
    );
  }
}

// ─── MAIN (Bottom Nav) ────────────────────────────────
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
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convo',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        actions: [
          IconButton(
              icon: const Icon(Icons.edit_outlined), onPressed: () {}),
        ],
      ),
      body: Column(children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF1C1C1C)
                  : Colors.grey[100],
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
                Icon(Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey[600]),
                const SizedBox(height: 12),
                Text('No conversations yet',
                    style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 6),
                const Text('Find friends to start chatting!',
                    style: TextStyle(
                        color: Color(0xFF00C853), fontSize: 13)),
              ],
            ),
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00C853),
        child: const Icon(Icons.edit, color: Colors.white),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
              fillColor: isDark
                  ? const Color(0xFF1C1C1C)
                  : Colors.grey[100],
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
                    size: 64, color: Colors.grey[600]),
                const SizedBox(height: 12),
                Text('No friends yet',
                    style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 6),
                const Text('Search username to add friends',
                    style: TextStyle(
                        color: Color(0xFF00C853), fontSize: 13)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFF00C853),
            child: const Text('A',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          const Text('asikrshoudo',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('@asikrshoudo',
              style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 32),
          _tile(context, Icons.edit_outlined, 'Change Name', () {}),
          _tile(context, Icons.alternate_email, 'Username', () {}),
          _tile(context, Icons.language, 'Language', () {}),
        ]),
      ),
    );
  }

  Widget _tile(BuildContext ctx, IconData icon, String title,
      VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00C853)),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// ─── SETTINGS ─────────────────────────────────────────
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _openLink() async {
    final uri = Uri.parse('https://www.thekami.tech');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(children: [
        const SizedBox(height: 8),
        _section('Account'),
        _tile(context, Icons.notifications_outlined,
            'Notifications', () {}),
        _tile(context, Icons.lock_outline, 'Privacy', () {}),
        _tile(
            context, Icons.palette_outlined, 'Appearance', () {}),
        _section('About'),
        _tile(context, Icons.info_outline, 'App Version', () {},
            trailing: const Text('v1.0.0.2',
                style: TextStyle(color: Colors.grey))),
        ListTile(
          leading: const Icon(Icons.favorite_outline,
              color: Color(0xFF00C853)),
          title: const Text('Powered by TheKami'),
          trailing: const Icon(Icons.open_in_new,
              size: 18, color: Colors.grey),
          onTap: _openLink,
        ),
      ]),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                color: Color(0xFF00C853),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
      ),
    );
  }

  Widget _tile(
      BuildContext ctx, IconData icon, String title, VoidCallback onTap,
      {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
