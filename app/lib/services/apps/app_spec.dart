/// What a user-built app is: its data (tables), its website pages, and who may do what.
///
/// The AI never writes server code. It fills in this small description one piece at a
/// time, and [AppSpec.fromJson] repairs anything a small model gets wrong, so the app
/// engine ([AppServer]) can always run it.
library;

const fieldTypes = <String, String>{
  'text': 'short text',
  'longtext': 'long text',
  'number': 'number',
  'money': 'price / amount',
  'yesno': 'yes or no',
  'date': 'date',
  'time': 'time of day',
  'datetime': 'date and time',
  'choice': 'one of a few options',
  'link': 'one record from another table',
  'links': 'several records from another table',
  'email': 'email address',
  'phone': 'phone number',
  'image': 'photo',
};

/// Model words that mean one of our types.
const _typeAliases = <String, String>{
  'string': 'text', 'str': 'text', 'name': 'text', 'url': 'text', 'shorttext': 'text',
  'photo': 'image', 'picture': 'image', 'img': 'image', 'imageurl': 'image', 'image_url': 'image', 'logo': 'image', 'thumbnail': 'image',
  'textarea': 'longtext', 'description': 'longtext', 'long_text': 'longtext', 'notes': 'longtext',
  'int': 'number', 'integer': 'number', 'float': 'number', 'decimal': 'number', 'double': 'number', 'quantity': 'number',
  'price': 'money', 'currency': 'money', 'amount': 'money',
  'bool': 'yesno', 'boolean': 'yesno', 'checkbox': 'yesno', 'yes_no': 'yesno',
  'enum': 'choice', 'select': 'choice', 'status': 'choice', 'options': 'choice', 'dropdown': 'choice',
  'reference': 'link', 'ref': 'link', 'relation': 'link', 'foreignkey': 'link', 'foreign_key': 'link',
  'list': 'links', 'refs': 'links', 'references': 'links', 'many': 'links', 'multi': 'links',
  'timestamp': 'datetime', 'date_time': 'datetime',
  'tel': 'phone', 'mail': 'email',
};

/// `Menu Items!` → `menu_items`.
String slug(Object? s, {String fallback = 'item'}) {
  final v = '${s ?? ''}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  if (v.isEmpty) return fallback;
  return RegExp(r'^[0-9]').hasMatch(v) ? 't_$v' : (v.length > 40 ? v.substring(0, 40) : v);
}

/// `menu_items` → `Menu items`.
String titleOf(String id) {
  final t = id.replaceAll('_', ' ').trim();
  return t.isEmpty ? id : t[0].toUpperCase() + t.substring(1);
}

bool _bool(Object? v) => v == true || '$v'.toLowerCase() == 'true' || '$v' == '1' || '$v'.toLowerCase() == 'yes';

String _str(Object? v) => v == null ? '' : '$v'.trim();

class FieldSpec {
  FieldSpec({required this.id, required this.label, required this.type, this.required = false, this.options = const [], this.link, this.managerOnly = false, this.qty = false, this.when});
  final String id, label, type;
  final bool required, managerOnly;

  /// Only asked for when another field has one of these values (e.g. address: {'type': ['Delivery']});
  /// [required] then means required in that case.
  final MapEntry<String, List<String>>? when;

  /// Whether this field applies, given the other values of the record.
  bool appliesTo(Map<String, Object?> values) {
    final w = when;
    if (w == null) return true;
    final v = '${values[w.key] ?? ''}'.toLowerCase();
    return w.value.any((o) => o.toLowerCase() == v);
  }

  /// For `choice`.
  final List<String> options;

  /// For `link` / `links`: the other table's id.
  final String? link;

