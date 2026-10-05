import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../services/knowledge/chunker.dart';
import '../../services/knowledge/extract.dart' as ex;
import '../../services/knowledge/knowledge.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'admin_pages.dart' show scopes;

const _types = XTypeGroup(label: 'Documents', extensions: ['pdf', 'docx', 'xlsx', 'csv', 'tsv', 'txt', 'md', 'markdown', 'html', 'htm', 'json', 'xml', 'yaml', 'yml', 'log']);

Future<void> addDocuments(BuildContext context, {required bool folder}) async {
  final s = context.read<AppState>();
  final paths = <String>[];
  if (folder) {
    final d = await getDirectoryPath(confirmButtonText: 'Add folder');
    if (d != null) paths.add(d);
  } else {
    paths.addAll((await openFiles(acceptedTypeGroups: [_types], confirmButtonText: 'Add')).map((f) => f.path));
  }
  if (paths.isEmpty || !context.mounted) return;
  final scope = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text('Who can Ava use this for?', style: displayStyle(c, 18)),
      children: [
        for (final e in scopes.entries)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(e.value))),
      ],
    ),
  );
  if (scope == null) return;
  for (final path in paths) {
    await s.knowledge.addSource(path, scope: scope);
    await s.log('Added ${folder ? 'folder' : 'document'} ${p.basename(path)} to Knowledge');
  }
  s.toast(folder ? 'Folder added. Indexing now…' : '${paths.length} document${paths.length == 1 ? '' : 's'} added. Indexing now…');
}

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});
  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  final q = TextEditingController();
  List<KnowledgeHit>? hits;
  int? ms;

  Future<void> _search() async {
    final r = await context.read<AppState>().knowledge.search(q.text, k: 5);
    setState(() {
      hits = r.hits;
      ms = r.ms;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Knowledge',
          description: 'Documents Ava uses to answer. Indexed on this computer and kept up to date when files change.',
          actions: [
            Btn('Add folder', icon: Icons.create_new_folder_outlined, onPressed: () => addDocuments(context, folder: true)),
            Btn('Add files', icon: Icons.upload_file, kind: BtnKind.primary, onPressed: () => addDocuments(context, folder: false)),
          ]),
      if (s.knowledge.embedError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            borderColor: LL.amber,
            child: Muted('Meaning search is unavailable (${s.knowledge.embedError}). Word search still works. Start Ollama to enable it.'),
          ),
        ),
      const KnowledgeList(),
      const SizedBox(height: 16),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Try a question', style: displayStyle(context, 16)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: q, onSubmitted: (_) => _search(), decoration: const InputDecoration(hintText: 'e.g. Do you have gluten-free options?'))),
            const SizedBox(width: 8),
            Btn('Search', icon: Icons.search, kind: BtnKind.primary, onPressed: _search),
          ]),
          if (hits != null) ...[
            const SizedBox(height: 10),
            Muted('${hits!.length} passages in $ms ms', mono: true),
            for (final h in hits!)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: context.c.canvas, borderRadius: BorderRadius.circular(LL.rSm)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Muted(h.where, mono: true, size: 11.5),
                  const SizedBox(height: 4),
                  Text(h.text.length > 400 ? '${h.text.substring(0, 400)}…' : h.text, style: const TextStyle(fontSize: 13)),
                ]),
              ),
          ],
        ]),
      ),
    ]);
  }
}

