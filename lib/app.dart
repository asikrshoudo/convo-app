import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants.dart';
import 'screens/splash_screen.dart';

class ConvoApp extends StatelessWidget {
  const ConvoApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: themeNotifier,
    builder: (_, mode, __) => ValueListenableBuilder<Color>(
      valueListenable: accentColorNotifier,
      builder: (_, accent, __) {
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: kDark,
          systemNavigationBarIconBrightness: Brightness.light,
        ));
        return MaterialApp(
          title: 'Convo',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme:     _lightTheme(accent),
          darkTheme: _darkTheme(accent),
          home: const SplashScreen(),
        );
      }));

  // ── Dark theme ───────────────────────────────────────────────
  ThemeData _darkTheme(Color accent) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary:    accent,
      secondary:  kAccentLight,
      surface:    kCard,
      background: kDark,
      error:      kRed,
      onPrimary:  Colors.white,
      onSurface:  kTextPrimary,
    ),
    scaffoldBackgroundColor: kDark,
    fontFamily: 'SF Pro Display',

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: kDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        fontSize: 17, fontWeight: FontWeight.w600,
        color: kTextPrimary, letterSpacing: -0.3),
      iconTheme: IconThemeData(color: accent, size: 22),
    ),

    // NavigationBar (bottom)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withOpacity(0.18),
      labelTextStyle: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accent);
        }
        return const TextStyle(fontSize: 10, color: kTextSecondary);
      }),
      iconTheme: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return IconThemeData(color: accent, size: 22);
        }
        return const IconThemeData(color: kTextSecondary, size: 22);
      }),
    ),

    // Input
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5)),
      hintStyle: const TextStyle(color: kTextSecondary, fontSize: 15),
    ),

    // Text
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700,
          color: kTextPrimary, letterSpacing: -0.5),
      titleLarge:   TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
          color: kTextPrimary, letterSpacing: -0.3),
      titleMedium:  TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
          color: kTextPrimary, letterSpacing: -0.2),
      bodyLarge:    TextStyle(fontSize: 15, color: kTextPrimary),
      bodyMedium:   TextStyle(fontSize: 14, color: kTextPrimary),
      bodySmall:    TextStyle(fontSize: 12, color: kTextSecondary),
      labelSmall:   TextStyle(fontSize: 10, color: kTextSecondary, letterSpacing: 0.4),
    ),

    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      )),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      )),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      )),

    // Divider
    dividerTheme: const DividerThemeData(
        color: kDivider, thickness: 0.5, space: 0),

    // ListTile
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      iconColor: accent,
      titleTextStyle: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w400, color: kTextPrimary),
      subtitleTextStyle: const TextStyle(fontSize: 12, color: kTextSecondary),
    ),

    // BottomSheet
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetRadius))),
    ),

    // Dialog
    dialogTheme: DialogTheme(
      backgroundColor: kCard2,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius)),
      titleTextStyle: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600,
          color: kTextPrimary, letterSpacing: -0.2),
      contentTextStyle: const TextStyle(
          fontSize: 14, color: kTextSecondary),
    ),

    // SnackBar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kCard2,
      contentTextStyle: const TextStyle(color: kTextPrimary, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // ── Light theme ──────────────────────────────────────────────
  ThemeData _lightTheme(Color accent) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary:   accent,
      secondary: kAccentLight,
      surface:   Colors.white,
      background: const Color(0xFFF2F2F7),
      error:     kRed,
    ),
    scaffoldBackgroundColor: const Color(0xFFF2F2F7),
    fontFamily: 'SF Pro Display',
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600,
          color: Colors.black, letterSpacing: -0.3),
      iconTheme: IconThemeData(color: accent, size: 22),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      )),
  );
}
