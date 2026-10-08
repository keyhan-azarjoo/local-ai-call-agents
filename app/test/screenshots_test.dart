import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/agent_templates.dart';
import 'package:localailine/services/apps/app_spec.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/auth.dart';
import 'package:localailine/services/builtin_llm.dart';
import 'package:localailine/services/catalog.dart';
import 'package:localailine/services/companion/host_server.dart';
import 'package:localailine/services/hardware.dart';
import 'package:localailine/services/knowledge/knowledge.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/speech.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine/theme/tokens.dart';
import 'package:localailine/ui/pages/test_runs_section.dart';
import 'package:localailine/ui/shell.dart';
import 'package:provider/provider.dart';

/// Pictures of the desktop app for the README, drawn through the real app (sidebar, top bar, pages)
/// with demo data only: a temporary database, a fictional owner (Alex Morgan), fictional businesses
/// and callers, and UK drama numbers (07700 900xxx, 020 7946 0xxx). Nothing is called, started or
/// downloaded, and Ollama is never asked.
///
///   SHOTS=../docs/screenshots flutter test test/screenshots_test.dart
/// (or tool/screenshots.sh, which also makes the website pictures and shrinks them).
void main() {
  final shots = Platform.environment['SHOTS'];

  testWidgets('README pictures of the desktop app', (t) async {
    await t.runAsync(_fonts);
    const size = Size(1440, 900);
    await t.binding.setSurfaceSize(size);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    late _DemoState s;
    late HostServer host;
    await t.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('ll_shots');
      s = _DemoState('${tmp.path}/localailine.db');
      s.db = await Db.open(path: s.dbPath);
      await _seed(s, tmp);
      // Pairing works on the main computer: a real (temporary) companion server on a free port.
      host = HostServer(s.db, hostName: 'Studio Mac', handlers: const {});
      await host.start(port: 0, discovery: false);
      s.host = host;
    });
    addTearDown(() => t.runAsync(() async => host.stop()));

    final key = GlobalKey();
    Future<void> settle([int rounds = 8]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> shot(String name) async {
      await settle();
      expect(find.byType(ErrorWidget), findsNothing);
      if (shots == null) return;
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(shots).createSync(recursive: true);
        File('$shots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: s,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: s.messenger,
          navigatorKey: s.navigator,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: const Shell(),
        ),
      ),
    ));

    Future<void> scrollTo(Finder f) async {
      await settle(4);
      await t.ensureVisible(f);
      final pos = Scrollable.of(t.element(f)).position;
      pos.jumpTo((pos.pixels - 24).clamp(0, pos.maxScrollExtent));
      await t.pump();
    }

    // Home: Ava answering, the latest calls.
    await t.runAsync(() => s.db.raw.update('lines', {'status': 'connected'}, where: "provider = 'twilio'"));
    s.go(PageId.home);
    await shot('app-home');

    // Calls: two calls streaming word by word, and the conversations that just ended.
    _startLiveCalls(s);
    s.go(PageId.calls);
    await shot('app-calls-live');

    // Call flow: the restaurant team, fitted to the canvas.
    await t.runAsync(() => s.setAdvanced(true));
    s.go(PageId.agents);
    await scrollTo(find.text('Calls at the same time'));
    await shot('app-call-flow');

    // My assistant.
    s.go(PageId.assistant);
    await shot('app-assistant');
    await t.runAsync(() => s.setAdvanced(false));

    // Build an app: your apps and the ready-made ones.
    s.go(PageId.builder);
    await shot('app-builder');

    // Phone line (the account checked; answering here).
    await t.runAsync(() => s.db.raw.update('lines', {'status': 'verified'}, where: "provider = 'twilio'"));
    s.go(PageId.lines);
    await shot('app-phone-line');

    // Settings → AI engines (built into LocalAILine, running).
    s.go(PageId.settings);
    await shot('app-ai-engines');

    // Calls → Tests: the phone-call test scenarios.
    s.callsFilter = 'test';
    s.go(PageId.home);
    await settle(2);
    s.go(PageId.calls);
    await settle();
    await scrollTo(find.byType(TestRunsSection));
    await shot('app-test-runs');

    // Done: no timers left behind.
    s.liveCalls.clear();
    s.liveText.clear();
    await t.pumpWidget(const SizedBox());
    await settle(2);
  }, skip: shots == null);
}

