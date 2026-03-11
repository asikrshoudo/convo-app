import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Red error banner shown above forms.
Widget errorBox(String msg) => Container(
  padding: const EdgeInsets.all(12),
  margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(
    color: kRed.withOpacity(0.1),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: kRed.withOpacity(0.3))),
  child: Row(children: [
    const Icon(Icons.error_outline_rounded, color: kRed, size: 18),
    const SizedBox(width: 8),
    Expanded(child: Text(msg,
        style: const TextStyle(color: kRed, fontSize: 13))),
  ]));

/// Basic text field used across auth screens.
Widget inputField(
  String hint,
  IconData icon,
  TextEditingController ctrl,
  bool obscure,
  bool isDark,
  Color bg, {
  TextInputType? type,
}) => TextField(
  controller: ctrl,
  obscureText: obscure,
  keyboardType: type,
  style: TextStyle(color: isDark ? kTextPrimary : Colors.black87),
  decoration: InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: kTextSecondary),
    prefixIcon: const Icon(Icons.person, color: kTextSecondary),
    filled: true,
    fillColor: bg,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none)));

/// Full-width primary button.
Widget primaryButton(String label, VoidCallback? onTap,
    {bool loading = false}) =>
  SizedBox(
    width: double.infinity,
    height: 54,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccent,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16))),
      onPressed: onTap,
      child: loading
        ? const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2))
        : Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold))));

/// Small icon container (accent tinted box).
Widget iconBox(IconData icon) => Container(
  width: 40, height: 40,
  decoration: BoxDecoration(
    color: kAccent.withOpacity(0.12),
    borderRadius: BorderRadius.circular(10)),
  child: Icon(icon, color: kAccent, size: 20));
