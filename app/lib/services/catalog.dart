import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'hardware.dart';

enum Fit { great, fits, tight, tooLarge }

extension FitX on Fit {
  String get label => switch (this) {
        Fit.great => 'Great fit',
        Fit.fits => 'Fits',
        Fit.tight => 'Tight',
        Fit.tooLarge => 'Too large',
      };
}

class LlmEntry {
  LlmEntry(this.id, this.name, this.sizeGb, this.params, this.note);
  final String id, name, note;
  final double sizeGb, params;

  /// Weights + KV cache (8k context) + runtime overhead.
  double get needGb {
    final kv = params <= 4
        ? .4
        : params <= 8
            ? .8
            : params <= 14
                ? 1.2
                : 2.0;
    return sizeGb + kv + 1.0;
  }

  Fit fitFor(Hardware hw) => fitOf(needGb, hw.modelBudgetGb);
}

Fit fitOf(double need, double budget) {
  if (need <= budget * .6) return Fit.great;
  if (need <= budget) return Fit.fits;
  if (need <= budget * 1.15) return Fit.tight;
  return Fit.tooLarge;
}

class SpeechEntry {
  SpeechEntry(this.id, this.name, this.sizeMb, this.url, this.note);
  final String id, name, url, note;
  final int sizeMb;
}

class Catalog {
  Catalog(this.llm, this.stt, this.tts);
  final List<LlmEntry> llm;
  final List<SpeechEntry> stt, tts;

  static Catalog parse(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    SpeechEntry sp(dynamic e) =>
        SpeechEntry(e['id'], e['name'], (e['sizeMb'] as num).toInt(), e['url'], e['note']);
    return Catalog(
      [
        for (final e in m['llm'])
          LlmEntry(e['id'], e['name'], (e['sizeGb'] as num).toDouble(), (e['params'] as num).toDouble(), e['note'])
      ],
      [for (final e in m['stt']) sp(e)],
      [for (final e in m['tts']) sp(e)],
    );
  }

  static Future<Catalog> load() async => parse(await rootBundle.loadString('assets/catalog/models.json'));

  /// The model we suggest for calls on this machine: the strongest
  /// "great fit" from a short list known to hold a phone conversation well.
  LlmEntry recommend(Hardware hw) {
    const preferred = ['qwen3:8b', 'qwen3:4b', 'qwen3:1.7b', 'qwen2.5:0.5b'];
    for (final id in preferred) {
      final e = llm.firstWhere((m) => m.id == id);
      if (e.fitFor(hw) == Fit.great) return e;
    }
    return llm.first;
  }
}
