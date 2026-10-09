import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:localailine/state/app_state.dart';
import 'package:localailine_ui/app_model.dart';
import 'package:localailine_ui/theme/tokens.dart';
import 'package:localailine_ui/ui/auth_pages.dart';
import 'package:localailine_ui/ui/extras.dart';
import 'package:localailine_ui/ui/shell.dart';

import 'ui/desktop/companion.dart';
import 'ui/desktop/extras.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState()..init();
  runApp(withState(state, const LocalAILineApp()));
}

/// The app's state for the pages: as the desktop's own [AppState], as the shared [AppModel], and
/// the desktop's extra pages.
Widget withState(AppState state, Widget child) => MultiProvider(
      providers: [
        ListenableProvider<AppState>.value(value: state),
        ListenableProvider<AppModel>.value(value: state),
        Provider<UiExtras>.value(value: desktopExtras()),
      ],
      child: child,
    );

class LocalAILineApp extends StatelessWidget {
  const LocalAILineApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'LocalAILine',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: s.messenger,
      navigatorKey: s.navigator,
      builder: (context, child) => RingOverlay(child: child ?? const SizedBox()),
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: s.themeMode,
      home: switch (s.gate) {
        Gate.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        Gate.setup => const SetupWizard(),
        Gate.signIn => const SignInPage(),
        Gate.app => const Shell(),
        Gate.companion => const CompanionShell(),
      },
    );
  }
}
