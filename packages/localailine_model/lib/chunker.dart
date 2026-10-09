import 'knowledge.dart' show Section;

class Chunk {
  Chunk(this.text, {this.heading, this.page});
  final String text;
  final String? heading;
  final int? page;
}

/// Splits documents along their structure: headings start new sections,
/// paragraphs are kept whole where possible, tables are split by rows with
/// nothing cut mid-line. Small overlap keeps context across chunk borders.
class Chunker {
  Chunker({this.target = 900, this.max = 1400, this.overlap = 150});
  final int target, max, overlap;

  static final _heading = RegExp(r'^(#{1,6}\s+.+|[A-Z][A-Z0-9 &/,\-]{3,60}:?|\d+(\.\d+)*\.?\s+[A-Z].{2,80})$');

  List<Chunk> chunk(List<Section> sections) {
    final out = <Chunk>[];
    String? heading;
    for (final s in sections) {
      if (s.table) {
        out.addAll(_rows(s.text, heading, s.page));
        continue;
      }
      final buf = StringBuffer();
      String? bufHeading = heading;
      void flush() {
        final t = buf.toString().trim();
        if (t.isNotEmpty) out.add(Chunk(t, heading: bufHeading, page: s.page));
        buf.clear();
      }

      for (final para in _paragraphs(s.text)) {
        final line = para.trim();
        if (line.isEmpty) continue;
        if (!line.contains('\n') && line.length < 90 && _heading.hasMatch(line) && !RegExp(r'[£\$€]\s?\d').hasMatch(line)) {
          // A heading closes the current chunk once it has some body.
          if (buf.length > target ~/ 3) flush();
          heading = line.replaceFirst(RegExp(r'^#+\s*'), '').replaceAll(RegExp(r':$'), '');
          if (buf.isEmpty) bufHeading = heading;
          continue;
        }
        if (buf.length + line.length > target && buf.isNotEmpty) {
          final tail = _tail(buf.toString());
          flush();
          bufHeading = heading;
          if (tail.isNotEmpty) buf.writeln(tail);
        }
        if (line.length > max) {
          for (final piece in _sentences(line)) {
            if (buf.length + piece.length > max && buf.isNotEmpty) {
              flush();
              bufHeading = heading;
            }
            buf.write('$piece ');
          }
          buf.writeln();
        } else {
          buf.writeln(line);
        }
      }
      flush();
    }
    return out;
  }

  Iterable<Chunk> _rows(String text, String? heading, int? page) sync* {
    final buf = StringBuffer();
    for (final row in text.split('\n')) {
      if (row.trim().isEmpty) continue;
      if (buf.length + row.length > target && buf.isNotEmpty) {
        yield Chunk(buf.toString().trim(), heading: heading, page: page);
        buf.clear();
      }
      buf.writeln(row);
    }
    if (buf.isNotEmpty) yield Chunk(buf.toString().trim(), heading: heading, page: page);
  }

  /// Paragraphs: blank lines split; single short lines (lists, headings) stay separate.
  Iterable<String> _paragraphs(String text) sync* {
    for (final block in text.replaceAll('\r', '').split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n');
      final listy = lines.length > 1 && lines.every((l) => l.trim().length < 120);
      if (listy) {
        // Keep list items together but let headings inside break out.
        final cur = <String>[];
        for (final l in lines) {
          if (_heading.hasMatch(l.trim()) && l.trim().length < 90) {
            if (cur.isNotEmpty) yield cur.join('\n');
            cur.clear();
            yield l;
          } else {
            cur.add(l);
          }
        }
        if (cur.isNotEmpty) yield cur.join('\n');
      } else {
        // Keep line breaks: table rows and price lines must stay separate.
        yield lines.join('\n');
      }
    }
  }

  Iterable<String> _sentences(String s) => RegExp(r'[^.!?]+[.!?]*\s*').allMatches(s).map((m) => m.group(0)!.trim());

  String _tail(String s) {
    if (overlap <= 0 || s.length <= overlap) return '';
    final t = s.substring(s.length - overlap);
    final cut = t.indexOf(RegExp(r'[.!?\n]\s'));
    return cut < 0 ? '' : t.substring(cut + 1).trim();
  }
}
