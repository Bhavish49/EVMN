import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/evmn_screen.dart';

final _router = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const EvmnScreen(section: 'dashboard'),
    ),
    GoRoute(
      path: '/network',
      builder: (context, state) => const EvmnScreen(section: 'network'),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const EvmnScreen(section: 'profile'),
    ),
    GoRoute(
      path: '/modes',
      builder: (context, state) => const EvmnScreen(section: 'modes'),
    ),
    GoRoute(
      path: '/alerts',
      builder: (context, state) => const EvmnScreen(section: 'alerts'),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const EvmnScreen(section: 'history'),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const EvmnScreen(section: 'settings'),
    ),
  ],
);

class EvmnApp extends StatelessWidget {
  const EvmnApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'EVMN',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff1769aa),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xfff5f7fa),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    ),
    routerConfig: _router,
  );
}
