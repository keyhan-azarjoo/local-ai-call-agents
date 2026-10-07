import 'dart:convert';

import '../ollama.dart' show ChatMessage;
import 'app_spec.dart';
import 'app_styles.dart';

/// Sends messages to the AI and returns its whole reply. [json]: answer must be JSON.
typedef AskModel = Future<String> Function(List<ChatMessage> messages, {bool json, String? model});

class BuildError implements Exception {
  BuildError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a picture told us: the look to copy and any content (e.g. a photographed menu).
class PictureNotes {
  PictureNotes({this.kind = 'other', this.accent, this.dark = false, this.font = 'sans', this.style = '', this.content = ''});
  final String kind, font, style, content;
  final String? accent;
  final bool dark;

  String get summary => [
        'Picture ($kind)',
        if (style.isNotEmpty) 'look: $style',
        if (accent != null) 'main colour $accent',
        if (dark) 'dark background',
        if (content.isNotEmpty) 'content: $content',
      ].join('; ');

  Map<String, Object?> toJson() => {'kind': kind, 'accent': accent, 'dark': dark, 'font': font, 'style': style, 'content': content};
  static PictureNotes fromJson(Map<String, dynamic> j) => PictureNotes(
      kind: '${j['kind'] ?? 'other'}',
      accent: j['accent'] as String?,
      dark: j['dark'] == true,
      font: '${j['font'] ?? 'sans'}',
      style: '${j['style'] ?? ''}',
      content: '${j['content'] ?? ''}');
}

/// Builds an app with the AI in many small steps, so a small local model only
/// ever has one simple job: plan, then each table, then each page, then example data.
/// Every answer is JSON that is checked (and repaired) before it is used.
class AppBuilder {
  AppBuilder(this.ask);
  final AskModel ask;

  static const _system = 'You help a non-technical person build a simple app for their business. '
      'You answer with one JSON object only: no explanations, no markdown.';

  /// Asks for JSON, checks it, and asks again (up to [tries] times) when it doesn't fit.
  Future<Map<String, dynamic>> askJson(String prompt, {String? Function(Map<String, dynamic>)? check, List<String> images = const [], String? model, int tries = 3}) async {
    final msgs = [ChatMessage('system', _system), ChatMessage('user', prompt, images: images)];
    var problem = '';
    for (var i = 0; i < tries; i++) {
      final reply = await ask(msgs, json: true, model: model);
      final j = parseJson(reply);
      problem = j == null ? 'That was not valid JSON.' : (check?.call(j) ?? '');
      if (problem.isEmpty) return j!;
      msgs
        ..add(ChatMessage('assistant', reply.length > 3000 ? reply.substring(0, 3000) : reply))
        ..add(ChatMessage('user', '$problem Answer again with only the corrected JSON object.'));
    }
    throw BuildError(problem);
  }

  /// The first JSON object in a reply (tolerates code fences, extra words, trailing commas).
  static Map<String, dynamic>? parseJson(String reply) {
    final a = reply.indexOf('{'), b = reply.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    var s = reply.substring(a, b + 1);
    for (var i = 0; i < 2; i++) {
      try {
        final j = jsonDecode(s);
        return j is Map ? j.cast<String, dynamic>() : null;
      } catch (_) {
        s = s.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);
      }
    }
    return null;
  }

  // ---------------- pictures ----------------

