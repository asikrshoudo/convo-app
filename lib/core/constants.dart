import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─── Firebase ────────────────────────────────────────────────
final db   = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// ─── Theme Notifiers (used in app.dart + settings) ───────────
final themeNotifier       = ValueNotifier<ThemeMode>(ThemeMode.dark);
final accentColorNotifier = ValueNotifier<Color>(kAccent);

// ─── Brand Accent ─────────────────────────────────────────────
/// iMessage-style blue — replaces old green
const Color kAccent      = Color(0xFF2C7BE5);
const Color kAccentLight = Color(0xFF5B9CF6);
const Color kGreen       = kAccent; // legacy alias — old refs continue to compile

// ─── Backgrounds ─────────────────────────────────────────────
const Color kDark  = Color(0xFF000000); // pure iOS dark
const Color kDark2 = Color(0xFF0A0A0A);

// ─── Surfaces ────────────────────────────────────────────────
const Color kCard  = Color(0xFF1C1C1E); // elevated surface  (alias kSurface)
const Color kCard2 = Color(0xFF2C2C2E); // secondary surface

// ─── Text ────────────────────────────────────────────────────
const Color kTextPrimary   = Color(0xFFFFFFFF);
const Color kTextSecondary = Color(0xFF8E8E93); // iOS grey
const Color kTextTertiary  = Color(0xFF48484A);

// ─── Misc ────────────────────────────────────────────────────
const Color kDivider = Color(0xFF38383A);
const Color kRed     = Color(0xFFFF3B30);
const Color kOrange  = Color(0xFFFF9500);

// ─── Chat bubbles ─────────────────────────────────────────────
const Color kBubbleMe    = kAccent;
const Color kBubbleOther = Color(0xFF2C2C2E);

// ─── Radius constants ────────────────────────────────────────
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