  /// For `links`: each picked record has a quantity (e.g. 2 × Pizza).
  final bool qty;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'type': type,
        if (required) 'required': true,
        if (options.isNotEmpty) 'options': options,
        'link': ?link,
        if (managerOnly) 'manager_only': true,
        if (qty) 'qty': true,
        if (when != null) 'when': {when!.key: when!.value},
      };

  static FieldSpec? fromJson(Object? j) {
    if (j is String) j = {'id': j};
    if (j is! Map) return null;
    final id = slug(j['id'] ?? j['name'] ?? j['label'], fallback: '');
    if (id.isEmpty || id == 'id') return null;
    var type = slug(j['type'], fallback: 'text').replaceAll('_', '');
    type = fieldTypes.containsKey(type) ? type : (_typeAliases[slug(j['type'], fallback: 'text')] ?? _typeAliases[type] ?? 'text');
    var options = <String>[];
    final o = j['options'] ?? j['choices'] ?? j['values'];
    if (o is List) options = [for (final x in o) _str(x is Map ? (x['label'] ?? x['value']) : x)]..removeWhere((x) => x.isEmpty);
    if (o is String) options = o.split(RegExp(r'[,|/]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (type == 'choice' && options.isEmpty) type = 'text';
    final link = j['link'] ?? j['table'] ?? j['ref'] ?? j['references'];
    return FieldSpec(
      id: id,
      label: _str(j['label']).isEmpty ? titleOf(id) : _str(j['label']),
      type: type,
      required: _bool(j['required']),
      options: options.toSet().take(30).toList(),
      link: link == null || _str(link).isEmpty ? null : slug(link),
      managerOnly: _bool(j['manager_only'] ?? j['managerOnly'] ?? j['admin_only']),
      qty: _bool(j['qty'] ?? j['quantity']),
      when: _when(j['when'] ?? j['show_if'] ?? j['only_if']),
    );
  }

  static MapEntry<String, List<String>>? _when(Object? w) {
    if (w is! Map || w.isEmpty) return null;
    final e = w.entries.first;
    final vals = e.value is List ? [for (final v in e.value as List) _str(v)] : [_str(e.value)];
    vals.removeWhere((v) => v.isEmpty);
    return vals.isEmpty ? null : MapEntry(slug(e.key), vals);
  }

  FieldSpec copyWith({String? type, String? link, bool clearLink = false, bool? qty, bool? managerOnly}) => FieldSpec(
      id: id, label: label, type: type ?? this.type, required: required, options: options, link: clearLink ? null : (link ?? this.link), managerOnly: managerOnly ?? this.managerOnly, qty: qty ?? this.qty, when: when);
}

/// Who, besides the manager, may use a table: website visitors and phone callers.
/// A field that holds someone's personal details: their number, email, address, date of birth,
/// health or payment details, private notes.
bool personal(FieldSpec f) =>
    f.type == 'phone' ||
    f.type == 'email' ||
    RegExp(r'address|post ?code|zip|street|birth|\bdob\b|allerg|medical|health|nhs|insurance|card|payment|passport|national|private|notes?\b', caseSensitive: false).hasMatch('${f.id} ${f.label}');

/// A record's status (New, Confirmed, Cancelled…): the choice field called `status`, else the first
/// choice only the manager sets. (Other manager-only choices, like payment, are never the status.)
FieldSpec? statusOf(TableSpec t) =>
    t.fields.where((f) => f.type == 'choice' && f.id == 'status').firstOrNull ?? t.fields.where((f) => f.type == 'choice' && f.managerOnly).firstOrNull;

/// Days the business is closed (holidays, private hire): a list with a date in it, called
/// closures / holidays / closed days.
TableSpec? closuresOf(AppSpec spec) => spec.tables
    .where((t) => !t.single && RegExp(r'closure|holiday|closed', caseSensitive: false).hasMatch('${t.id} ${t.purpose}') && t.fields.any((f) => f.type == 'date'))
    .firstOrNull;

class Access {
  const Access({this.see = false, this.add = false});
  final bool see, add;

  String get label => see && add ? 'Customers can see and add' : (see ? 'Customers can see' : (add ? 'Customers can add (not see)' : 'Manager only'));

  Object toJson() => [if (see) 'see', if (add) 'add'];

  /// Read from exact words ("see", "add", "see+add", ["see","add"]): loose wording like "customers
  /// can't see" or "all" must never make a table public.
  static Access fromJson(Object? j) {
    final raw = (j is List ? j.join(' ') : '$j').toLowerCase();
    final words = raw.split(RegExp(r'[^a-z]+')).toSet();
    final no = RegExp(r"\b(can[’']?t|cannot|not|no|none|never)\b").hasMatch(raw);
    if (no || words.contains('manager') || words.contains('private')) {
      return Access(add: !no && words.contains('add'));
    }
    return Access(see: words.any(const {'see', 'read', 'view', 'list', 'public'}.contains), add: words.any(const {'add', 'create', 'submit', 'order', 'book'}.contains));
  }
}

class TableSpec {
  TableSpec({required this.id, required this.title, this.purpose = '', this.single = false, this.access = const Access(), this.fields = const []});
  final String id, title, purpose;

  /// One record only (e.g. opening hours, shop details), not a list.
  final bool single;
  final Access access;
  final List<FieldSpec> fields;

  /// The field that names a record (shown in lists and pickers).
  /// The AI is told to put the name first; fall back to the first short text.
  String get labelField {
    final first = fields.firstOrNull;
    if (first != null && !first.managerOnly && !const {'link', 'links', 'longtext', 'yesno'}.contains(first.type)) return first.id;
    return (fields.where((f) => f.type == 'text' && !f.managerOnly).firstOrNull ?? fields.firstOrNull)?.id ?? 'id';
  }

  FieldSpec? field(String id) => fields.where((f) => f.id == id).firstOrNull;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        if (purpose.isNotEmpty) 'purpose': purpose,
        'kind': single ? 'single' : 'list',
        'access': access.toJson(),
        'fields': [for (final f in fields) f.toJson()],
      };

  static TableSpec? fromJson(Object? j) {
    if (j is String) j = {'id': j};
    if (j is! Map) return null;
    final id = slug(j['id'] ?? j['name'] ?? j['title'], fallback: '');
    if (id.isEmpty) return null;
    final fields = <FieldSpec>[];
    for (final f in (j['fields'] is List ? j['fields'] as List : const [])) {
      final fs = FieldSpec.fromJson(f);
      if (fs != null && !fields.any((x) => x.id == fs.id) && !const {'created_at', 'updated_at'}.contains(fs.id)) fields.add(fs);
    }
    return TableSpec(
      id: id,
      title: _str(j['title']).isEmpty ? titleOf(id) : _str(j['title']),
      purpose: _str(j['purpose'] ?? j['description']),
      single: RegExp(r'single|one|settings').hasMatch(_str(j['kind']).toLowerCase()),
      access: Access.fromJson(j['access'] ?? j['public']),
      fields: fields.take(25).toList(),
    );
  }

  TableSpec copyWith({List<FieldSpec>? fields, Access? access, String? title, String? purpose}) =>
      TableSpec(id: id, title: title ?? this.title, purpose: purpose ?? this.purpose, single: single, access: access ?? this.access, fields: fields ?? this.fields);
}