/// The app's own fonts and Material icons, so text and icons are drawn as in the app (not blocks).
Future<void> _fonts() async {
  for (final (family, files) in [
    ('Plex', ['IBMPlexSans.ttf']),
    ('Bricolage', ['BricolageGrotesque.ttf']),
    ('PlexMono', ['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Medium.ttf']),
  ]) {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final material = '$root/bin/cache/artifacts/material_fonts';
  final icons = File('$material/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) throw StateError('Material icons font not found at ${icons.path}: set FLUTTER_ROOT.');
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  // Roboto: what Flutter falls back to for a character the app's fonts don't have.
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('$material/$f');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await roboto.load();
  // "serif" (the template cards' headings in elegant styles): what macOS draws for it.
  final serif = FontLoader('serif');
  for (final f in ['/System/Library/Fonts/Supplemental/Times New Roman.ttf', '/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf']) {
    if (File(f).existsSync()) serif.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await serif.load();
  for (final f in ['/System/Library/Fonts/Supplemental/Arial Unicode.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']) {
    if (File(f).existsSync()) {
      await (FontLoader('ShotSymbols')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())))).load();
      break;
    }
  }
}

/// The app's theme; characters its fonts don't have (♪, ▍) come from a system font, as in the app.
ThemeData _theme(Brightness b) {
  final th = buildTheme(b);
  return th.copyWith(
    textTheme: th.textTheme.apply(fontFamilyFallback: const ['ShotSymbols']),
    primaryTextTheme: th.primaryTextTheme.apply(fontFamilyFallback: const ['ShotSymbols']),
  );
}

/// The app with nothing outside it: no Ollama, no engine, no downloads.
class _DemoState extends AppState {
  _DemoState(String path) : super(dbPath: path);

  @override
  Future<void> refreshEngine() async {
    await Future<void>.delayed(Duration.zero); // (as the real one: never while a page is being drawn)
    engineChecked = true;
    notifyListeners();
  }
}

