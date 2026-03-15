import 'package:flutter/material.dart';

/// A single chat theme — background + bubble colours.
class ChatThemeData {
  final String id;
  final String name;

  /// Solid background colour (used when no bgAsset).
  final Color bgDark;
  final Color bgLight;

  /// Optional bundled asset path, e.g. 'assets/themes/forest.jpg'.
  /// null = solid colour background only.
  final String? bgAsset;

  /// Bubble colour for the sender ("me") side.
  final Color bubbleMe;

  /// Bubble colour for the other person — dark mode.
  final Color bubbleOtherDark;

  /// Bubble colour for the other person — light mode.
  final Color bubbleOtherLight;

  /// Accent for "me" bubble text (always white for dark bubbles).
  final Color textMe;

  const ChatThemeData({
    required this.id,
    required this.name,
    required this.bgDark,
    required this.bgLight,
    this.bgAsset,
    required this.bubbleMe,
    required this.bubbleOtherDark,
    required this.bubbleOtherLight,
    this.textMe = Colors.white,
  });
}

// ─── 6 preset themes ──────────────────────────────────────────────────────────

const kChatThemes = <ChatThemeData>[
  // 0 · Default — unchanged app colours
  ChatThemeData(
    id:               'default',
    name:             'Default',
    bgDark:           Color(0xFF000000),
    bgLight:          Color(0xFFF2F2F7),
    bubbleMe:         Color(0xFF2979FF),
    bubbleOtherDark:  Color(0xFF1E1E1E),
    bubbleOtherLight: Color(0xFFFFFFFF),
  ),

  // 1 · Forest — deep green vibes
  // bgAsset: 'assets/themes/forest.jpg'   ← add photo here
  ChatThemeData(
    id:               'forest',
    name:             'Forest',
    bgDark:           Color(0xFF0A1A0F),
    bgLight:          Color(0xFFE8F5E9),
    bgAsset:          'assets/themes/forest.jpg',
    bubbleMe:         Color(0xFF2E7D32),
    bubbleOtherDark:  Color(0xFF1B2F1E),
    bubbleOtherLight: Color(0xFFDCEDDC),
  ),

  // 2 · Ocean — deep blue tones
  // bgAsset: 'assets/themes/ocean.jpg'
  ChatThemeData(
    id:               'ocean',
    name:             'Ocean',
    bgDark:           Color(0xFF051525),
    bgLight:          Color(0xFFE3F2FD),
    bgAsset:          'assets/themes/ocean.jpg',
    bubbleMe:         Color(0xFF0277BD),
    bubbleOtherDark:  Color(0xFF0D2035),
    bubbleOtherLight: Color(0xFFD6EAF8),
  ),

  // 3 · Sunset — warm orange/red
  // bgAsset: 'assets/themes/sunset.jpg'
  ChatThemeData(
    id:               'sunset',
    name:             'Sunset',
    bgDark:           Color(0xFF1A0A00),
    bgLight:          Color(0xFFFFF3E0),
    bgAsset:          'assets/themes/sunset.jpg',
    bubbleMe:         Color(0xFFE65100),
    bubbleOtherDark:  Color(0xFF2D1500),
    bubbleOtherLight: Color(0xFFFFE0B2),
  ),

  // 4 · Minimal — near-black, soft grey bubbles
  ChatThemeData(
    id:               'minimal',
    name:             'Minimal',
    bgDark:           Color(0xFF0D0D0D),
    bgLight:          Color(0xFFF5F5F5),
    bubbleMe:         Color(0xFF424242),
    bubbleOtherDark:  Color(0xFF1A1A1A),
    bubbleOtherLight: Color(0xFFEEEEEE),
    textMe:           Colors.white,
  ),

  // 5 · Neon — very dark + electric purple
  // bgAsset: 'assets/themes/neon.jpg'
  ChatThemeData(
    id:               'neon',
    name:             'Neon',
    bgDark:           Color(0xFF08000F),
    bgLight:          Color(0xFFF3E5F5),
    bgAsset:          'assets/themes/neon.jpg',
    bubbleMe:         Color(0xFF7B1FA2),
    bubbleOtherDark:  Color(0xFF180D22),
    bubbleOtherLight: Color(0xFFE8D5F5),
  ),
];

/// Returns theme by id, falls back to default.
ChatThemeData themeById(String? id) =>
  kChatThemes.firstWhere((t) => t.id == id,
    orElse: () => kChatThemes.first);
