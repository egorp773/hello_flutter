import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_preview/device_preview.dart';
import 'package:go_router/go_router.dart';

import 'features/home/home_screen.dart';
import 'features/manual/manual_control_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      child: kReleaseMode
          ? const _RootApp()
          : DevicePreview(
              enabled: !kReleaseMode,
              builder: (_) => const _RootApp(),
            ),
    ),
  );
}

class _RootApp extends ConsumerWidget {
  const _RootApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/manual',
          builder: (_, __) => const ManualControlScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: ThemeMode.dark,
      theme: ThemeData.dark(useMaterial3: true),
    );
  }
}
