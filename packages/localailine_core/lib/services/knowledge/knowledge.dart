import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:localailine_core/notifier.dart';
import 'package:localailine_model/api.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../data/db.dart';
import '../openai_compat.dart' show OpenAiServer;
import 'chunker.dart';
import 'extract.dart';
import 'package:localailine_model/knowledge.dart';
export 'package:localailine_model/knowledge.dart' show IndexProgress;
export 'package:localailine_model/knowledge.dart' show KnowledgeHit;

/// Local document search: files → chunks → embeddings (Ollama) + full-text
/// index (SQLite FTS5) → hybrid search held in memory for speed.
/// Watches folders and re-indexes only what changed.
class KnowledgeService extends Notifier implements KnowledgeApi {
  KnowledgeService(this.db, {this.ollama = 'http://127.0.0.1:11434', http.Client? client}) : _c = client ?? http.Client();
  final Db db;
  final String ollama;

  /// Where embeddings are made: a small Ollama of their own (see [startEmbedServer]) when it runs,
  /// so searching never waits behind the phone calls' answers (the shared one could wedge: the
  /// embedding model waited for memory the busy chat model never gave up).
  String? embedBase;
  String get _embedUrl => embedBase ?? ollama;

  /// Embeddings from an OpenAI-compatible server instead of Ollama.
  /// [remoteEmbedModel] is asked for [embedDimensions] values, the same as the local model gives.
  OpenAiServer? remoteEmbed;
  String remoteEmbedModel = 'text-embedding-3-small';
  static const embedDimensions = 768;
  Process? _embedServer;
  static const embedPort = 11435;

