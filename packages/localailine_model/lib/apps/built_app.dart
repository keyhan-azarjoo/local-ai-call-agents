import 'dart:convert';

import 'app_builder.dart' show PictureNotes;
import 'app_spec.dart';

enum AppRun { stopped, running, paused }

/// A user-built app as stored in the `apps` table.
class BuiltApp {
  BuiltApp(this.row);
  final Map<String, Object?> row;
  int get id => row['id'] as int;
  String get name => row['name'] as String;
  String get request => row['request'] as String;
  int get port => row['port'] as int;
  String get pin => row['pin'] as String;
  AppSpec get spec => AppSpec.fromJson((jsonDecode(row['spec'] as String) as Map).cast<String, dynamic>());
  AppRun get savedRun => AppRun.values.firstWhere((r) => r.name == row['status'], orElse: () => AppRun.stopped);
}

enum BuildState { waiting, working, done, simple, skipped, failed }

class BuildStep {
  BuildStep(this.title, this.run);
  final String title;
  final Future<String?> Function() run;
  BuildState state = BuildState.waiting;
  String? note;
}

/// One "create an app" conversation, kept while you move around the app.
class BuildJob {
  String stage = 'describe'; // describe → questions → plan → build → done
  String request = '';
  final pictures = <(String, PictureNotes?)>[]; // base64, what the AI saw
  List<String> questions = [];
  final answers = <String, String>{};
  Features features = const Features();
  bool exampleData = true;
  AppSpec? plan;
  final steps = <BuildStep>[];
  int? appId;
  String? busy; // what the AI is doing now
  String? error;
  bool cancelled = false;
  Future<void> Function()? save;

  /// The website's look (see [siteStyles]); null = suggested from the request.
  String? style;

  /// The business's own name, used for the app and its texts.
  String businessName = '';

  List<PictureNotes> get notes => [for (final p in pictures) ?p.$2];
}

class NoVision implements Exception {
  @override
  String toString() => 'None of your downloaded AI models can read pictures. In LocalAILine, add a picture once to download one (Gemma 3).';
}
