import 'package:flutter/material.dart';
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
        ScaleTransition(scale: _scale, child: Stack(
          alignment: Alignment.center,
          children: [
            Text('Convo',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3
                  ..color = kGreen,
              )),
            Text('Convo',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                foreground: Paint()
                  ..style = PaintingStyle.fill
                  ..color = kGreen.withOpacity(0.08),
              )),
          ])),
        const SizedBox(height: 16),
        const Text('powered by TheKami', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]))));
}