import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'presentation/screens.dart';
import 'presentation/registration_screen.dart';

import 'presentation/scanner_screen.dart';
import 'presentation/state.dart';
import 'presentation/luganda_material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: MuzzlidApp()));
}

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const FieldScreen()),
    GoRoute(
        path: '/register-animal',
        builder: (context, state) => const RegistrationScreen()),
    GoRoute(
        path: '/verify',
        builder: (context, state) => const ScannerScreen(registration: false)),
  ],
);

class MuzzlidApp extends ConsumerWidget {
  const MuzzlidApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'MuzzIID',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        locale: Locale(ref.watch(languageProvider)),
        supportedLocales: const [Locale('en'), Locale('lg')],
        localizationsDelegates: const [
          LugandaMaterialDelegate(),
          LugandaWidgetsDelegate(),
          LugandaCupertinoFallback(),
          ...GlobalMaterialLocalizations.delegates
        ],
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff6f7f2),
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff245c40), contrastLevel: 0),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          ),
        ),
      );
}