/// One piece of a page. Types: text, list, form, info.
class Block {
  Block(this.data);
  final Map<String, Object?> data;
  String get type => data['type'] as String;
  String? get table => data['table'] as String?;

  /// A few words about this part of a page, e.g. "banner", "list of menu".
  String describe(AppSpec spec) => switch (type) {
        'hero' => 'banner',
        'text' => 'text',
        'contact' => 'contact details and map link',
        'features' => 'highlights',
        'gallery' => 'photo gallery${table == null ? '' : ' of ${spec.table(table!)?.title.toLowerCase() ?? table}'}',
        'testimonials' => 'reviews from ${spec.table(table ?? '')?.title.toLowerCase() ?? table ?? '?'}',
        'list' when data['layout'] == 'menu' => 'menu of ${spec.table(table ?? '')?.title.toLowerCase() ?? table ?? '?'}',
        'availability' => 'free times of ${spec.table(table ?? '')?.title.toLowerCase() ?? table ?? '?'}',
        _ => '${type == 'info' ? 'details' : type} of ${spec.table(table ?? '')?.title.toLowerCase() ?? table ?? '?'}',
      };

  static Block? fromJson(Object? j) {
    if (j is String) return Block({'type': 'text', 'text': j});
    if (j is! Map) return null;
    var type = slug(j['type'], fallback: 'text');
    type = switch (type) {
      'hero' || 'banner' || 'header' || 'cover' => 'hero',
      'text' || 'heading' || 'paragraph' || 'markdown' || 'html' || 'intro' => 'text',
      'list' || 'table' || 'grid' || 'cards' || 'search' || 'catalog' || 'menu' => 'list',
      'form' || 'create' || 'add' || 'booking' || 'order' || 'input' => 'form',
      'info' || 'details' || 'single' || 'record' || 'hours' => 'info',
      'availability' || 'free' || 'slots' || 'calendar' || 'schedule' || 'timetable' => 'availability',
      'gallery' || 'photos' || 'images' || 'pictures' || 'carousel' => 'gallery',
      'testimonials' || 'testimonial' || 'reviews' || 'quotes' => 'testimonials',
      'contact' || 'map' || 'location' || 'find_us' || 'contact_us' => 'contact',
      'features' || 'highlights' || 'benefits' || 'why_us' || 'icons' => 'features',
      _ => '',
    };
    if (type.isEmpty) return null;
    final out = <String, Object?>{'type': type};
    if (type == 'hero') {
      final title = _str(j['title'] ?? j['heading'] ?? j['text']);
      if (title.isEmpty) return null;
      out['title'] = title;
      for (final k in const ['text', 'button', 'link', 'image']) {
        final v = _str(j[k == 'text' ? 'text' : k] ?? (k == 'text' ? j['subtitle'] : null));
        if (v.isNotEmpty && !(k == 'text' && v == title)) out[k] = k == 'link' ? slug(v) : v;
      }
    } else if (type == 'contact') {
      for (final k in const ['title', 'text']) {
        final v = _str(j[k] ?? (k == 'title' ? j['heading'] : null));
        if (v.isNotEmpty) out[k] = v.length > 600 ? v.substring(0, 600) : v;
      }
    } else if (type == 'features') {
      // One card per line: "Title: what it means". Also from a list of items.
      final items = j['items'] ?? j['features'];
      var text = _str(j['text'] ?? j['content']);
      if (text.isEmpty && items is List) {
        text = [
          for (final x in items)
            if (x is Map) [_str(x['title'] ?? x['name']), _str(x['text'] ?? x['description'])].where((v) => v.isNotEmpty).join(': ') else _str(x),
        ].where((l) => l.isNotEmpty).join('\n');
      }
      final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).take(12).toList();
      if (lines.isEmpty) return null;
      out['text'] = lines.join('\n').length > 2000 ? lines.join('\n').substring(0, 2000) : lines.join('\n');
      final title = _str(j['title'] ?? j['heading']);
      if (title.isNotEmpty) out['title'] = title;
    } else if (type == 'gallery') {
      // Photos: from a table's pictures, and/or a list of pictures.
      final title = _str(j['title'] ?? j['heading']);
      if (title.isNotEmpty) out['title'] = title;
      final t = j['table'] ?? j['source'];
      if (t != null && _str(t).isNotEmpty) out['table'] = slug(t);
      final imgs = j['images'] ?? j['photos'];
      final list = [for (final x in (imgs is List ? imgs : const [])) _str(x is Map ? (x['url'] ?? x['src']) : x)]..removeWhere((x) => x.isEmpty);
      if (list.isNotEmpty) out['images'] = list.take(24).toList();
      if (out['table'] == null && out['images'] == null) return null;
    } else if (type == 'text') {
      final text = _str(j['text'] ?? j['content'] ?? j['body'] ?? j['title']);
      if (text.isEmpty) return null;
      out['text'] = text.length > 2000 ? text.substring(0, 2000) : text;
    } else {
      final t = j['table'] ?? j['source'] ?? j['data'];
      if (t == null) return null;
      out['table'] = slug(t);
      final title = _str(j['title'] ?? j['heading']);
      if (title.isNotEmpty) out['title'] = title;
      if (j['fields'] is List) out['fields'] = [for (final f in j['fields'] as List) slug(f is Map ? (f['id'] ?? f['name']) : f)];
      if (type == 'list') out['search'] = j['search'] == null ? true : _bool(j['search']);
      // A printed-menu look (sections, dotted lines to the price) instead of cards.
      if (type == 'list' && slug(j['layout'] ?? j['style'], fallback: '') == 'menu') out['layout'] = 'menu';
      // Only the records ticked yes in this field (e.g. popular dishes).
      if (type == 'list' && _str(j['only']).isNotEmpty) out['only'] = slug(j['only']);
      if (type == 'form') {
        final submit = _str(j['submit'] ?? j['button']);
        final thanks = _str(j['thanks'] ?? j['success'] ?? j['message']);
        if (submit.isNotEmpty) out['submit'] = submit;
        if (thanks.isNotEmpty) out['thanks'] = thanks;
      }
    }
    return Block(out);
  }
}

