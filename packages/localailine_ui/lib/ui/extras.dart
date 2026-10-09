import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_model.dart';

/// What an edition adds to the shared pages. The desktop app adds its local AI engines, voice
/// server, paired phones and test runs; another edition can add its own.
/// Provide one above the app with `Provider<UiExtras>.value(...)`.
class UiExtras {
  const UiExtras({
    this.pages = const {},
    this.slots = const {},
    this.companionSetup,
    this.startWithCompanion = false,
    this.signInPrefill,
    this.appName = 'LocalAILine',
    this.brand,
  });

  /// The app's name in texts on the shared pages.
  final String appName;

  /// The app's logo and name, top left and on the sign-in pages (null: LocalAILine's).
  final WidgetBuilder? brand;

  /// Pages the edition provides (shown in the menu only when there's a builder for them).
  final Map<PageId, WidgetBuilder> pages;

  /// Named places inside shared pages, e.g. `engine.setup` (setting up the AI) or `calls.tests`.
  final Map<String, WidgetBuilder> slots;

  /// Connecting this device to a LocalAILine computer instead of setting it up (paired phones).
  final Widget Function(BuildContext context, VoidCallback onBack)? companionSetup;
  final bool startWithCompanion;

  /// Development builds: a username and password to fill in on the sign-in page.
  final Future<(String, String)?> Function(AppModel s)? signInPrefill;
}

/// The app's name, for texts on the shared pages.
String appNameOf(BuildContext context) => context.read<UiExtras?>()?.appName ?? 'LocalAILine';

/// One of the edition's named places (see [UiExtras.slots]); nothing when it has none.
class Slot extends StatelessWidget {
  const Slot(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) {
    final b = context.read<UiExtras?>()?.slots[name];
    return b == null ? const SizedBox.shrink() : b(context);
  }
}
