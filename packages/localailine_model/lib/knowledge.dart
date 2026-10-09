
/// A piece of a document before chunking: text plus where it came from.
class Section {
  Section(this.text, {this.page, this.table = false});
  final String text;
  final int? page;

  /// Rows of a table/sheet (each line "header: value; …"); chunked by rows.
  final bool table;
}

class IndexProgress {
  IndexProgress(this.done, this.total, this.current);
  final int done, total;
  final String current;
}

class KnowledgeHit {
  KnowledgeHit(this.chunkId, this.sourceId, this.file, this.heading, this.page, this.text, this.score, {this.keyword = false});

  /// Also matched by exact words (not only by meaning).
  final bool keyword;
  final int chunkId, sourceId;
  final String file;
  final String? heading;
  final int? page;
  final String text;
  final double score;

  String get where => [file.split(RegExp(r'[\\/]')).last, if (page != null) 'p.$page', ?heading].join(' · ');
}
