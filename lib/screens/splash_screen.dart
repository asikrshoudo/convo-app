import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'auth/login_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => auth.currentUser != null
            ? const MainScreen()
            : const LoginScreen()));
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kDark,
    body: FadeTransition(
      opacity: _fade,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Column(children: [
                // Blue circle logo
                Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(
                    color: kAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kAccent.withOpacity(0.4),
                        blurRadius: 28,
                        offset: const Offset(0, 8)),
                    ]),
                  child: const Center(
                    child: Text('C',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1)))),
                const SizedBox(height: 20),
                const Text('Convo',
                  style: TextStyle(
                    color: kTextPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1)),
              ])),
            const SizedBox(height: 48),
            const Text('powered by TheKami',
              style: TextStyle(
                  color: kTextSecondary, fontSize: 13)),
          ]))));
}
