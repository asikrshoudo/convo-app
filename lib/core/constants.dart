import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─── Firebase ────────────────────────────────────────────────
final db   = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// ─── Theme Notifiers ─────────────────────────────────────────
final themeNotifier       = ValueNotifier<ThemeMode>(ThemeMode.dark);
final accentColorNotifier = ValueNotifier<Color>(kAccent);

// ─── Brand Accent ─────────────────────────────────────────────
const Color kAccent      = Color(0xFF2C7BE5);
const Color kAccentLight = Color(0xFF5B9CF6);
const Color kGreen       = kAccent; // legacy alias

// ─── Backgrounds ─────────────────────────────────────────────
const Color kDark  = Color(0xFF000000);
const Color kDark2 = Color(0xFF0A0A0A);

// ─── Surfaces ────────────────────────────────────────────────
const Color kCard  = Color(0xFF1C1C1E);
const Color kCard2 = Color(0xFF2C2C2E);

// ─── Text ────────────────────────────────────────────────────
const Color kTextPrimary   = Color(0xFFFFFFFF);
const Color kTextSecondary = Color(0xFF8E8E93);
const Color kTextTertiary  = Color(0xFF48484A);

// ─── Misc ────────────────────────────────────────────────────
const Color kDivider = Color(0xFF38383A);
const Color kRed     = Color(0xFFFF3B30);
const Color kOrange  = Color(0xFFFF9500);

// ─── Chat bubbles ─────────────────────────────────────────────
const Color kBubbleMe    = kAccent;
const Color kBubbleOther = Color(0xFF2C2C2E);

// ─── Radius ──────────────────────────────────────────────────
const double kBubbleRadius = 20;
const double kCardRadius   = 16;
const double kSheetRadius  = 24;

// ─── Shadows ─────────────────────────────────────────────────
List<BoxShadow> kElevation1 = [
  BoxShadow(color: Colors.black.withOpacity(0.18),
      blurRadius: 8, offset: const Offset(0, 2)),
];
List<BoxShadow> kElevation2 = [
  BoxShadow(color: Colors.black.withOpacity(0.28),
      blurRadius: 16, offset: const Offset(0, 4)),
];

// ─── Accent color palette (used in Settings → Appearance) ────
const Map<String, Color> kAccentColors = {
  'Blue':   Color(0xFF2C7BE5),
  'Purple': Color(0xFF7C3AED),
  'Pink':   Color(0xFFEC4899),
  'Orange': Color(0xFFFF9500),
  'Teal':   Color(0xFF14B8A6),
  'Red':    Color(0xFFFF3B30),
  'Green':  Color(0xFF34C759),
  'Indigo': Color(0xFF4F46E5),
};
