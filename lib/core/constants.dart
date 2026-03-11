import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─── Colors ─────────────────────────────────────────────────────────────────
const kGreen = Color(0xFF00C853);
const kDark  = Color(0xFF0A0A0A);
const kCard  = Color(0xFF1A1A1A);
const kCard2 = Color(0xFF222222);

// ─── Firebase singletons ────────────────────────────────────────────────────
final db   = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// ─── Global theme controller ────────────────────────────────────────────────
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

// ─── Accent color options ───────────────────────────────────────────────────
const kAccentColors = <String, Color>{
  'Green'  : Color(0xFF00C853),
  'Blue'   : Color(0xFF2979FF),
  'Purple' : Color(0xFF7C4DFF),
  'Pink'   : Color(0xFFFF4081),
  'Orange' : Color(0xFFFF6D00),
  'Teal'   : Color(0xFF00BCD4),
  'Red'    : Color(0xFFE53935),
  'Yellow' : Color(0xFFFFD600),
};

final accentColorNotifier = ValueNotifier<Color>(kGreen);
