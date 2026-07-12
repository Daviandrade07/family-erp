import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/biometric_gate.dart';
import 'core/config/ai_config.dart';
import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/aurora_background.dart';
import 'features/settings/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  // A1: falha cedo se o build não forneceu as credenciais do Supabase
  // (evita o app subir com placeholders e quebrar o login). Ver BUILD.md.
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // Chave da IA salva no dispositivo (definida pelo usuário em Configurações).
  await AiConfig.load();

  runApp(const ProviderScope(child: FamilyErpApp()));
}

class FamilyErpApp extends ConsumerWidget {
  const FamilyErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider);

    return MaterialApp.router(
      title: 'Kinfin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent: accent),
      darkTheme: AppTheme.dark(accent: accent),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => AuroraBackground(
        child: BiometricGate(child: child ?? const SizedBox.shrink()),
      ),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