class PageSpec {
  PageSpec({required this.id, required this.title, this.purpose = '', this.manager = false, this.blocks = const []});
  final String id, title, purpose;

  /// Only for the manager (needs the manager PIN).
  final bool manager;
  final List<Block> blocks;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        if (purpose.isNotEmpty) 'purpose': purpose,
        if (manager) 'manager': true,
        'blocks': [for (final b in blocks) b.data],
      };

  static PageSpec? fromJson(Object? j) {
    if (j is String) j = {'id': j};
    if (j is! Map) return null;
    final id = slug(j['id'] ?? j['name'] ?? j['title'], fallback: '');
    if (id.isEmpty) return null;
    return PageSpec(
      id: id,
      title: _str(j['title']).isEmpty ? titleOf(id) : _str(j['title']),
      purpose: _str(j['purpose'] ?? j['description']),
      manager: _bool(j['manager'] ?? j['admin']),
      blocks: [for (final b in (j['blocks'] is List ? j['blocks'] as List : const [])) ?Block.fromJson(b)].take(12).toList(),
    );
  }

  PageSpec copyWith({List<Block>? blocks, String? title, String? purpose}) =>
      PageSpec(id: id, title: title ?? this.title, purpose: purpose ?? this.purpose, manager: manager, blocks: blocks ?? this.blocks);
}

