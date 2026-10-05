import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/db.dart';
import 'catalog.dart';

/// Local hearing (speech-to-text) and voice (text-to-speech).
///
/// Hearing: whisper.cpp `whisper-cli` + a ggml model.
/// Voice: Piper + an .onnx voice, falling back to the OS voice
/// (macOS `say`, Windows SAPI, Linux espeak-ng) so Talk always works.
class Speech {
  Speech._(this.modelsDir);
  final Directory modelsDir;

  static Future<Speech> create() async {
    final d = Directory(p.join((await Db.dataDir()).path, 'models'));
    Directory(p.join(d.path, 'stt')).createSync(recursive: true);
    Directory(p.join(d.path, 'tts')).createSync(recursive: true);
    return Speech._(d);
  }

  static String get _home => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  static Future<String?> which(String name) async {
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [name]);
      if (r.exitCode == 0) return (r.stdout as String).split('\n').first.trim();
    } catch (_) {}
    for (final dir in ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin']) {
      final f = File('$dir/$name');
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  Future<String?> whisperBinary() async => await which('whisper-cli') ?? await which('whisper-cpp');
  Future<String?> piperBinary() => which('piper');

  /// Downloaded or already-present speech models.
  String? sttModelPath(String id) {
    for (final f in [p.join(modelsDir.path, 'stt', id), p.join(_home, '.whisper-models', id)]) {
      if (File(f).existsSync()) return f;
    }
    return null;
  }

  String? ttsVoicePath(String id) {
    final f = p.join(modelsDir.path, 'tts', '$id.onnx');
    return File(f).existsSync() && File('$f.json').existsSync() ? f : null;
  }

  /// Downloads a speech model from its upstream source, reporting 0..1 progress.
  Stream<double> download(SpeechEntry e, {required bool tts}) async* {
    final dest = tts ? p.join(modelsDir.path, 'tts', '${e.id}.onnx') : p.join(modelsDir.path, 'stt', e.id);
    final files = tts ? [(e.url, dest), ('${e.url}.json', '$dest.json')] : [(e.url, dest)];
    final client = http.Client();
    try {
      for (final (url, path) in files) {
        final res = await client.send(http.Request('GET', Uri.parse(url)));
        if (res.statusCode != 200) throw HttpException('Download failed (${res.statusCode}) for ${e.name}');
        final total = res.contentLength ?? e.sizeMb * 1024 * 1024;
        final tmp = File('$path.part');
        final sink = tmp.openWrite();
        var got = 0;
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          if (path == dest) yield (got / total).clamp(0, 1).toDouble();
        }
        await sink.close();
        await tmp.rename(path);
      }
      yield 1;
    } finally {
      client.close();
    }
  }

  /// Turns a 16 kHz mono WAV into text.
  Future<String> transcribe(String wavPath, {required String modelPath, String language = 'auto'}) async {
    final bin = await whisperBinary();
    if (bin == null) throw SpeechError('Hearing engine (whisper.cpp) is not installed.');
    final r = await Process.run(bin, ['-m', modelPath, '-f', wavPath, '-nt', '-np', '-l', language]);
    if (r.exitCode != 0) throw SpeechError('Could not transcribe: ${(r.stderr as String).trim().split('\n').last}');
    return (r.stdout as String).replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
  }

  Process? _player;

  /// Speaks [text] out loud with the chosen voice, or the OS voice as fallback.
  Future<void> speak(String text, {String? voicePath}) async {
    await stop();
    final clean = text.replaceAll(RegExp(r'[*_#`]'), '').trim();
    if (clean.isEmpty) return;
    final piper = await piperBinary();
    if (piper != null && voicePath != null) {
      final out = p.join(Directory.systemTemp.path, 'll_tts_${DateTime.now().microsecondsSinceEpoch}.wav');
      final proc = await Process.start(piper, ['-m', voicePath, '-f', out]);
      proc.stdin.writeln(clean);
      await proc.stdin.close();
      if (await proc.exitCode == 0 && File(out).existsSync()) {
        await _play(out);
        return;
      }
    }
    await _osSpeak(clean);
  }

  Future<void> _play(String wav) async {
    if (Platform.isMacOS) {
      _player = await Process.start('afplay', [wav]);
    } else if (Platform.isLinux) {
      _player = await Process.start('aplay', ['-q', wav]);
    } else if (Platform.isWindows) {
      _player = await Process.start(
          'powershell', ['-NoProfile', '-Command', "(New-Object Media.SoundPlayer '$wav').PlaySync()"]);
    }
    await _player?.exitCode;
    _player = null;
  }

  Future<void> _osSpeak(String text) async {
    if (Platform.isMacOS) {
      _player = await Process.start('say', [text]);
    } else if (Platform.isWindows) {
      final safe = text.replaceAll("'", "''");
      _player = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('$safe')"
      ]);
    } else {
      _player = await Process.start('espeak-ng', [text]);
    }
    await _player?.exitCode;
    _player = null;
  }

  Future<void> stop() async {
    _player?.kill();
    _player = null;
  }
}

class SpeechError implements Exception {
  SpeechError(this.message);
  final String message;
  @override
  String toString() => message;
}
