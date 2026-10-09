import 'dart:convert';


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
  LlmEntry(this.id, this.name, this.sizeGb, this.params, this.note, {this.think, this.slow = false});
  final String id, name, note;
  final double sizeGb, params;

  /// 'off' = hybrid model, ask Ollama not to think (fast replies).
  /// 'separate' = always thinks; Ollama returns the thinking apart from the reply.
  final String? think;

  /// Too slow to start speaking for phone calls; never auto-picked.
  final bool slow;

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
          LlmEntry(e['id'], e['name'], (e['sizeGb'] as num).toDouble(), (e['params'] as num).toDouble(), e['note'],
              think: e['think'] as String?, slow: e['slow'] == true)
      ],
      [for (final e in m['stt']) sp(e)],
      [for (final e in m['tts']) sp(e)],
    );
  }

  /// [loadAsset] reads a bundled file by its asset path (Flutter's rootBundle, or a file on a server).
  static Future<Catalog> load(Future<String> Function(String asset) loadAsset) async => parse(await loadAsset('assets/catalog/models.json'));

  /// A short list to choose from on this machine, best first:
  /// the recommended model, one smarter option if it still fits,
  /// and lighter/faster options.
  List<(LlmEntry, String)> choices(Hardware hw) {
    final rec = recommend(hw);
    final fitting = llm.where((m) => !m.slow && (m.fitFor(hw) == Fit.great || m.fitFor(hw) == Fit.fits)).toList()
      ..sort((a, b) => b.params.compareTo(a.params));
    final out = <(LlmEntry, String)>[(rec, 'Best for this computer')];
    final smarter = fitting.where((m) => m.params > rec.params).toList();
    if (smarter.isNotEmpty) out.add((smarter.last, 'Smarter, a little slower'));
    final lighter = fitting.where((m) => m.params < rec.params).take(2);
    for (final m in lighter) {
      out.add((m, m.params < 1 ? 'Tiny · for testing' : 'Faster, lighter'));
    }
    return out;
  }

  /// Best already-downloaded model: largest catalog model that fits well.
  String? bestInstalled(Hardware? hw, List<String> installed) {
    if (installed.isEmpty) return null;
    final known = llm.where((m) => installed.contains(m.id) && !m.slow).toList();
    if (hw != null) {
      // The recommended model is chosen for speed on this machine; prefer it.
      final rec = recommend(hw);
      if (known.any((m) => m.id == rec.id)) return rec.id;
      final great = known.where((m) => m.fitFor(hw) == Fit.great).toList()..sort((a, b) => b.params.compareTo(a.params));
      if (great.isNotEmpty) return great.first.id;
      final fits = known.where((m) => m.fitFor(hw) == Fit.fits).toList()..sort((a, b) => a.params.compareTo(b.params));
      if (fits.isNotEmpty) return fits.first.id;
    }
    if (known.isNotEmpty) return known.first.id;
    // Only slow or unknown models downloaded: still better than nothing.
    return installed.first;
  }

  /// The model we suggest for calls on this machine: the strongest
  /// "great fit" from a short list known to hold a phone conversation well.
  LlmEntry recommend(Hardware hw) {
    const preferred = ['qwen3:8b', 'qwen3:4b-instruct', 'qwen3:1.7b', 'qwen2.5:0.5b'];
    for (final id in preferred) {
      final e = llm.firstWhere((m) => m.id == id);
      if (e.fitFor(hw) == Fit.great) return e;
    }
    return llm.first;
  }
}