/// What the user asked for besides the data.
class Features {
  const Features({this.website = true, this.ava = true});
  final bool website, ava;
  Map<String, bool> toJson() => {'website': website, 'ava': ava};
  static Features fromJson(Object? j) => j is Map ? Features(website: j['website'] != false, ava: j['ava'] != false) : const Features();
}

class AppSpec {
  AppSpec({required this.name, this.summary = '', this.tables = const [], this.pages = const [], this.features = const Features(), this.theme = '', this.dark = false, this.font = 'sans', this.site = const {}});
  final String name, summary;

  /// The user's own main colour; empty = the style's colour.
  final String theme;

  /// Website details the manager can edit: style, tagline, about, logo, hero, address, phone, email.
  final Map<String, String> site;
  String get style => site['style'] ?? 'modern';

  static const siteKeys = ['style', 'tagline', 'about', 'logo', 'hero', 'address', 'phone', 'email', 'footer', 'currency', 'booking_minutes', 'delivery_fee', 'min_order'];

  /// The look: dark background, and sans / serif / rounded letters.
  final bool dark;
  final String font;
  final List<TableSpec> tables;
  final List<PageSpec> pages;
  final Features features;

  TableSpec? table(String id) => tables.where((t) => t.id == id).firstOrNull;
  PageSpec? page(String id) => pages.where((p) => p.id == id).firstOrNull;

  Map<String, Object?> toJson() => {
        'name': name,
        if (summary.isNotEmpty) 'summary': summary,
        'theme': theme,
        'look': {'dark': dark, 'font': font},
        'site': site,
        'features': features.toJson(),
        'tables': [for (final t in tables) t.toJson()],
        'pages': [for (final p in pages) p.toJson()],
      };

