import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/tokens.dart';
import 'ui/auth_pages.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState()..init();
  runApp(ChangeNotifierProvider.value(value: state, child: const LocalAILineApp()));
}

class LocalAILineApp extends StatelessWidget {
  const LocalAILineApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'LocalAILine',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: s.messenger,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: s.themeMode,
      home: switch (s.gate) {
        Gate.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        Gate.setup => const SetupWizard(),
        Gate.signIn => const SignInPage(),
        Gate.app => const Shell(),
      },
    );
  }
}