  /// Starts that Ollama (same models folder, one model, one request at a time) and uses it.
  Future<void> startEmbedServer(String? ollamaBinary) async {
    _embedBinary = ollamaBinary;
    _killRunners(); // model processes orphaned by an earlier run
    final url = 'http://127.0.0.1:$embedPort';
    Future<bool> up() async {
      try {
        return (await _c.get(Uri.parse('$url/api/version')).timeout(const Duration(seconds: 2))).statusCode == 200;
      } catch (_) {
        return false;
      }
    }

    if (!await up()) {
      if (ollamaBinary == null) return;
      _embedServer?.kill();
      _embedServer = await Process.start(ollamaBinary, ['serve'], environment: {
        'OLLAMA_HOST': '127.0.0.1:$embedPort',
        'OLLAMA_NUM_PARALLEL': '1',
        'OLLAMA_MAX_LOADED_MODELS': '1',
        'OLLAMA_KEEP_ALIVE': '60m',
      });
      _embedServer!.stdout.drain<void>();
      _embedServer!.stderr.drain<void>();
      for (var i = 0; i < 20 && !await up(); i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (await up()) embedBase = url;
  }

  /// Stuck anyway: start it again (it serves nothing else, so no call notices).
  Future<void> _restartEmbedServer() async {
    if (_embedServer == null) return;
    // Slow under load is not stuck: only start again when it no longer answers at all.
    try {
      final v = await _c.get(Uri.parse('http://127.0.0.1:$embedPort/api/version')).timeout(const Duration(seconds: 3));
      if (v.statusCode == 200 && ++_embedFails < 3) return;
    } catch (_) {}
    _embedFails = 0;
    _killRunners(_embedServer!.pid);
    _embedServer!.kill();
    _embedServer = null;
    embedBase = null;
    await startEmbedServer(_embedBinary);
  }

  String? _embedBinary;
  var _embedFails = 0;

  /// The model processes an Ollama server started: stopped with it (else each stays, ~0.6 GB, and
  /// a night of restarts filled the memory). Also any left without their server by an earlier run.
  static void _killRunners([int? serverPid]) {
    if (Platform.isWindows) return;
    try {
      final ps = Process.runSync('ps', ['-axo', 'pid,ppid,command']).stdout.toString();
      for (final l in const LineSplitter().convert(ps)) {
        final m = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$').firstMatch(l);
        if (m == null || !m.group(3)!.contains('llama-server')) continue;
        final ppid = int.parse(m.group(2)!);
        if (ppid == 1 || ppid == serverPid) Process.killPid(int.parse(m.group(1)!));
      }
    } catch (_) {}
  }

  void stopEmbedServer() {
    if (_embedServer != null) _killRunners(_embedServer!.pid);
    _embedServer?.kill();
    _embedServer = null;
  }
  final http.Client _c;

  /// Small, fast, multilingual embedding model.
  static const embedModel = 'embeddinggemma';
  static const maxFileBytes = 60 * 1024 * 1024;

  final progress = <int, IndexProgress>{};
  final _watchers = <int, StreamSubscription>{};
  final _queue = <int>{};
  bool _running = false;
  Timer? _rescan;
  String? embedError;

  // In-memory vector index: chunk ids and their normalised vectors.
  List<int> _ids = [];
  List<int> _sources = [];
  Float32List _vecs = Float32List(0);
  int _dim = 0;
  bool _loaded = false;

  // ---------------- lifecycle ----------------

  Future<void> start() async {
    await _loadIndex();
    for (final s in await db.all('knowledge', orderBy: 'id')) {
      _watch(s);
      enqueue(s['id'] as int); // quick check: only changed files are re-read
    }
    _rescan = Timer.periodic(const Duration(minutes: 5), (_) async {
      for (final s in await db.all('knowledge')) {
        enqueue(s['id'] as int);
      }
    });
  }

  @override
  void dispose() {
    _rescan?.cancel();
    for (final w in _watchers.values) {
      w.cancel();
    }
    super.dispose();
  }

  /// Folders on this machine can be added (off when the engine runs on a server: uploads only).
  bool foldersAllowed = true;

  @override
  bool get canAddFolders => foldersAllowed;

  @override
  Future<int> addFile({required String name, String? path, required Future<List<int>> Function() bytes, required String scope, String? title}) async {
    if (foldersAllowed && path != null && File(path).existsSync()) return addSource(path, scope: scope, name: title);
    final dir = Directory(p.join(p.dirname(db.path), 'uploads', '${DateTime.now().microsecondsSinceEpoch}'))..createSync(recursive: true);
    final f = File(p.join(dir.path, p.basename(name).replaceAll(RegExp(r'[^\w .()-]'), '_')));
    await f.writeAsBytes(await bytes());
    return addSource(f.path, scope: scope, name: title ?? p.basename(name));
  }

  @override
  Future<String> readText({required String name, String? path, required Future<List<int>> Function() bytes}) async {
    if (foldersAllowed && path != null && File(path).existsSync()) return (await TextExtractor.extract(path)).map((x) => x.text).join('\n\n');
    final dir = await Directory.systemTemp.createTemp('ll-read-');
    try {
      final f = File(p.join(dir.path, p.basename(name).replaceAll(RegExp(r'[^\w .()-]'), '_')));
      await f.writeAsBytes(await bytes());
      return (await TextExtractor.extract(f.path)).map((x) => x.text).join('\n\n');
    } finally {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<int> addSource(String path, {required String scope, String? name}) async {
    final isDir = Directory(path).existsSync();
    final id = await db.insert('knowledge', {
      'name': name ?? p.basename(path),
      'path': path,
      'scope': scope,
      'status': 'waiting',
      'kind': isDir ? 'folder' : 'file',
    });
    final row = (await db.all('knowledge', where: 'id = ?', args: [id])).first;
    _watch(row);
    enqueue(id);
    notifyListeners();
    return id;
  }

  Future<void> removeSource(int id) async {
    await _watchers.remove(id)?.cancel();
    await db.raw.transaction((tx) async {
      await tx.rawDelete('DELETE FROM kn_fts WHERE rowid IN (SELECT id FROM kn_chunks WHERE source_id = ?)', [id]);
      await tx.delete('kn_chunks', where: 'source_id = ?', whereArgs: [id]);
      await tx.delete('kn_files', where: 'source_id = ?', whereArgs: [id]);
      await tx.delete('knowledge', where: 'id = ?', whereArgs: [id]);
    });
    _dropFromIndex((s) => s == id);
    notifyListeners();
  }

  Future<void> reindex(int id) async {
    await db.raw.rawUpdate('UPDATE kn_files SET mtime = -1 WHERE source_id = ?', [id]);
    enqueue(id);
  }

  void _watch(Map<String, Object?> s) {
    final id = s['id'] as int;
    final path = s['path'] as String;
    final target = s['kind'] == 'folder' ? Directory(path) : File(path).parent;
    if (!target.existsSync()) return;
    Timer? debounce;
    try {
      _watchers[id] = target.watch(recursive: s['kind'] == 'folder').listen((e) {
        if (s['kind'] != 'folder' && p.normalize(e.path) != p.normalize(path)) return;
        if (p.basename(e.path).startsWith('.')) return;
        debounce?.cancel();
        debounce = Timer(const Duration(seconds: 2), () => enqueue(id));
      });
    } catch (_) {
      // Watching isn't available everywhere (e.g. some network drives); the 5-minute rescan covers it.
    }
  }

  void enqueue(int sourceId) {
    _queue.add(sourceId);
    if (!_running) _drain();
  }

  Future<void> _drain() async {
    _running = true;
    while (_queue.isNotEmpty) {
      final id = _queue.first;
      _queue.remove(id);
      try {
        await _index(id);
      } catch (e) {
        await db.update('knowledge', id, {'status': 'error', 'error': '$e'});
      }
      progress.remove(id);
      notifyListeners();
    }
    await _backfill();
    _running = false;
  }

  /// Chunks saved while the embedding model was missing get vectors later.
  Future<void> _backfill() async {
    while (true) {
      final rows = await db.raw.rawQuery(
          'SELECT c.id, c.text, c.heading, f.path FROM kn_chunks c JOIN kn_files f ON f.id = c.file_id WHERE c.vec IS NULL LIMIT 128');
      if (rows.isEmpty) return;
      List<Float32List> v;
      try {
        v = await _embed([
          for (final r in rows)
            'title: ${p.basenameWithoutExtension(r['path'] as String)}${r['heading'] == null ? '' : ' — ${r['heading']}'} | text: ${r['text']}'
        ]);
      } catch (e) {
        embedError = '$e';
        return;
      }
      await db.raw.transaction((tx) async {
        for (var i = 0; i < rows.length; i++) {
          await tx.update('kn_chunks', {'vec': v[i].buffer.asUint8List()}, where: 'id = ?', whereArgs: [rows[i]['id']]);
        }
      });
      await _loadIndex(force: true);
    }
  }

  // ---------------- indexing ----------------

  Future<List<File>> _filesOf(Map<String, Object?> s) async {
    final path = s['path'] as String;
    if (s['kind'] != 'folder') return File(path).existsSync() ? [File(path)] : [];
    final dir = Directory(path);
    if (!dir.existsSync()) return [];
    final out = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: path);
      if (p.split(rel).any((part) => part.startsWith('.') || part == 'node_modules')) continue;
      if (TextExtractor.isSupported(e.path)) out.add(e);
    }
    return out;
  }

  Future<void> _index(int sourceId) async {
    final rows = await db.all('knowledge', where: 'id = ?', args: [sourceId]);
    if (rows.isEmpty) return;
    final s = rows.first;
    final files = await _filesOf(s);
    final known = {for (final f in await db.all('kn_files', where: 'source_id = ?', args: [sourceId])) f['path'] as String: f};

    // Files that disappeared.
    final present = files.map((f) => f.path).toSet();
    for (final gone in known.keys.where((k) => !present.contains(k)).toList()) {
      await _deleteFile(known[gone]!['id'] as int);
    }

    final changed = <File>[];
    for (final f in files) {
      final st = f.statSync();
      final k = known[f.path];
      if (k == null || k['size'] != st.size || k['mtime'] != st.modified.millisecondsSinceEpoch) changed.add(f);
    }
    if (changed.isEmpty) {
      await _finish(sourceId);
      return;
    }
    await db.update('knowledge', sourceId, {'status': 'indexing', 'error': null});
    var done = 0;
    for (final f in changed) {
      progress[sourceId] = IndexProgress(done, changed.length, p.basename(f.path));
      notifyListeners();
      await _indexFile(sourceId, f, known[f.path]?['id'] as int?);
      done++;
    }
    await _finish(sourceId);
  }

  Future<void> _finish(int sourceId) async {
    final files = await db.count('kn_files', where: 'source_id = ?', args: [sourceId]);
    final chunks = await db.count('kn_chunks', where: 'source_id = ?', args: [sourceId]);
    final errs = await db.all('kn_files', where: 'source_id = ? AND error IS NOT NULL', args: [sourceId]);
    await db.update('knowledge', sourceId, {
      'status': files == 0 ? 'empty' : 'ready',
      'files': files,
      'chunks': chunks,
      'indexed_at': DateTime.now().millisecondsSinceEpoch,
      'error': errs.isEmpty ? null : '${errs.length} file(s) could not be read, e.g. ${p.basename(errs.first['path'] as String)}: ${errs.first['error']}',
    });
  }

  Future<void> _deleteFile(int fileId) async {
    await db.raw.transaction((tx) async {
      await tx.rawDelete('DELETE FROM kn_fts WHERE rowid IN (SELECT id FROM kn_chunks WHERE file_id = ?)', [fileId]);
      await tx.delete('kn_chunks', where: 'file_id = ?', whereArgs: [fileId]);
      await tx.delete('kn_files', where: 'id = ?', whereArgs: [fileId]);
    });
    await _loadIndex(force: true);
  }

  Future<void> _indexFile(int sourceId, File f, int? oldFileId) async {
    final st = f.statSync();
    List<Chunk> chunks = [];
    String? error;
    if (st.size > maxFileBytes) {
      error = 'larger than 60 MB';
    } else {
      try {
        // Data snapshots from tools: small chunks (about one record each) so a search returns exact rows.
        final isData = f.path.contains('${Platform.pathSeparator}mcp${Platform.pathSeparator}');
        final sections = await TextExtractor.extract(f.path);
        chunks = isData
            ? Chunker(target: 300, max: 700, overlap: 0).chunk([for (final x in sections) Section(x.text, page: x.page, table: true)])
            : Chunker().chunk(sections);
      } catch (e) {
        error = '$e';
      }
    }
    final title = p.basenameWithoutExtension(f.path);
    List<Float32List?> vecs = List.filled(chunks.length, null);
    if (chunks.isNotEmpty) {
      try {
        vecs = await _embed([for (final c in chunks) 'title: $title${c.heading == null ? '' : ' — ${c.heading}'} | text: ${c.text}']);
        embedError = null;
      } catch (e) {
        embedError = '$e'; // keyword search still works without vectors
      }
    }
    await db.raw.transaction((tx) async {
      if (oldFileId != null) {
        await tx.rawDelete('DELETE FROM kn_fts WHERE rowid IN (SELECT id FROM kn_chunks WHERE file_id = ?)', [oldFileId]);
        await tx.delete('kn_chunks', where: 'file_id = ?', whereArgs: [oldFileId]);
        await tx.delete('kn_files', where: 'id = ?', whereArgs: [oldFileId]);
      }
      final fileId = await tx.insert('kn_files', {
        'source_id': sourceId,
        'path': f.path,
        'size': st.size,
        'mtime': st.modified.millisecondsSinceEpoch,
        'chunks': chunks.length,
        'error': error,
      });
      for (var i = 0; i < chunks.length; i++) {
        final c = chunks[i];
        final id = await tx.insert('kn_chunks', {
          'file_id': fileId,
          'source_id': sourceId,
          'ord': i,
          'heading': c.heading,
          'page': c.page,
          'text': c.text,
          'vec': vecs[i]?.buffer.asUint8List(),
        });
        await tx.rawInsert('INSERT INTO kn_fts(rowid, text, heading) VALUES (?, ?, ?)', [id, c.text, c.heading ?? '']);
      }
    });
    await _loadIndex(force: true);
  }

  // ---------------- embeddings ----------------

  /// Makes sure the embedding model is present (downloads it once).
  Future<bool> ensureModel() async {
    if (remoteEmbed != null) return true;
    try {
      final tags = jsonDecode((await _c.get(Uri.parse('$ollama/api/tags'))).body) as Map;
      if ((tags['models'] as List).any((m) => (m['name'] as String).startsWith(embedModel))) return true;
      final r = await _c.post(Uri.parse('$ollama/api/pull'), body: jsonEncode({'model': embedModel, 'stream': false}));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The embedding model didn't answer: don't wait on it again for a minute.
  DateTime? _embedDownUntil;

  Future<List<Float32List>> _embed(List<String> texts) async {
    if (_embedDownUntil != null && DateTime.now().isBefore(_embedDownUntil!)) throw Exception('The embedding model is not answering.');
    try {
      return await _embedNow(texts);
    } on TimeoutException {
      _embedDownUntil = DateTime.now().add(const Duration(minutes: 1));
      unawaited(_restartEmbedServer());
      rethrow;
    }
  }

  Future<List<Float32List>> _embedNow(List<String> texts) async {
    if (remoteEmbed != null) return _embedRemote(texts);
    final out = <Float32List>[];
    for (var i = 0; i < texts.length; i += 32) {
      final batch = texts.sublist(i, math.min(i + 32, texts.length));
      // A stuck embedding model must never hold up a call: give up and answer without it.
      final limit = Duration(seconds: 12 + batch.length ~/ 2);
      var r = await _c.post(Uri.parse('$_embedUrl/api/embed'),
          body: jsonEncode({'model': embedModel, 'input': batch, 'keep_alive': '30m', 'truncate': true})).timeout(limit);
      if (r.statusCode == 404 && await ensureModel()) {
        r = await _c.post(Uri.parse('$_embedUrl/api/embed'), body: jsonEncode({'model': embedModel, 'input': batch, 'keep_alive': '30m', 'truncate': true})).timeout(limit);
      }
      if (r.statusCode != 200) throw Exception('Embedding failed (${r.statusCode}): ${r.body}');
      for (final v in (jsonDecode(r.body) as Map)['embeddings'] as List) {
        out.add(_normalise(Float32List.fromList([for (final x in v as List) (x as num).toDouble()])));
      }
    }
    return out;
  }

  Future<List<Float32List>> _embedRemote(List<String> texts) async {
    final srv = remoteEmbed!, out = <Float32List>[];
    for (var i = 0; i < texts.length; i += 96) {
      final batch = texts.sublist(i, math.min(i + 96, texts.length));
      final r = await _c
          .post(Uri.parse('${srv.base}/embeddings'), headers: srv.headers, body: jsonEncode({'model': remoteEmbedModel, 'input': batch, 'dimensions': embedDimensions}))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('Embedding failed (${r.statusCode}): ${r.body}');
      final data = [...((jsonDecode(r.body) as Map)['data'] as List).cast<Map>()]..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
      for (final d in data) {
        out.add(_normalise(Float32List.fromList([for (final x in d['embedding'] as List) (x as num).toDouble()])));
      }
    }
    return out;
  }

  static Float32List _normalise(Float32List v) {
    var n = 0.0;
    for (final x in v) {
      n += x * x;
    }
    n = math.sqrt(n);
    if (n > 0) {
      for (var i = 0; i < v.length; i++) {
        v[i] /= n;
      }
    }
    return v;
  }

  Future<void> _loadIndex({bool force = false}) async {
    if (_loaded && !force) return;
    final rows = await db.raw.rawQuery('SELECT id, source_id, vec FROM kn_chunks WHERE vec IS NOT NULL ORDER BY id');
    if (rows.isEmpty) {
      _ids = [];
      _sources = [];
      _vecs = Float32List(0);
      _loaded = true;
      return;
    }
    final first = (rows.first['vec'] as Uint8List);
    _dim = first.lengthInBytes ~/ 4;
    final vecs = Float32List(_dim * rows.length);
    final ids = <int>[], sources = <int>[];
    var n = 0;
    for (final r in rows) {
      final b = r['vec'] as Uint8List;
      if (b.lengthInBytes != _dim * 4) continue;
      vecs.setRange(n * _dim, (n + 1) * _dim, b.buffer.asFloat32List(b.offsetInBytes, _dim));
      ids.add(r['id'] as int);
      sources.add(r['source_id'] as int);
      n++;
    }
    _ids = ids;
    _sources = sources;
    _vecs = Float32List.sublistView(vecs, 0, n * _dim);
    _loaded = true;
  }

  void _dropFromIndex(bool Function(int source) drop) {
    final keep = [for (var i = 0; i < _ids.length; i++) if (!drop(_sources[i])) i];
    final v = Float32List(keep.length * _dim);
    for (var k = 0; k < keep.length; k++) {
      v.setRange(k * _dim, (k + 1) * _dim, _vecs, keep[k] * _dim);
    }
    _ids = [for (final i in keep) _ids[i]];
    _sources = [for (final i in keep) _sources[i]];
    _vecs = v;
  }

  // ---------------- tools by meaning ----------------

  final _toolVecs = <String, Float32List>{};
  Float32List? _lastQueryVec;
  String? _lastQuery;

  /// Query vector, cached so documents and tools share one embedding call.
  Future<Float32List?> queryVector(String q) async {
    if (q == _lastQuery && _lastQueryVec != null) return _lastQueryVec;
    try {
      final v = (await _embed(['task: search result | query: $q'])).first;
      _lastQuery = q;
      _lastQueryVec = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Embeds tool descriptions once (cached by text), so a question can find
  /// the right tool even with typos or different words ("staff" → list_users).
  bool _toolVecsLoaded = false;

  Future<void> indexTools(Map<String, String> toolTexts) async {
    if (!_toolVecsLoaded) {
      // Saved from earlier runs: no re-embedding after a restart.
      for (final r in await db.raw.rawQuery('SELECT text, vec FROM tool_vecs')) {
        final b = r['vec'] as Uint8List;
        _toolVecs[r['text'] as String] = Float32List.fromList(b.buffer.asFloat32List(b.offsetInBytes, b.lengthInBytes ~/ 4));
      }
      _toolVecsLoaded = true;
    }
    final missing = toolTexts.entries.where((e) => !_toolVecs.containsKey(e.value)).toList();
    if (missing.isEmpty) return;
    try {
      final v = await _embed([for (final e in missing) 'title: ${e.key} | text: ${e.value}']);
      await db.raw.transaction((tx) async {
        for (var i = 0; i < missing.length; i++) {
          _toolVecs[missing[i].value] = v[i];
          await tx.rawInsert('INSERT OR REPLACE INTO tool_vecs(text, vec) VALUES (?, ?)', [missing[i].value, v[i].buffer.asUint8List()]);
        }
      });
    } catch (_) {}
  }

  /// Returns tool keys ordered by meaning, best first.
  /// Tools that clearly match: at least [minScore] and close to the best match.
  Future<List<String>> rankTools(String query, Map<String, String> toolTexts, {int k = 6, double minScore = 0.30, double window = 0.08}) async {
    final all = await rankToolsScored(query, toolTexts, k: k);
    if (all.isEmpty) return [];
    final best = all.first.$2;
    return [for (final e in all) if (e.$2 >= minScore && e.$2 >= best - window) e.$1];
  }

  Future<List<(String, double)>> rankToolsScored(String query, Map<String, String> toolTexts, {int k = 6}) async {
    await indexTools(toolTexts);
    final q = await queryVector(query);
    if (q == null) return [];
    final scored = <(String, double)>[];
    for (final e in toolTexts.entries) {
      final v = _toolVecs[e.value];
      if (v == null || v.length != q.length) continue;
      var dot = 0.0;
      for (var i = 0; i < v.length; i++) {
        dot += v[i] * q[i];
      }
      scored.add((e.key, dot));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(k).toList();
  }

  // ---------------- prices ----------------

  /// Every line with a price in the given sources, de-duplicated, as written
  /// in the document. Used to quote orders exactly.
  Future<List<String>> priceLines(Set<int> sources) async {
    if (sources.isEmpty) return [];
    final rows = await db.raw.rawQuery(
        "SELECT text FROM kn_chunks WHERE source_id IN (${sources.join(',')}) AND (text LIKE '%£%' OR text LIKE '%\$%' OR text LIKE '%€%') ORDER BY file_id, ord");
    final out = <String>[];
    final seen = <String>{};
    for (final r in rows) {
      for (var l in (r['text'] as String).split('\n')) {
        l = l.replaceAll('|', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (l.length < 4 || l.length > 220 || !RegExp(r'[£\$€]\s?\d').hasMatch(l)) continue;
        if (seen.add(l.toLowerCase())) out.add(l);
      }
    }
    return out.take(200).toList();
  }

  // ---------------- search ----------------

  int get chunkCount => _ids.length;

  /// Hybrid search: meaning (vectors) + exact words (FTS5), fused by rank.
  Future<({List<KnowledgeHit> hits, int ms})> search(String query, {Set<int>? sources, int k = 5}) async {
    final sw = Stopwatch()..start();
    await _loadIndex();
    final q = query.trim();
    if (q.isEmpty) return (hits: <KnowledgeHit>[], ms: 0);
    final allowed = sources;

    // Vector side.
    final vecRank = <int, int>{};
    final vecScore = <int, double>{};
    if (_ids.isNotEmpty) {
      try {
        final qv = await queryVector(q);
        if (qv != null && qv.length == _dim) {
          final scores = <(int, double)>[];
          for (var i = 0; i < _ids.length; i++) {
            if (allowed != null && !allowed.contains(_sources[i])) continue;
            var dot = 0.0;
            final o = i * _dim;
            for (var d = 0; d < _dim; d++) {
              dot += _vecs[o + d] * qv[d];
            }
            scores.add((_ids[i], dot));
          }
          scores.sort((a, b) => b.$2.compareTo(a.$2));
          for (var r = 0; r < math.min(30, scores.length); r++) {
            vecRank[scores[r].$1] = r;
            vecScore[scores[r].$1] = scores[r].$2;
          }
        }
      } catch (_) {}
    }

    // Keyword side.
    const stop = {
      'the', 'and', 'for', 'are', 'you', 'who', 'what', 'which', 'how', 'is', 'was', 'were', 'do', 'does', 'did', 'can', 'could',
      'me', 'my', 'we', 'our', 'your', 'a', 'an', 'of', 'to', 'in', 'on', 'at', 'it', 'its', 'be', 'there', 'this', 'that', 'with',
      'give', 'tell', 'show', 'please', 'have', 'has', 'any', 'all', 'about', 'from', 'many', 'much', 'list', 'role', 'name',
    };
    final words = RegExp(r'[\p{L}\p{N}]{2,}', unicode: true)
        .allMatches(q.toLowerCase())
        .map((m) => m.group(0)!)
        .where((w) => !stop.contains(w))
        .map((w) => '"$w"')
        .toList();
    final ftsRank = <int, int>{};
    if (words.isNotEmpty) {
      final where = allowed == null ? '' : ' AND c.source_id IN (${allowed.isEmpty ? '-1' : allowed.join(',')})';
      try {
        final rows = await db.raw.rawQuery(
            'SELECT kn_fts.rowid AS id FROM kn_fts JOIN kn_chunks c ON c.id = kn_fts.rowid WHERE kn_fts MATCH ?$where ORDER BY bm25(kn_fts) LIMIT 30',
            [words.join(' OR ')]);
        for (var r = 0; r < rows.length; r++) {
          ftsRank[rows[r]['id'] as int] = r;
        }
      } catch (_) {}
    }

    // Reciprocal rank fusion.
    final fused = <int, double>{};
    for (final e in vecRank.entries) {
      fused[e.key] = (fused[e.key] ?? 0) + 1 / (60 + e.value);
    }
    for (final e in ftsRank.entries) {
      fused[e.key] = (fused[e.key] ?? 0) + 1 / (60 + e.value);
    }
    final top = fused.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final ids = top.take(k).map((e) => e.key).toList();
    if (ids.isEmpty) return (hits: <KnowledgeHit>[], ms: sw.elapsedMilliseconds);
    final rows = await db.raw.rawQuery(
        'SELECT c.id, c.source_id, c.heading, c.page, c.text, f.path FROM kn_chunks c JOIN kn_files f ON f.id = c.file_id WHERE c.id IN (${ids.join(',')})');
    final byId = {for (final r in rows) r['id'] as int: r};
    final hits = [
      for (final id in ids)
        if (byId[id] != null)
          KnowledgeHit(id, byId[id]!['source_id'] as int, byId[id]!['path'] as String, byId[id]!['heading'] as String?,
              byId[id]!['page'] as int?, byId[id]!['text'] as String, vecScore[id] ?? 0, keyword: ftsRank.containsKey(id)),
    ];
    return (hits: hits, ms: sw.elapsedMilliseconds);
  }
}
