import 'dart:async';
import 'package:flutter/material.dart';
import '../core/constants.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> {
  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _step = (_step + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Text(
        '.' * _step,
        style: const TextStyle(
          color: kAccent,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: 3,
        ),
      ),
    );
  }
}
