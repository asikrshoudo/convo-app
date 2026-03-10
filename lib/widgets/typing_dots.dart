import 'package:flutter/material.dart';
import '../core/constants.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) =>
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
        ..repeat(reverse: true, period: Duration(milliseconds: 900 + i * 150)));
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => Padding(
      padding: const EdgeInsets.only(right: 2),
      child: AnimatedBuilder(
        animation: _ctrls[i],
        builder: (_, __) => Transform.translate(
          offset: Offset(0, -3 * _ctrls[i].value),
          child: Container(
            width: 5, height: 5,
            decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle)))))));
}
