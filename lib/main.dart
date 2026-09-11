import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state.dart';
import 'src/rust/frb_generated.dart';
import 'workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: GitFrontApp()));
}

class GitFrontApp extends ConsumerWidget {
  const GitFrontApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gitFrontProvider);
    final systemLocale = PlatformDispatcher.instance.locale;
    final locale = switch (state.language) {
      AppLanguage.system =>
        systemLocale.languageCode == 'ko'
            ? const Locale('ko')
            : const Locale('en'),
      AppLanguage.korean => const Locale('ko'),
      AppLanguage.english => const Locale('en'),
    };
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff7058e8),
      brightness: Brightness.light,
      surface: const Color(0xfff7f7fb),
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff9f8cff),
      brightness: Brightness.dark,
      surface: const Color(0xff17171d),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GitFront Preview',
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: state.darkMode == null
          ? ThemeMode.system
          : state.darkMode!
          ? ThemeMode.dark
          : ThemeMode.light,
      theme: _theme(lightScheme),
      darkTheme: _theme(darkScheme),
      home: const WorkbenchPage(),
    );
  }

  ThemeData _theme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.55),
      visualDensity: VisualDensity.compact,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: const OutlineInputBorder(),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