/// Apps shown as running (their websites are pictured separately, from real servers).
class _DemoApps extends AppsManager {
  _DemoApps(super.db, super.mcp) : super(ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
  @override
  AppRun runOf(int id) => AppRun.running;
}

/// Hearing and voice installed and downloaded.
class _DemoSpeech implements Speech {
  @override
  Future<String?> whisperBinary() async => '/opt/homebrew/bin/whisper-cli';
  @override
  Future<String?> piperBinary() async => '/opt/homebrew/bin/piper';
  @override
  String? sttModelPath(String id) => '/models/stt/$id';
  @override
  String? ttsVoicePath(String id) => '/models/tts/$id.onnx';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _seed(_DemoState s, Directory tmp) async {
  final db = s.db;
  final now = DateTime.now();
  int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

  s.catalog = await Catalog.load();
  s.speech = _DemoSpeech();
  s.auth = AuthService(db);
  s.mcp = McpManager(db, openBrowser: (_) async {});
  s.knowledge = KnowledgeService(db);
  s.apps = _DemoApps(db, s.mcp)..addListener(s.refresh);
  s.hardware = Hardware(os: 'macOS 15.5', cpu: 'Apple M3 Pro', cores: 12, ramGb: 36, gpu: 'Apple M3 Pro', vramGb: 0, unifiedMemory: true, freeDiskGb: 412);
  s
    ..gate = Gate.app
    ..answering = true
    ..lines = 4
    ..recordCalls = true;

  // The owner.
  final uid = await db.insert('users', {'name': 'Alex Morgan', 'username': 'alex', 'role': 'owner', 'pw_hash': '-', 'created_at': ago(const Duration(days: 30))});
  s.user = User(uid, 'Alex Morgan', 'alex', Role.owner);
  await db.seedDefaults('Alex Morgan');

  // The AI: LocalAILine's own engine, running Qwen3 4B.
  final rec = BuiltinEngine.recommend(s.hardware);
  Directory('${tmp.path}/models/llm').createSync(recursive: true);
  File('${tmp.path}/models/llm/${rec.file}').writeAsStringSync('demo');
  Directory('${tmp.path}/bin').createSync(recursive: true);
  File('${tmp.path}/bin/llama-server').writeAsStringSync('demo');
  s
    ..llmSource = 'builtin'
    ..builtinModel = rec.id;
  s.builtin
    ..state = EngineRun.running
    ..runningLines = 4
    ..ctxPerSlot = 16384;

  // Ava answers for Trattoria Bella, with a team behind her (the call flow).
  final ava = (await db.all('agents', where: "handles = 'incoming'")).first;
  await db.update('agents', ava['id'] as int, {
    'greeting': 'Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?',
    'instructions': 'You answer the phone for Trattoria Bella, an Italian restaurant on Harbour Street. Take table bookings and food orders '
        '(collection, delivery or to a table) with the restaurant\'s system. Be warm and quick, like a good host. '
        'For more than 8 people, take their name and number: the manager calls back.',
  });
  await s.setUpTeam(businessTemplates.firstWhere((b) => b.id == 'restaurant'));

  // What she knows.
  for (final (name, path, files, chunks) in [
    ('Menu & allergens', '~/Documents/Trattoria Bella/Menu 2026.pdf', 1, 42),
    ('Opening hours & delivery area', '~/Documents/Trattoria Bella/FAQ.docx', 1, 12),
  ]) {
    await db.insert('knowledge', {'name': name, 'path': path, 'scope': 'all', 'status': 'ready', 'kind': 'file', 'files': files, 'chunks': chunks, 'indexed_at': ago(const Duration(hours: 3))});
  }

  // Two apps made from templates (their own websites and manager pages).
  for (final (i, id) in ['restaurant', 'barber'].indexed) {
    final tpl = appTemplates.firstWhere((x) => x.id == id);
    final spec = AppSpec.fromJson({...tpl.spec, 'features': {'website': true, 'ava': true}});
    await db.insert('apps', {
      'name': spec.name, 'request': tpl.blurb, 'spec': jsonEncode(spec.toJson()), 'port': 8790 + i, 'pin': '482913', 'status': 'running',
      'created_at': ago(Duration(days: 9 - i)), 'updated_at': ago(Duration(days: 1 + i)),
    });
  }

  // A phone line (Twilio), answering here.
  await db.insert('lines', {
    'provider': 'twilio', 'label': 'Twilio', 'number': '+442079460123',
    'config': jsonEncode({'sid': 'AC00000000000000000000000000000000', 'number': '+442079460123', 'inbound': true}), 'status': 'verified',
  });
  await db.insert('lines', {'provider': 'fxo', 'label': 'Landline (FXO box)', 'number': '020 7946 0456', 'config': jsonEncode({'host': '192.168.1.40', 'number': '020 7946 0456'}), 'status': 'saved'});
  await db.insert('devices', {'name': 'Alex’s iPhone', 'platform': 'ios', 'token_hash': 'demo-1', 'created_at': ago(const Duration(days: 12)), 'last_seen': ago(const Duration(minutes: 4)), 'ring': 1});
  await db.insert('devices', {'name': 'Front desk iPad', 'platform': 'ios', 'token_hash': 'demo-2', 'created_at': ago(const Duration(days: 6)), 'last_seen': ago(const Duration(hours: 2)), 'ring': 0});

  // Calls Ava took, and one she made.
  List<Map<String, Object?>> turns(List<String> lines) => [for (final (i, l) in lines.indexed) {'who': i.isEven ? 'ai' : 'them', 'text': l}];
  final calls = [
    ('incoming', 'Sophie Turner', '+447700900123', 14, 212, 'Answered', 'Booked a table for 4 on Saturday at 19:30 (birthday). Window table requested.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Hi, can I book a table for four this Saturday, about half seven?', 'Of course. Saturday at 19:30 for four — I have a window table free. Can I take your name?', 'Sophie Turner. It’s my husband’s birthday.', 'Lovely! Booked: Saturday 19:30, four people, window table, and I’ve noted the birthday. See you then!']),
    ('incoming', 'Daniel Price', '+447700900456', 38, 164, 'Answered', 'Ordered 2 Margherita and a Tiramisù for collection at 18:15 (£28.00).',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Hiya, I’d like to order for collection please.', 'Sure — what would you like?', 'Two Margheritas and a tiramisù.', 'That’s £28.00, ready at 18:15. Name for the order?']),
    ('outgoing', 'Harbour Wines', '020 7946 0871', 95, 128, 'Answered', 'Delivery of the Chianti moved to Thursday morning; no extra charge.',
        ['Hi, I’m Alex Morgan’s AI assistant, calling on behalf of Trattoria Bella.', 'Hello, Harbour Wines, how can I help?']),
    ('incoming', 'Unknown caller', '+447700900789', 160, 41, 'Screened', 'Sales call about card machines. Took a message, no follow-up needed.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Hi, I’m calling about your card payment fees…']),
    ('incoming', 'Grace Okafor', '+447700900321', 300, 186, 'Answered', 'Asked about gluten-free pizza; booked for 2 on Friday at 20:00.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Do you do gluten-free pizza?']),
    ('incoming', 'Tom Hughes', '+447700900654', 1440, 97, 'Answered', 'Passed to Paolo: private dining for 18 on 14 November. Paolo is sending a quote.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'We’re looking at a team dinner for about eighteen people.']),
  ];
  for (final (dir, name, number, mins, secs, outcome, summary, lines) in calls) {
    await db.insert('calls', {
      'direction': dir, 'name': name, 'number': number, 'line': '+44 20 7946 0123', 'started_at': ago(Duration(minutes: mins)), 'duration_s': secs,
      'outcome': outcome, 'summary': summary, 'transcript': jsonEncode(turns(lines)),
    });
  }
  // What callers asked for.
  for (final (kind, name, phone, summary, agent, status, mins) in [
    ('booking', 'Sophie Turner', '07700 900123', 'Table for 4 · Saturday 19:30 · window · birthday', 'Lily', 'new', 14),
    ('order', 'Daniel Price', '07700 900456', '2 × Margherita, 1 × Tiramisù · collection 18:15 · £28.00', 'Sam', 'new', 38),
    ('message', 'Tom Hughes', '07700 900654', 'Private dining for 18 on 14 November: please send a quote with the set menu', 'Paolo', 'done', 1440),
  ]) {
    await db.insert('requests', {'kind': kind, 'name': name, 'phone': phone, 'summary': summary, 'agent': agent, 'status': status, 'created_at': ago(Duration(minutes: mins))});
  }