  Future<PictureNotes> readPicture(String base64, {required String model}) async {
    final j = await askJson(
      'Look at this picture. The user wants an app/website and shared it to show what they like or what they have.\n'
      'Reply with JSON:\n'
      '{"kind":"website" (a screenshot of a website or app) | "menu" (a menu, price list or product list) | "logo" | "photo" | "other",\n'
      ' "style":"the look in a few words (layout, mood, shapes)",\n'
      ' "accent":"#rrggbb main brand or button colour",\n'
      ' "dark":true if the background is dark,\n'
      ' "font":"sans" | "serif" | "rounded",\n'
      ' "content":"the useful text you can read, e.g. every menu item with its price and description, one per line. Empty if none."}',
      images: [base64],
      model: model,
    );
    final accent = '${j['accent'] ?? ''}'.trim();
    return PictureNotes(
      kind: slug(j['kind'], fallback: 'other'),
      style: '${j['style'] ?? ''}'.trim(),
      accent: RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accent) ? accent : null,
      dark: j['dark'] == true,
      font: const {'serif', 'rounded'}.contains(j['font']) ? j['font'] as String : 'sans',
      content: (j['content'] is List ? (j['content'] as List).join('\n') : '${j['content'] ?? ''}').trim(),
    );
  }

  static String _pictures(List<PictureNotes> pics) => pics.isEmpty ? '' : '\nFrom the user\'s pictures:\n${pics.map((p) => '- ${p.summary}').join('\n')}\n';

  // ---------------- questions ----------------

  Future<List<String>> questions(String request, List<PictureNotes> pics) async {
    final j = await askJson(
      'The user wants this app:\n"$request"\n${_pictures(pics)}\n'
      'Ask up to 4 short, simple questions whose answers you need to build it well '
      '(e.g. what customers should be able to do, what the manager needs to set). '
      'Don\'t ask about technology, colours or hosting. If everything is clear, ask nothing.\n'
      'JSON: {"questions":["...","..."]}',
      check: (j) => j['questions'] is List ? null : 'Use the key "questions" with a list of strings.',
    );
    return [for (final q in j['questions'] as List) '$q'.trim()].where((q) => q.length > 3).take(4).toList();
  }

  // ---------------- plan ----------------

  static const _planFormat = '{"name":"short app name","summary":"one sentence","tagline":"a short, warm slogan for the website",\n'
      ' "tables":[{"id":"snake_case","title":"Title","purpose":"what it stores","kind":"list" or "single","access":"see" | "add" | "see+add" | "none"}],\n'
      ' "pages":[{"id":"snake_case","title":"Title","purpose":"what customers do on this page"}]}';

  static const _planRules = 'Rules:\n'
      '- 2 to 6 tables. kind "single" = only one record (e.g. opening hours, shop details); "list" = many records.\n'
      '- access = what customers (website visitors and phone callers) may do: "see" (e.g. a menu), '
      '"add" (e.g. orders or bookings: they can add one but not see other people\'s), "see+add", or "none" (manager only).\n'
      '- The manager can always see and change every table on a separate manager page: don\'t add pages for the manager.\n'
      '- 1 to 4 pages for customers.\n'
      'Example for a bike repair shop:\n'
      '{"name":"Spoke Repairs","summary":"Customers see services and book a repair.",'
      '"tables":[{"id":"services","title":"Services","purpose":"repairs offered with prices","kind":"list","access":"see"},'
      '{"id":"bookings","title":"Bookings","purpose":"repair bookings from customers","kind":"list","access":"add"},'
      '{"id":"shop_info","title":"Shop info","purpose":"address and opening hours","kind":"single","access":"see"}],'
      '"pages":[{"id":"home","title":"Home","purpose":"welcome, opening hours and services"},{"id":"book","title":"Book a repair","purpose":"choose services and book a time"}]}';

  /// Things customers do that must be saved somewhere (small models often forget the table).
  static final _customerActs = RegExp(r'\b(order|ordering|book|booking|reserve|reservation|appointment|sign up|signup|register|enrol|enroll|request|message|contact|review|apply|application|rsvp|quote|feedback)', caseSensitive: false);

  String? _checkPlan(Map<String, dynamic> j, bool website, String request) {
    if (j['tables'] is! List || (j['tables'] as List).isEmpty) return 'Add a "tables" list with at least one table.';
    if (website && (j['pages'] is! List || (j['pages'] as List).isEmpty)) return 'Add a "pages" list with at least one page.';
    final act = _customerActs.firstMatch(request);
    final spec = AppSpec.fromJson({...j, 'pages': const []});
    if (act != null && !spec.tables.any((t) => t.access.add && !t.single)) {
      return 'Customers ${act[0]!.toLowerCase()}: add a list table with "access":"add" that saves each one (for example "orders" or "bookings").';
    }
    return null;
  }

  Future<AppSpec> plan(String request, Map<String, String> answers, Features features, List<PictureNotes> pics, {String style = 'modern', String name = ''}) async {
    final qa = answers.entries.where((e) => e.value.trim().isNotEmpty).map((e) => 'Q: ${e.key}\nA: ${e.value}').join('\n');
    final j = await askJson(
      'The user wants this app:\n"$request"\n${name.isEmpty ? '' : 'The business is called "$name": use that as the app name.\n'}${qa.isEmpty ? '' : '\nTheir answers:\n$qa\n'}${_pictures(pics)}\n'
      '${features.website ? '' : 'They don\'t want a website: make no pages ("pages":[]).\n'}'
      'Make a small plan. JSON:\n$_planFormat\n$_planRules',
      check: (j) => _checkPlan(j, features.website, '$request\n$qa'),
    );
    final spec = _fromPlan(j, features, pics, style: style);
    return name.isEmpty ? spec : spec.copyWith(name: name);
  }

  /// The plan again, changed the way the user asked.
  Future<AppSpec> changePlan(AppSpec current, String change) async {
    final j = await askJson(
      'This is the current plan of an app:\n${jsonEncode(_planJson(current))}\n\n'
      'The user wants this change: "$change"\n'
      'Return the whole changed plan in the same JSON format:\n$_planFormat\n$_planRules',
      check: (j) => _checkPlan(j, current.features.website, change),
    );
    final next = _fromPlan(j, current.features, const [], style: current.style);
    return next.copyWith(site: {...current.site, if (next.site['tagline'] != null) 'tagline': next.site['tagline']!}, theme: current.theme);
  }

  static Map<String, Object?> _planJson(AppSpec s) => {
        'name': s.name,
        'summary': s.summary,
        'tables': [for (final t in s.tables) {'id': t.id, 'title': t.title, 'purpose': t.purpose, 'kind': t.single ? 'single' : 'list', 'access': t.access.toJson()}],
        'pages': [for (final p in s.pages) {'id': p.id, 'title': p.title, 'purpose': p.purpose}],
      };

  AppSpec _fromPlan(Map<String, dynamic> j, Features features, List<PictureNotes> pics, {String style = 'modern'}) {
    final look = pics.where((p) => p.kind == 'website' || p.kind == 'logo').firstOrNull ?? pics.where((p) => p.accent != null).firstOrNull;
    // A picture of a website decides the style: dark → bold, serif → elegant, rounded → warm.
    final fromPicture = look == null || look.kind != 'website'
        ? null
        : (look.dark ? 'bold' : (look.font == 'serif' ? 'elegant' : (look.font == 'rounded' ? 'warm' : null)));
    return AppSpec.fromJson({
      ...j,
      'features': features.toJson(),
      if (!features.website) 'pages': const [],
      'theme': look?.accent ?? '',
      'site': {'style': fromPicture ?? style, 'tagline': ?(j['tagline'] as Object?)?.toString()},
    });
  }

  // ---------------- tables ----------------

  static const _fieldFormat = '{"fields":[{"id":"snake_case","label":"Label","type":"text","required":true}]}\n'
      'Types: text, longtext, number, money, yesno, date, time, datetime, email, phone, image (a photo),\n'
      ' choice (add "options":["A","B"]),\n'
      ' link (one record of another table: add "link":"table_id"),\n'
      ' links (several records of another table: add "link":"table_id", and "qty":true when each has a quantity, like food in an order).\n'
      'Add "manager_only":true to fields only the manager fills in (e.g. an order status).';

  Future<List<FieldSpec>> tableFields(AppSpec spec, String tableId, List<PictureNotes> pics) async {
    final t = spec.table(tableId)!;
    final others = spec.tables.where((x) => x.id != t.id).map((x) => x.id).join(', ');
    final j = await askJson(
      'App plan:\n${spec.outline()}${_pictures(pics.where((p) => p.content.isNotEmpty).toList())}\n'
      'Now design the fields of the table "${t.id}" (${t.purpose}${t.single ? '; it holds one record' : ''}).\n'
      'JSON:\n$_fieldFormat\n'
      'Rules: 2 to 10 fields. The first field is the name or title of a record. No "id" field. '
      '${others.isEmpty ? '' : 'Other tables you can link to: $others. '}'
      '${t.access.see && !t.single ? 'Customers browse these, so add a "description" (longtext) and a "photo" (image) field. ' : ''}'
      'Only link from a record that uses others (an order links to the food and the table it is for); never link back (food does not link to orders or tables). '
      '${t.access.add ? 'Customers fill this in, so ask them only what is needed. ' : ''}'
      'Example for bookings of a bike shop: {"fields":[{"id":"customer_name","label":"Your name","type":"text","required":true},'
      '{"id":"phone","label":"Phone","type":"phone","required":true},{"id":"services","label":"Services","type":"links","link":"services"},'
      '{"id":"day","label":"Day","type":"date","required":true},{"id":"status","label":"Status","type":"choice","options":["New","Confirmed","Done"],"manager_only":true}]}',
      check: (j) => j['fields'] is List && [for (final f in j['fields'] as List) ?FieldSpec.fromJson(f)].isNotEmpty ? null : 'Give a "fields" list with at least one field that has an "id".',
    );
    return TableSpec.fromJson({'id': t.id, 'fields': j['fields']})!.fields;
  }

  /// The table's fields after the change the user asked for.
  Future<List<FieldSpec>> changeTable(AppSpec spec, String tableId, String change) async {
    final t = spec.table(tableId)!;
    final j = await askJson(
      'App plan:\n${spec.outline()}\n'
      'The table "${t.id}" has these fields:\n${jsonEncode({'fields': [for (final f in t.fields) f.toJson()]})}\n'
      'The user wants this change: "$change"\n'
      'Return all fields of the table after the change (keep the ids of fields that stay). JSON:\n$_fieldFormat',
      check: (j) => j['fields'] is List && (j['fields'] as List).isNotEmpty ? null : 'Give the "fields" list.',
    );
    return TableSpec.fromJson({'id': t.id, 'fields': j['fields']})!.fields;
  }

  // ---------------- pages ----------------

  String _blockFormat(AppSpec spec) {
    final see = spec.tables.where((t) => t.access.see && !t.single).map((t) => t.id).join(', ');
    final single = spec.tables.where((t) => t.access.see && t.single).map((t) => t.id).join(', ');
    final add = spec.tables.where((t) => t.access.add).map((t) => t.id).join(', ');
    final photos = spec.tables.where((t) => t.access.see && !t.single && t.fields.any((f) => f.type == 'image')).map((t) => t.id).join(', ');
    final quotes = spec.tables.where((t) => t.access.see && !t.single && t.fields.any((f) => f.type == 'longtext')).map((t) => t.id).join(', ');
    return '{"blocks":[ ...blocks... ]}\nBlocks you can use:\n'
        '{"type":"hero","title":"A big, inviting headline","text":"One sentence under it","button":"Button text","link":"page id the button opens"}  (a big banner; use it first)\n'
        '{"type":"text","text":"## Heading\\nA short friendly paragraph"}\n'
        '{"type":"features","title":"Why people choose us","text":"Fresh every day: short line\\nFamily run: short line\\nEasy parking: short line"}  (3 to 6 cards with icons, one per line "Title: text")\n'
        '{"type":"contact","title":"Find us"}  (address, phone, email, opening hours and a map link, from the business details)\n'
        '${see.isEmpty ? '' : '{"type":"list","table":"one of: $see","title":"...","search":true}  (cards with a search box; add "layout":"menu" for a printed-menu look with sections and prices)\n'}'
        '${photos.isEmpty ? '' : '{"type":"gallery","table":"one of: $photos","title":"..."}  (a grid of photos)\n'}'
        '${quotes.isEmpty ? '' : '{"type":"testimonials","table":"one of: $quotes","title":"What people say"}  (quotes, only from a table of reviews)\n'}'
        '${single.isEmpty ? '' : '{"type":"info","table":"one of: $single","title":"..."}  (shows the one record)\n'}'
        '${add.isEmpty ? '' : '{"type":"form","table":"one of: $add","title":"...","submit":"button text","thanks":"message after sending"}\n'}'
        'Put a list right before a form that picks from it: customers then press "Add" on a card to put it in the form.';
  }

  String? _checkBlocks(Map<String, dynamic> j) =>
      j['blocks'] is List && [for (final b in j['blocks'] as List) ?Block.fromJson(b)].isNotEmpty ? null : 'Give a "blocks" list with at least one block.';

  Future<List<Block>> pageBlocks(AppSpec spec, String pageId) async {
    final p = spec.page(pageId)!;
    // A page for ordering / booking needs the form that saves it.
    final adds = spec.tables.where((t) => t.access.add && !t.single).toList();
    final act = _customerActs.firstMatch('${p.title} ${p.purpose}');
    final needForm = act != null && adds.isNotEmpty;
    final j = await askJson(
      'App plan:\n${spec.outline()}\n'
      'Now design the customer page "${p.id}" (${p.purpose}). JSON:\n${_blockFormat(spec)}\n'
      'Rules: 2 to 5 blocks. Start with a "hero" block. The business is called "${spec.name}". Pages: ${spec.pages.map((x) => x.id).join(', ')}. Write warm, professional texts for customers, in the language the user wrote in.'
      '${needForm ? ' This page must have a "form" block for ${adds.map((t) => '"${t.id}"').join(' or ')}.' : ''}',
      check: (j) {
        final base = _checkBlocks(j);
        if (base != null || !needForm) return base;
        final hasForm = (j['blocks'] as List).map(Block.fromJson).any((b) => b?.type == 'form' && adds.any((t) => t.id == slug(b!.table) || t.id.startsWith(slug(b.table))));
        return hasForm ? null : 'Customers ${act[0]!.toLowerCase()} on this page: add {"type":"form","table":"${adds.first.id}",...}.';
      },
    );
    return _blocks(spec, p, j['blocks'] as List);
  }

  Future<List<Block>> changePage(AppSpec spec, String pageId, String change) async {
    final p = spec.page(pageId)!;
    final j = await askJson(
      'App plan:\n${spec.outline()}\n'
      'The page "${p.id}" now has:\n${jsonEncode({'blocks': [for (final b in p.blocks) b.data]})}\n'
      'The user wants this change: "$change"\n'
      'Return all blocks of the page after the change. JSON:\n${_blockFormat(spec)}',
      check: _checkBlocks,
    );
    return _blocks(spec, p, j['blocks'] as List);
  }

  List<Block> _blocks(AppSpec spec, PageSpec p, List raw) {
    final next = spec.copyWith(pages: [for (final x in spec.pages) x.id == p.id ? x.copyWith(blocks: [for (final b in raw) ?Block.fromJson(b)]) : x]).repaired();
    return next.page(p.id)!.blocks;
  }

  // ---------------- additions ----------------

  /// A new table or page from a sentence. Returns the app with the new part (fields/blocks filled in).
  Future<AppSpec> addPart(AppSpec spec, String what) async {
    final j = await askJson(
      'App plan:\n${spec.outline()}\n'
      'The user wants to add: "$what"\n'
      'Is that new data to keep (a table) or a new customer page? JSON:\n'
      '{"kind":"table","table":{"id":"snake_case","title":"Title","purpose":"...","kind":"list" or "single","access":"see" | "add" | "see+add" | "none"}}\n'
      'or {"kind":"page","page":{"id":"snake_case","title":"Title","purpose":"..."}}',
      check: (j) => (j['kind'] == 'table' && j['table'] is Map) || (j['kind'] == 'page' && j['page'] is Map) ? null : 'Use "kind":"table" with "table", or "kind":"page" with "page".',
    );
    if (j['kind'] == 'table') {
      var t = TableSpec.fromJson(j['table'])!;
      while (spec.table(t.id) != null) {
        t = TableSpec(id: '${t.id}_2', title: t.title, purpose: t.purpose, single: t.single, access: t.access);
      }
      var next = spec.copyWith(tables: [...spec.tables, t]);
      final fields = await tableFields(next, t.id, const []);
      next = next.copyWith(tables: [for (final x in next.tables) x.id == t.id ? x.copyWith(fields: fields) : x]);
      return next.repaired();
    }
    var p = PageSpec.fromJson(j['page'])!;
    while (spec.page(p.id) != null) {
      p = PageSpec(id: '${p.id}_2', title: p.title, purpose: p.purpose);
    }
    final next = spec.copyWith(pages: [...spec.pages, p]);
    final blocks = await pageBlocks(next, p.id);
    return next.copyWith(pages: [for (final x in next.pages) x.id == p.id ? x.copyWith(blocks: blocks) : x]);
  }

  /// A new style and colour from a sentence ("make it dark and luxurious") and/or a picture's notes.
  Future<AppSpec> changeLook(AppSpec spec, String change) async {
    final j = await askJson(
      'A website now uses the style "${spec.style}" with main colour ${spec.theme.isEmpty ? styleOf(spec.style).accent : spec.theme}.\n'
      'Styles: ${siteStyles.map((s) => '"${s.id}" (${s.about})').join('; ')}.\n'
      'The user wants: "$change"\nJSON: {"style":"one of the style ids","accent":"#rrggbb main colour"}',
      check: (j) => siteStyles.any((s) => s.id == j['style']) ? null : 'Pick "style" from: ${siteStyles.map((s) => s.id).join(', ')}.',
    );
    final accent = '${j['accent'] ?? ''}';
    return spec.copyWith(
      site: {...spec.site, 'style': j['style'] as String},
      theme: RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accent) ? accent : spec.theme,
    );
  }

  /// New website details (tagline, about, contact, footer) from a sentence.
  Future<AppSpec> changeSite(AppSpec spec, String change) async {
    const keys = ['name', 'tagline', 'about', 'address', 'phone', 'email', 'footer', 'currency'];
    final now = {'name': spec.name, for (final k in keys.skip(1)) k: spec.site[k] ?? ''};
    final j = await askJson(
      'The website of "${spec.name}" (${spec.summary}) has these details:\n${jsonEncode(now)}\n'
      'The user wants: "$change"\nReturn all details after the change, same JSON keys.',
    );
    final site = {...spec.site};
    for (final k in keys.skip(1)) {
      final v = '${j[k] ?? now[k]}'.trim();
      v.isEmpty ? site.remove(k) : site[k] = v;
    }
    final name = '${j['name'] ?? ''}'.trim();
    return spec.copyWith(name: name.isEmpty ? null : name, site: site);
  }

  /// Which part a change is about: look, site details, one table, one page, or something new.
  Future<({String kind, String? target})> route(AppSpec spec, String request) async {
    // "Add a page about…" / "a new gallery page" is always something new.
    final r = request.toLowerCase();
    if (RegExp(r'\b(add|create|make|new|another)\b[^.]*\bpage\b').hasMatch(r) && !spec.pages.any((p) => r.contains('${p.title.toLowerCase()} page'))) {
      return (kind: 'add', target: null);
    }
    final j = await askJson(
      'App plan:\n${spec.outline()}\n'
      'The user asks: "$request"\n'
      'Which ONE part should change? JSON {"kind":"look" | "site" | "table" | "page" | "add","target":"table or page id, if any"}\n'
      '- look: colours, style, dark/light, fonts, "more modern/luxurious/fun"\n'
      '- site: the business name, slogan/tagline, about text, address, phone, email, currency\n'
      '- table: the information kept for one table (add or remove fields, e.g. "add a photo to the menu", "orders need a phone number")\n'
      '- page: what one EXISTING page shows or says (texts, order of sections, headings)\n'
      '- add: a new page or a new kind of data that does not exist yet',
      check: (j) {
        final k = j['kind'];
        if (!const ['look', 'site', 'table', 'page', 'add'].contains(k)) return '"kind" must be look, site, table, page or add.';
        if (k == 'table' && spec.table(slug(j['target'])) == null) return 'Give "target": one of ${spec.tables.map((t) => t.id).join(', ')}.';
        if (k == 'page' && spec.page(slug(j['target'])) == null) return 'Give "target": one of ${spec.pages.map((p) => p.id).join(', ')}.';
        return null;
      },
    );
    return (kind: j['kind'] as String, target: j['target'] == null ? null : slug(j['target']));
  }

  // ---------------- reading records from a photo ----------------

  /// Reads the records in a photo (a menu, a price list, a product sheet…) for one table.
  /// Nothing is saved: the user checks them first.
  Future<List<Map<String, dynamic>>> rowsFromPicture(AppSpec spec, String tableId, String base64, {required String model}) async {
    final t = spec.table(tableId)!;
    final fields = t.fields.where((f) => f.type != 'image' && f.type != 'links' && !f.managerOnly).toList();
    final j = await askJson(
      'This picture shows ${t.title.toLowerCase()} of "${spec.name}" (${t.purpose}), e.g. a menu or a price list.\n'
      'Read EVERY item in it, in order. For each item fill these fields when the picture shows them:\n'
      '${fields.map((f) => '- ${f.id}: ${f.type == 'money' ? 'price, as printed' : fieldTypes[f.type]}${f.options.isNotEmpty ? ', one of: ${f.options.join(' / ')}' : ''}${f.link != null ? ' (a name from ${spec.table(f.link!)?.title.toLowerCase()})' : ''}').join('\n')}\n'
      'Copy prices exactly as printed, as text with the decimal point (e.g. "6.50"). Leave out fields the picture does not show. Copy names exactly as written.\n'
      'JSON: {"rows":[{"${fields.first.id}":"..."}]}',
      images: [base64],
      model: model,
      check: (j) => j['rows'] is List && (j['rows'] as List).whereType<Map>().isNotEmpty ? null : 'Give "rows": a list with one object per item in the picture.',
    );
    final ids = {for (final f in fields) f.id};
    return [
      for (final r in (j['rows'] as List).whereType<Map>())
        {for (final e in r.entries) if (ids.contains(slug(e.key)) && e.value != null && '${e.value}'.trim().isNotEmpty) slug(e.key): e.value},
    ].where((r) => r.isNotEmpty).take(80).toList();
  }

  // ---------------- example data ----------------

  Future<List<Map<String, dynamic>>> exampleRows(AppSpec spec, String tableId, List<PictureNotes> pics, Map<String, List<String>> linkNames) async {
    final t = spec.table(tableId)!;
    final content = pics.where((p) => p.content.isNotEmpty).map((p) => p.content).join('\n');
    final links = t.fields.where((f) => f.link != null && (linkNames[f.link]?.isNotEmpty ?? false)).map((f) => '- ${f.id}: use names from ${linkNames[f.link]!.take(15).join(', ')}').join('\n');
    final j = await askJson(
      'App plan:\n${spec.outline()}\n'
      '${content.isEmpty ? '' : 'The user\'s pictures show this (use it as the real data where it fits):\n$content\n\n'}'
      'Write ${t.single ? 'the one record' : '3 to 8 realistic example records'} for the table "${t.id}" (${t.purpose}).\n'
      'Fields: ${t.fields.map((f) => '${f.id} (${f.type}${f.options.isNotEmpty ? ': ${f.options.join('/')}' : ''})').join(', ')}\n'
      '${links.isEmpty ? '' : 'For link fields:\n$links\n'}'
      'JSON: {"rows":[{"${t.fields.first.id}":"..."}]}',
      check: (j) => j['rows'] is List && (j['rows'] as List).whereType<Map>().isNotEmpty ? null : 'Give a "rows" list of objects.',
    );
    return [for (final r in (j['rows'] as List).whereType<Map>()) r.cast<String, dynamic>()].take(t.single ? 1 : 20).toList();
  }
}