  /// Reads (and repairs) a description from the AI or the database.
  static AppSpec fromJson(Map<String, dynamic> j) {
    final tables = <TableSpec>[];
    for (final t in (j['tables'] is List ? j['tables'] as List : const [])) {
      final ts = TableSpec.fromJson(t);
      if (ts != null && !tables.any((x) => x.id == ts.id)) tables.add(ts);
    }
    final pages = <PageSpec>[];
    for (final p in (j['pages'] is List ? j['pages'] as List : const [])) {
      final ps = PageSpec.fromJson(p);
      if (ps != null && !pages.any((x) => x.id == ps.id)) pages.add(ps);
    }
    final theme = _str(j['theme']);
    final look = j['look'] is Map ? j['look'] as Map : const {};
    final rawSite = j['site'] is Map ? j['site'] as Map : const {};
    final site = <String, String>{
      for (final k in siteKeys)
        if (_str(rawSite[k]).isNotEmpty) k: _str(rawSite[k]).length > 1500 ? _str(rawSite[k]).substring(0, 1500) : _str(rawSite[k]),
    };
    if (site['tagline'] == null && _str(j['tagline']).isNotEmpty) site['tagline'] = _str(j['tagline']);
    return AppSpec(
      site: site,
      dark: look['dark'] == true,
      font: const {'serif', 'rounded'}.contains(look['font']) ? look['font'] as String : 'sans',
      name: _str(j['name']).isEmpty ? 'My app' : _str(j['name']),
      summary: _str(j['summary'] ?? j['description']),
      // #1F6FEB was the old default: let the style choose instead.
      theme: RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(theme) && theme.toUpperCase() != '#1F6FEB' ? theme : '',
      features: Features.fromJson(j['features']),
      tables: tables.take(12).toList(),
      pages: pages.take(10).toList(),
    ).repaired();
  }

  /// This app with [other]'s colours and font.
  AppSpec withLook(AppSpec other) => AppSpec(
      name: name, summary: summary, features: features, tables: tables, pages: pages, theme: other.theme, dark: other.dark, font: other.font,
      site: {...site, 'style': other.style});

  AppSpec copyWith({String? name, String? summary, List<TableSpec>? tables, List<PageSpec>? pages, Features? features, Map<String, String>? site, String? theme}) => AppSpec(
      name: name ?? this.name,
      summary: summary ?? this.summary,
      theme: theme ?? this.theme,
      site: site ?? this.site,
      dark: dark,
      font: font,
      features: features ?? this.features,
      tables: tables ?? this.tables,
      pages: pages ?? this.pages);

