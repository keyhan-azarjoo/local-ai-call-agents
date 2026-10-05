import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// A piece of a document before chunking: text plus where it came from.
class Section {
  Section(this.text, {this.page, this.table = false});
  final String text;
  final int? page;

  /// Rows of a table/sheet (each line "header: value; …"); chunked by rows.
  final bool table;
}

/// Pulls readable text out of the files people actually have.
class TextExtractor {
  static const supported = {'.txt', '.md', '.markdown', '.csv', '.tsv', '.json', '.html', '.htm', '.pdf', '.docx', '.xlsx', '.log', '.xml', '.yaml', '.yml'};

  static bool isSupported(String path) => supported.contains(p.extension(path).toLowerCase());

  static Future<List<Section>> extract(String path) async {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.pdf':
        return _pdf(path);
      case '.docx':
        return [Section(_docx(await File(path).readAsBytes()))];
      case '.xlsx':
        return _xlsx(await File(path).readAsBytes());
      case '.csv':
      case '.tsv':
        return [Section(_table(await _read(path), ext == '.tsv' ? '\t' : ','), table: true)];
      case '.html':
      case '.htm':
        return [Section(_html(await _read(path)))];
      default:
        return [Section(await _read(path))];
    }
  }

  /// Repairs PDF text: "£16. 00" → "£16.00", drops headers/footers that repeat
  /// on most pages and "Page 3" lines.
  static List<Section> cleanPdfPages(List<(int, String)> pages) {
    String norm(String l) => l.trim().replaceAll(RegExp(r'\d+'), '#');
    final seen = <String, int>{};
    for (final (_, text) in pages) {
      for (final l in text.split('\n').map(norm).toSet()) {
        if (l.isNotEmpty) seen[l] = (seen[l] ?? 0) + 1;
      }
    }
    final repeated = pages.length < 3 ? <String>{} : {for (final e in seen.entries) if (e.value >= (pages.length * .6).ceil()) e.key};
    return [
      for (final (n, text) in pages)
        Section(
          text
              .split('\n')
              .where((l) => !repeated.contains(norm(l)) && !RegExp(r'^\s*page\s*\d+(\s*(of|/)\s*\d+)?\s*$', caseSensitive: false).hasMatch(l))
              .join('\n')
              .replaceAllMapped(RegExp(r'(\d)\. (\d)'), (m) => '${m[1]}.${m[2]}'),
          page: n,
        ),
    ];
  }

  static Future<String> _read(String path) async {
    final bytes = await File(path).readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  static bool _pdfReady = false;

  static Future<List<Section>> _pdf(String path) async {
    if (!_pdfReady) {
      Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.path;
      await pdfrxFlutterInitialize();
      _pdfReady = true;
    }
    final doc = await PdfDocument.openFile(path);
    try {
      final pages = <(int, String)>[];
      for (final page in doc.pages) {
        final t = await page.loadStructuredText();
        if (t.fullText.trim().isNotEmpty) pages.add((page.pageNumber, t.fullText));
      }
      return cleanPdfPages(pages);
    } finally {
      await doc.dispose();
    }
  }

  static String _docx(List<int> bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final f = zip.findFile('word/document.xml');
    if (f == null) return '';
    final xml = utf8.decode(f.content as List<int>, allowMalformed: true);
    final out = StringBuffer();
    for (final para in RegExp(r'<w:p[ >][\s\S]*?</w:p>').allMatches(xml)) {
      final x = para.group(0)!;
      final heading = RegExp(r'<w:pStyle w:val="(Heading\d|Title)"').hasMatch(x);
      final text = RegExp(r'<w:t[^>]*>([^<]*)</w:t>').allMatches(x).map((m) => _unescape(m.group(1)!)).join();
      if (text.trim().isEmpty) continue;
      out.writeln(heading ? '# $text' : text);
      out.writeln();
    }
    return out.toString();
  }

  static List<Section> _xlsx(List<int> bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final shared = <String>[];
    final ss = zip.findFile('xl/sharedStrings.xml');
    if (ss != null) {
      final xml = utf8.decode(ss.content as List<int>, allowMalformed: true);
      for (final si in RegExp(r'<si>([\s\S]*?)</si>').allMatches(xml)) {
        shared.add(RegExp(r'<t[^>]*>([^<]*)</t>').allMatches(si.group(1)!).map((m) => _unescape(m.group(1)!)).join());
      }
    }
    final out = <Section>[];
    final sheets = zip.files.where((f) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final s in sheets) {
      final xml = utf8.decode(s.content as List<int>, allowMalformed: true);
      final rows = <List<String>>[];
      for (final r in RegExp(r'<row[^>]*>([\s\S]*?)</row>').allMatches(xml)) {
        final cells = <String>[];
        for (final c in RegExp(r'<c ([^>]*?)(?:/>|>([\s\S]*?)</c>)').allMatches(r.group(1)!)) {
          final attrs = c.group(1)!;
          final v = RegExp(r'<v>([^<]*)</v>').firstMatch(c.group(2) ?? '')?.group(1) ??
              RegExp(r'<t[^>]*>([^<]*)</t>').firstMatch(c.group(2) ?? '')?.group(1) ??
              '';
          cells.add(attrs.contains('t="s"') && int.tryParse(v) != null && int.parse(v) < shared.length ? shared[int.parse(v)] : _unescape(v));
        }
        if (cells.any((x) => x.trim().isNotEmpty)) rows.add(cells);
      }
      if (rows.isNotEmpty) out.add(Section(_rows(rows), table: true));
    }
    return out;
  }

  static String _table(String text, String sep) {
    final rows = <List<String>>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      rows.add(_splitCsv(line, sep));
    }
    return _rows(rows);
  }

  /// Rows as "Header: value; Header: value" so each line stands on its own.
  static String _rows(List<List<String>> rows) {
    if (rows.isEmpty) return '';
    final head = rows.first;
    final looksLikeHeader = head.every((h) => h.trim().isNotEmpty && double.tryParse(h) == null);
    if (!looksLikeHeader) return rows.map((r) => r.join(' | ')).join('\n');
    return rows.skip(1).map((r) {
      final parts = <String>[];
      for (var i = 0; i < r.length; i++) {
        if (r[i].trim().isEmpty) continue;
        parts.add('${i < head.length ? head[i].trim() : 'Column ${i + 1}'}: ${r[i].trim()}');
      }
      return parts.join('; ');
    }).where((l) => l.isNotEmpty).join('\n');
  }

  static List<String> _splitCsv(String line, String sep) {
    final out = <String>[];
    final cur = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          q = !q;
        }
      } else if (ch == sep && !q) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }

  static String _html(String html) {
    var s = html.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ');
    s = s.replaceAllMapped(RegExp(r'<h([1-6])[^>]*>([\s\S]*?)</h\1>', caseSensitive: false), (m) => '\n# ${m.group(2)}\n');
    s = s.replaceAll(RegExp(r'<(br|/p|/div|/li|/tr)[^>]*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _unescape(s).replaceAll(RegExp(r'[ \t]+'), ' ');
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}
