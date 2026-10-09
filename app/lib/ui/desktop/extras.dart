import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine_ui/ui/extras.dart';
import 'package:path/path.dart' as p;

import 'companion.dart';
import 'desktop_pages.dart';
import 'devices_section.dart';
import 'engine_pages.dart';
import 'talk_page.dart';
import 'test_runs_section.dart';

/// What the desktop app adds to the shared pages: its local AI engines, voice server, this
/// computer's hardware, talking to Ava here, paired phones and spoken test runs.
UiExtras desktopExtras() => UiExtras(
      pages: {
        PageId.talk: (_) => const TalkPage(),
        PageId.models: (_) => const ModelsPage(),
        PageId.speech: (_) => const SpeechPage(),
        PageId.hardware: (_) => const HardwarePage(),
        PageId.voiceServer: (_) => const VoiceServerPage(),
        PageId.devices: (_) => const DevicesPage(),
      },
      slots: {
        'engine.setup': (_) => const EngineSetupPanel(),
        'calls.tests': (_) => const TestRunsSection(),
        'home.tests': (_) => const TestRunBanner(),
        'lines.phones': (_) => const PhonesSection(),
      },
      companionSetup: (context, onBack) => CompanionSetup(onBack: onBack),
      startWithCompanion: AppEngine.isPhone,
      signInPrefill: (s) async {
        // Development builds only: sign-in details from dev-login.json next to the app's data
        // on this computer ({"username": …, "password": …}) — never kept in the code.
        if (!kDebugMode) return null;
        try {
          final f = File(p.join(p.dirname(s.db.path), 'dev-login.json'));
          if (!f.existsSync()) return null;
          final j = jsonDecode(f.readAsStringSync()) as Map;
          return ('${j['username'] ?? ''}', '${j['password'] ?? ''}');
        } catch (_) {
          return null;
        }
      },
    );