/// Sources with live indexing status.
class KnowledgeList extends StatelessWidget {
  const KnowledgeList({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return FutureBuilder(
      future: s.db.all('knowledge', orderBy: 'id DESC'),
      builder: (context, snap) {
        final rows = snap.data ?? [];
        return Section(
          title: compact ? 'What Ava knows' : 'Sources',
          trailing: compact
              ? Wrap(spacing: 6, children: [
                  Btn('Folder', icon: Icons.create_new_folder_outlined, small: true, onPressed: () => addDocuments(context, folder: true)),
                  Btn('Files', icon: Icons.upload_file, small: true, kind: BtnKind.primary, onPressed: () => addDocuments(context, folder: false)),
                ])
              : null,
          children: [
            if (rows.isEmpty)
              const EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No documents yet',
                body: 'Add menus, price lists, FAQs or a whole folder. Ava looks things up in them while she talks.',
              ),
            for (final k in rows) _row(context, s, k, last: k == rows.last),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, AppState s, Map<String, Object?> k, {bool last = false}) {
    final id = k['id'] as int;
    final prog = s.knowledge.progress[id];
    final status = k['status'] as String;
    final (label, tone) = prog != null
        ? ('Indexing ${prog.done + 1}/${prog.total}', Tone.amber)
        : switch (status) {
            'ready' => ('${k['files']} file${k['files'] == 1 ? '' : 's'} · ${k['chunks']} passages', Tone.green),
            'error' => ('Problem', Tone.red),
            'empty' => ('No readable files', Tone.neutral),
            _ => ('Waiting', Tone.neutral),
          };
    return Tile(
      last: last,
      leading: LogoBox(child: Icon(k['kind'] == 'folder' ? Icons.folder_outlined : Icons.description_outlined)),
      title: Row(children: [Flexible(child: Text(k['name'] as String)), const SizedBox(width: 8), Pill(label, tone: tone)]),
      subtitle: prog != null
          ? Padding(
              padding: const EdgeInsets.only(top: 6, right: 30),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Meter(prog.total == 0 ? 0 : (prog.done) / prog.total, color: LL.amber),
                const SizedBox(height: 3),
                Muted(prog.current, size: 11.5),
              ]),
            )
          : Muted(
              [
                k['path'] as String,
                scopes[k['scope']] ?? '',
                if (k['indexed_at'] != null) 'updated ${ago(k['indexed_at'] as int)}',
                if (k['error'] != null) '${k['error']}',
              ].join(' · '),
              size: 11.5),
      trailing: compact
          ? null
          : Wrap(spacing: 4, children: [
              IconButton(tooltip: 'Index again', icon: const Icon(Icons.refresh, size: 18), onPressed: () => s.knowledge.reindex(id)),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  await s.knowledge.removeSource(id);
                  await s.db.raw.rawUpdate('UPDATE skills SET source_id = NULL WHERE source_id = ?', [id]);
                  await s.log('Removed ${k['name']} from Knowledge');
                },
              ),
            ]),
    );
  }
}

/// A skill from a document: its "assistant instructions" section becomes
/// how Ava behaves; the whole document becomes searchable knowledge.
Future<void> addSkillFromDocument(BuildContext context) async {
  final s = context.read<AppState>();
  final f = await openFile(acceptedTypeGroups: [_types], confirmButtonText: 'Add skill');
  if (f == null) return;
  try {
    final sections = await ex.TextExtractor.extract(f.path);
    final text = sections.map((x) => x.text).join('\n\n');
    final (name, instructions, summary) = skillFrom(text, p.basenameWithoutExtension(f.path));
    final sourceId = await s.knowledge.addSource(f.path, scope: 'all', name: 'Skill: $name');
    await s.db.insert('skills', {'name': name, 'description': summary, 'instructions': instructions, 'source_id': sourceId, 'enabled': 1});
    await s.log('Added skill $name from ${p.basename(f.path)}');
    s.refresh();
    s.toast('Skill “$name” added. Ava will use it on the next call.');
  } catch (e) {
    s.toast('Couldn’t read that document: $e');
  }
}

/// Finds the skill name (first heading), the instructions section, and a one-line summary.
(String, String, String) skillFrom(String text, String fallbackName) {
  final all = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  // Page headers/footers repeat on every page; skip them (and "Page 3" lines).
  final counts = <String, int>{};
  for (final l in all) {
    final key = l.replaceAll(RegExp(r'\d+'), '#');
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final lines = all
      .where((l) => counts[l.replaceAll(RegExp(r'\d+'), '#')] == 1 && !RegExp(r'\bpage\s*\d+\b', caseSensitive: false).hasMatch(l))
      .toList();
  final name = lines.isEmpty ? fallbackName : lines.first.replaceFirst(RegExp(r'^#+\s*'), '');
  final lower = text.toLowerCase();
  var start = -1;
  for (final marker in ['instructions for the assistant', 'assistant instructions', 'how to act', 'instructions for ai', 'instructions']) {
    start = lower.indexOf(marker);
    if (start >= 0) break;
  }
  String instructions;
  if (start >= 0) {
    final rest = text.substring(start);
    final nl = rest.indexOf('\n');
    final body = rest.substring(nl < 0 ? 0 : nl).trim();
    // Until the next big section heading.
    final end = RegExp(r'\n\s*(#{1,2}\s|\d+\.\s+[A-Z][A-Z ]{4,}\n|[A-Z][A-Z &]{6,}\n)').firstMatch(body);
    instructions = (end == null ? body : body.substring(0, end.start)).trim();
  } else {
    instructions = Chunker().chunk([ex.Section(text)]).take(2).map((c) => c.text).join('\n');
  }
  if (instructions.length > 4000) instructions = instructions.substring(0, 4000);
  final summary = lines.length > 1 ? (lines[1].length > 140 ? '${lines[1].substring(0, 140)}…' : lines[1]) : name;
  return (name, instructions, summary);
}