  // Finished conversations, still readable under the live calls.
  s.recentLive.add((
    room: 'pstn-in-0-_+447700900321_a',
    number: '+447700900321',
    ended: now.subtract(const Duration(minutes: 5)),
    lines: [
      LiveLine('ai', 'Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', name: 'Ava', done: true),
      LiveLine('caller', 'Do you do gluten-free pizza? And is there a table for two on Friday at eight?', done: true),
      LiveLine('ai', 'We do — any pizza on a gluten-free base for £2 more. Friday at 20:00 for two is free; shall I book it?', name: 'Ava', done: true),
      LiveLine('caller', 'Yes please, it’s Grace Okafor.', done: true),
      LiveLine('ai', 'Done: Friday at 20:00 for two, under Grace. See you then!', name: 'Ava', done: true),
    ],
  ));

  // Test scenario results (Calls → Tests).
  final runs = Directory('${tmp.path}/test-runs')..createSync();
  final results = <Map<String, Object?>>[];
  final cases = [
    ('restaurant', 'book_table', 'team', 'chatty', true, 'A table for two on Saturday at 7pm, please.', null),
    ('restaurant', 'order_delivery', 'solo', 'terse', true, 'Two Diavola for delivery to 4 Quay Road, HB1 2CD.', null),
    ('restaurant', 'cancel_booking', 'team', 'polite', true, 'I need to cancel my booking for Friday, it’s under Priya.', null),
    ('restaurant', 'allergy_question', 'solo', 'chatty', true, 'Is the fritto misto OK for someone with a nut allergy?', null),
    ('barber', 'book', 'team', 'chatty', true, 'Can I get a skin fade with Tony on Saturday at 10?', null),
    ('barber', 'move_booking', 'solo', 'hurried', true, 'Can I move my 3 o’clock to 4?', null),
    ('barber', 'price_question', 'team', 'terse', true, 'How much is a cut and beard?', null),
    ('hotel', 'book_room', 'solo', 'polite', true, 'Do you have a double room for two nights from the 12th?', null),
    ('hotel', 'journey_change_dates', 'team', 'chatty', false, 'We’d like to arrive a day later, on the 13th instead.', 'check_out: expected "2026-10-15", website has "2026-10-14"'),
    ('garage', 'book_mot', 'solo', 'terse', true, 'MOT for a 2016 Ford Focus next Tuesday.', null),
    ('shop', 'order_collect', 'team', 'polite', true, 'Can I order two loaves of sourdough to collect at 5?', null),
    ('clinic', 'book_checkup', 'solo', 'anxious', true, 'I haven’t been to a dentist in years, can I book a check-up?', null),
    ('gym', 'class_signup', 'team', 'chatty', true, 'Is there space in HIIT blast on Tuesday morning?', null),
    ('events', 'buy_tickets', 'solo', 'hurried', false, 'Four tickets for the jazz night on Friday.', 'tickets: expected 4, website has 2'),
  ];
  for (final (i, (app, intent, setup, style, pass, said, failure)) in cases.indexed) {
    results.add({
      'id': '$app-${(i * 37 + 11).toString().padLeft(4, '0')}', 'app': app, 'intent': intent, 'setup': setup, 'style': style, 'pass': pass, 'seconds': 28 + (i * 13) % 41,
      'failures': [?failure],
      'calls': [
        {
          'from': 'A', 'seconds': 28 + (i * 13) % 41,
          'turns': ['AI: Hi, thanks for calling. How can I help?', 'CALLER: $said', 'AI: Of course — let me check that for you.'],
          'tools': ['check_availability({}) → Free.'], 'passed_to': [],
        },
      ],
    });
  }
  File('${runs.path}/results.jsonl').writeAsStringSync(results.map(jsonEncode).join('\n'));
}

/// Two calls on the line: one caller still speaking, one answer being written word by word.
void _startLiveCalls(AppState s) {
  const a = 'pstn-in-0-_+447700900218_a', b = 'pstn-in-1-_+447700900574_b';
  s.liveText[a] = [LiveLine('ai', 'Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', name: 'Ava', done: true)];
  s.liveCallerTurn(a, 'Hi, could I order two Diavola and a garlic focaccia for delivery?');
  s.liveAi(a, 'Of course! Two Diavola and a garlic focaccia, that’s £31.00. ');
  s.liveAi(a, 'What’s the address and postcode for the delivery?');
  s.liveAiDone(a);
  s.liveCaller(a, '4 Quay Road, HB1');

  s.liveText[b] = [LiveLine('ai', 'Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', name: 'Ava', done: true)];
  s.liveCallerTurn(b, 'Hello, I’d like to book a table for six on Friday evening, it’s for my mum’s birthday.');
  s.liveAi(b, 'How lovely! One moment while I pass you to Lily, who looks after our bookings. [voice:af_bella|Lily] ');
  s.liveAiDone(b);
  s.liveAi(b, 'Hi, it’s Lily. Friday for six — would 19:00 or 20:30 suit you better? I can also ');
}
