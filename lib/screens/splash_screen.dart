import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/constants.dart';
import 'auth/login_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => auth.currentUser != null ? const MainScreen() : const LoginScreen()));
    });
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kDark,
    body: FadeTransition(opacity: _fade, child: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(scale: _scale, child: Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00E676), kGreen],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 8))]),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SvgPicture.asset('assets/white_logo.svg', fit: BoxFit.contain)))),
        const SizedBox(height: 24),
        const Text('Convo',
          style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('powered by TheKami', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]))));
}