  /// Fixes what doesn't fit together: links to tables that don't exist, blocks that
  /// show unknown tables or fields, forms for tables customers can't add to.
  AppSpec repaired() {
    final ids = {for (final t in tables) t.id};
    String? resolve(String? id) {
      if (id == null) return null;
      if (ids.contains(id)) return id;
      // "menu_item" → "menu_items", "items" → "menu_items"
      return ids.where((t) => t == '${id}s' || '${t}s' == id || t.endsWith('_$id') || t.endsWith('_${id}s')).firstOrNull;
    }

    var fixedTables = [
      for (final t in tables)
        t.copyWith(fields: [
          for (final f in t.fields)
            if (f.type == 'link' || f.type == 'links')
              (resolve(f.link) == null || resolve(f.link) == t.id && t.single) ? f.copyWith(type: 'text', clearLink: true) : f.copyWith(link: resolve(f.link))
            else
              f,
        ]),
    ];
    // People's details are never public, whatever the app's description says: a table customers
    // add to that holds phone numbers or emails (bookings, orders, patients) can't be listed by
    // customers — each caller only reaches their own, by their number and name.
    fixedTables = [
      for (final t in fixedTables)
        t.access.see && t.access.add && t.fields.any(personal) && !t.single ? t.copyWith(access: Access(add: true)) : t,
    ];
    final private = {for (final t in fixedTables) if (!t.single && t.fields.any((f) => f.type == 'phone' || f.type == 'email') && (t.access.add || !t.access.see)) t.id};
    // Customers who can add to a table must be able to pick the records it links to — but not
    // people's records (a "patient" link is filled in by the manager, not picked from a list).
    final mustSee = {
      for (final t in fixedTables)
        if (t.access.add)
          for (final f in t.fields)
            if (f.link != null && !f.managerOnly && !private.contains(f.link)) f.link!,
    };
    fixedTables = [
      for (final t in fixedTables)
        (mustSee.contains(t.id) && !t.access.see ? t.copyWith(access: Access(see: true, add: t.access.add)) : t).copyWith(fields: [
          for (final f in t.fields)
            if (f.link != null && private.contains(f.link) && t.access.add && !f.managerOnly) f.copyWith(managerOnly: true) else f,
        ]),
    ];
    final byId = {for (final t in fixedTables) t.id: t};

    final fixedPages = <PageSpec>[];
    for (final p in pages) {
      final blocks = <Block>[];
      for (final b in p.blocks) {
        if (b.type == 'text' || b.type == 'contact' || b.type == 'features') {
          blocks.add(b);
          continue;
        }
        if (b.type == 'gallery') {
          // Pictures from a table only when visitors may see that table.
          final d = Map<String, Object?>.of(b.data)..remove('table');
          final t = b.table == null ? null : byId[resolve(b.table) ?? ''];
          if (t != null && !t.single && t.fields.any((f) => f.type == 'image' && !f.managerOnly) && (p.manager || t.access.see)) d['table'] = t.id;
          if (d['table'] == null && d['images'] == null) continue;
          blocks.add(Block(d));
          continue;
        }
        if (b.type == 'hero') {
          final d = Map<String, Object?>.of(b.data);
          if (d['link'] != null && !pages.any((x) => x.id == d['link'])) d.remove('link');
          blocks.add(Block(d));
          continue;
        }
        final t = byId[resolve(b.table) ?? ''];
        if (t == null) continue;
        final d = Map<String, Object?>.of(b.data)..['table'] = t.id;
        if (d['fields'] is List) {
          final keep = [for (final f in d['fields'] as List) if (t.field('$f') != null) '$f'];
          if (keep.isEmpty) {
            d.remove('fields');
          } else {
            d['fields'] = keep;
          }
        }
        if (b.type == 'testimonials') {
          // Quotes from a list visitors may see (reviews the manager picked), never from bookings.
          final quote = t.fields.any((f) => (f.type == 'longtext' || f.type == 'text') && !f.managerOnly);
          if (!t.single && quote && (p.manager || t.access.see)) blocks.add(Block(d));
          continue;
        }
        if (b.type == 'list' && d['only'] != null && t.field('${d['only']}')?.type != 'yesno') d.remove('only');
        if (b.type == 'availability') {
          final link = t.fields.where((f) => f.type == 'link').firstOrNull;
          final ok = link != null && t.fields.any((f) => f.type == 'date') && t.fields.any((f) => f.type == 'time') && (p.manager || t.access.add);
          if (ok) blocks.add(Block({...b.data, 'table': t.id}));
          continue;
        }
        final type = b.type == 'list' && t.single ? 'info' : (b.type == 'info' && !t.single ? 'list' : b.type);
        d['type'] = type;
        if (type != 'list') d..remove('search')..remove('layout')..remove('only');
        // Public pages only show what customers may use.
        if (!p.manager && (type == 'list' || type == 'info') && !t.access.see) continue;
        if (!p.manager && type == 'form' && !t.access.add) continue;
        blocks.add(Block(d));
      }
      fixedPages.add(p.copyWith(blocks: blocks));
    }
    return copyWith(tables: fixedTables, pages: fixedPages);
  }

  /// A short readable outline, given to the AI so it knows the whole app.
  String outline({bool fields = true}) {
    final b = StringBuffer('App: $name — $summary\nTables:\n');
    for (final t in tables) {
      b.writeln('- ${t.id} (${t.single ? 'one record' : 'list'}; ${t.access.label}): ${t.purpose}');
      if (fields && t.fields.isNotEmpty) {
        b.writeln('    fields: ${t.fields.map((f) => '${f.id}:${f.type}${f.link != null ? '→${f.link}' : ''}${f.options.isNotEmpty ? '[${f.options.join('|')}]' : ''}${f.managerOnly ? '(manager only)' : ''}').join(', ')}');
      }
    }
    b.writeln('Pages:');
    for (final p in pages) {
      b.writeln('- ${p.id}${p.manager ? ' (manager only)' : ''}: ${p.purpose}');
    }
    return b.toString();
  }
}
