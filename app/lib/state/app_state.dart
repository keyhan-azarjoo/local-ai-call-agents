import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_core/services/knowledge/extract.dart';
import 'package:localailine_core/services/system.dart';
import 'package:localailine_engine/engine.dart';
import 'package:localailine_ui/app_model.dart';
import 'package:localailine_ui/state/call_monitor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

export 'package:localailine_engine/engine.dart';

/// The desktop app's state: the LocalAILine engine in this process, plus the parts that need
/// Flutter (snack bars, dialogs, the theme, quitting the window, listening in on calls).
/// The shared pages see it as an [AppModel].
class AppState extends AppEngine implements AppModel {
  /// [loadAsset] reads the app's bundled files; an app that uses this one as a package passes
  /// `(a) => rootBundle.loadString('packages/localailine/\$a')`.
  AppState({super.dbPath, Future<String> Function(String asset)? loadAsset}) : super(loadAsset: loadAsset ?? rootBundle.loadString, loadPackageAsset: rootBundle.loadString) {
    Db.supportDir = getApplicationSupportDirectory;
    TextExtractor.initPdf = pdfrxFlutterInitialize;
  }

  @override
  final messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  final navigator = GlobalKey<NavigatorState>();

  @override
  ThemeMode get themeMode => darkTheme ? ThemeMode.dark : ThemeMode.light;

  /// Listening in on calls and taking them over, from this computer.
  @override
  late final callMonitor = CallMonitor(this);

  @override
  late final CallRoomsApi callRooms = LocalRooms(() => voice);

  @override
  int get maxLines => AppEngine.maxLines;

  @override
  void toast(String msg) {
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Future<void> openUrl(String url) => openExternal(url);

  @override
  Future<void> openDataFolder() async => openExternal((await Db.dataDir()).path);

  @override
  String tempFile(String name) => p.join(Directory.systemTemp.path, name);

  @override
  bool hasRecording(String? path) => path != null && path.isNotEmpty && File(path).existsSync();

  @override
  Future<void> playRecording(String path) => openExternal(path);

  @override
  bool get canScreenshot => Platform.isMacOS;

  /// macOS: drag over any part of the screen (e.g. a website in your browser).
  @override
  Future<List<int>?> takeScreenshot() async {
    final path = tempFile('localailine-shot-${DateTime.now().millisecondsSinceEpoch}.png');
    await Process.run('screencapture', ['-i', '-x', path]);
    final f = File(path);
    if (!f.existsSync()) return null; // cancelled with Esc
    final bytes = await f.readAsBytes();
    await f.delete();
    return bytes;
  }

  @override
  Future<void> previewVoice(String text, String voice) => speech.speak(text, voicePath: speech.ttsVoicePath(voice));

  @override
  void onExit(Future<void> Function() shutdown) {
    AppLifecycleListener(
      onExitRequested: () async {
        await shutdown();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  Future<bool> approveRemotely(Map<String, dynamic> r) async {
    final ctx = navigator.currentContext;
    if (ctx == null) return false;
    return await showDialog<bool>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: Text('Allow ${r['server']} › ${r['tool']}?'),
            content: Text('Ava wants to run this action:\n${jsonEncode(r['args'])}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Don’t allow')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Allow')),
            ],
          ),
        ) ??
        false;
  }
}
