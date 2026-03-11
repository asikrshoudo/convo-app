import 'package:flutter/material.dart';
import 'core/constants.dart';
import 'screens/splash_screen.dart';

class ConvoApp extends StatelessWidget {
  const ConvoApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: themeNotifier,
    builder: (_, mode, __) => ValueListenableBuilder<Color>(
      valueListenable: accentColorNotifier,
      builder: (_, accent, __) => MaterialApp(
        title: 'Convo',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: accent,
          brightness: Brightness.light),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: accent,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kDark,
          navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF111111))),
        home: const SplashScreen())));
}
