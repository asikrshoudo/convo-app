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
