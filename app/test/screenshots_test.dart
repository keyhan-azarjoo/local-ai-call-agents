import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_data.dart';
import 'package:localailine/services/apps/app_server.dart';
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
import 'package:localailine/services/voice_engine.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine/theme/tokens.dart';
import 'package:localailine/ui/shell.dart';
import 'package:provider/provider.dart';

/// Pictures of the desktop app for the README, drawn through the real app (sidebar, top bar, pages)
/// with demo data only: a temporary database, the owner (Keyhan Azarjoo), fictional businesses and
/// callers, and UK drama numbers (07700 900xxx, 020 7946 0xxx). Nothing is called, started or
/// downloaded, and Ollama is never asked. "Show all features" is on, so the tabs inside My
/// assistant, Phone line and Settings show.
///
///   SHOTS=../docs/screenshots flutter test test/screenshots_test.dart
/// (or tool/screenshots.sh, which also makes the website pictures and shrinks them).
void main() {
  final shots = Platform.environment['SHOTS'];

  testWidgets('README pictures of the desktop app', (t) async {
    await t.runAsync(_fonts);
    const size = Size(1440, 960);
    Future<void> resize(Size to) async {
      await t.binding.setSurfaceSize(to);
      t.view.physicalSize = to;
      await t.pump();
    }

    await resize(size);
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

    // Every picture with "Show all features" on.
    await t.runAsync(() => s.setAdvanced(true));

    // Home: Ava answering, the latest calls.
    await t.runAsync(() => s.db.raw.update('lines', {'status': 'connected'}, where: "provider = 'twilio'"));
    s.go(PageId.home);
    await shot('app-home');

    // Calls: two calls streaming word by word, and the conversations that just ended.
    _startLiveCalls(s);
    s.go(PageId.calls);
    await shot('app-calls-live');

    // My assistant → Call flow: both lines, the receptionist, four specialists and the manager.
    // (A taller picture: the tabs, the whole canvas and the note under it.)
    await resize(const Size(1440, 1040));
    s.go(PageId.agents);
    await shot('app-call-flow');

    // One specialist opened: what she may use (abilities, systems, skills, documents).
    await t.tap(find.text('Lily'));
    await settle();
    await t.runAsync(() => Scrollable.ensureVisible(t.element(find.text('What this agent may use'))));
    await shot('app-agent-editor');
    await t.tap(find.text('Cancel'));
    await settle(4);
    await resize(size);

    // My assistant → Ava.
    s.go(PageId.assistant);
    await shot('app-assistant');

    // My assistant → Skills.
    s.go(PageId.skills);
    await shot('app-skills');

    // My assistant → Knowledge.
    s.go(PageId.knowledge);
    await shot('app-knowledge');

    // My assistant → Tools: the restaurant app's two MCP servers, two connectors, and the ready ones.
    s.go(PageId.tools);
    await shot('app-tools');

    // The tools the restaurant app gives callers (its customers' MCP server, opened).
    await t.tap(find.textContaining(RegExp(r'^Show \d+ tools$')).first);
    await shot('app-mcp-tools');

    // Build an app: your apps and the ready-made ones.
    s.go(PageId.builder);
    await shot('app-builder');

    // Phone line: Twilio answering here, and a landline through a gateway box on this network.
    await t.runAsync(() => s.db.raw.update('lines', {'status': 'verified'}, where: "provider = 'twilio'"));
    s.voice = VoiceEngine(dataDir: Directory.systemTemp.path, appUrl: 'http://127.0.0.1:9', appKey: 'demo')..lanIp = '192.168.1.20';
    s.go(PageId.lines);
    await shot('app-phone-line');
    s.voice = null;

    // Settings → AI engines (built into LocalAILine, running).
    s.go(PageId.settings);
    await shot('app-ai-engines');

    // Calls → Tests: the phone-call test scenarios.
    s.callsFilter = 'test';
    s.go(PageId.home);
    await settle(2);
    s.go(PageId.calls);
    await settle();
    await scrollTo(find.text('Made by AI'));
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

/// Tools shown connected, with the tools they listed when added; nothing is contacted.
class _DemoMcp extends McpManager {
  _DemoMcp(super.db) : super(openBrowser: (_) async {});
  @override
  Future<void> connect(int id, {bool interactive = false}) async {
    status[id] = McpStatus.connected;
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
  s.mcp = _DemoMcp(db);
  s.knowledge = KnowledgeService(db, ollama: 'http://127.0.0.1:9'); // (never asked: nothing is indexed here)
  s.apps = _DemoApps(db, s.mcp)..addListener(s.refresh);
  s.hardware = Hardware(os: 'macOS 15.5', cpu: 'Apple M3 Pro', cores: 12, ramGb: 36, gpu: 'Apple M3 Pro', vramGb: 0, unifiedMemory: true, freeDiskGb: 412);
  s
    ..gate = Gate.app
    ..answering = true
    ..lines = 4
    ..recordCalls = true;

  // The owner.
  const owner = 'Keyhan Azarjoo';
  final uid = await db.insert('users', {'name': owner, 'username': 'keyhan', 'role': 'owner', 'pw_hash': '-', 'created_at': ago(const Duration(days: 30))});
  s.user = User(uid, owner, 'keyhan', Role.owner);
  await db.seedDefaults(owner);

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

  // Two apps made from templates (their own websites and manager pages).
  final appIds = <int>[];
  for (final (i, id) in ['restaurant', 'barber'].indexed) {
    final tpl = appTemplates.firstWhere((x) => x.id == id);
    final spec = AppSpec.fromJson({...tpl.spec, 'features': {'website': true, 'ava': true}});
    appIds.add(await db.insert('apps', {
      'name': spec.name, 'request': tpl.blurb, 'spec': jsonEncode(spec.toJson()), 'port': 8790 + i, 'pin': '482913', 'status': 'running',
      'created_at': ago(Duration(days: 9 - i)), 'updated_at': ago(Duration(days: 1 + i)),
    }));
  }

  // Tools: Trattoria Bella's own two MCP servers (what callers may do, and the manager's), with
  // the tools the app really offers, and two ready connectors.
  final bella = AppSpec.fromJson({...appTemplates.firstWhere((x) => x.id == 'restaurant').spec, 'features': {'website': true, 'ava': true}});
  final bellaServer = AppServer(data: AppData(db, appIds.first, bella), pin: '482913');
  Future<int> server(String name, String kind, String target, String scope, String auth, Map<String, Object?> secret, List<Map<String, Object?>> tools) =>
      db.insert('mcp_servers', {
        'name': name, 'kind': kind, 'target': target, 'scope': scope, 'auth_mode': auth, 'secret': jsonEncode(secret), 'enabled': 1,
        'status': 'connected', 'tools': jsonEncode(tools),
      });
  Map<String, Object?> tool(String name, String description, {bool readOnly = true}) =>
      {'name': name, 'description': description, 'inputSchema': {'type': 'object', 'properties': {}}, 'annotations': {'readOnlyHint': readOnly}};
  final customers = await server('Trattoria Bella', 'http', 'http://127.0.0.1:8790/mcp', 'all', 'token', {'app': appIds.first, 'role': 'customers'},
      [for (final x in bellaServer.mcpTools(manager: false)) x.toJson()]);
  await server('Trattoria Bella (manager)', 'http', 'http://127.0.0.1:8790/mcp/manager', 'me', 'token', {'app': appIds.first, 'role': 'manager', 'header': 'X-Key', 'value': '482913'},
      [for (final x in bellaServer.mcpTools(manager: true)) x.toJson()]);
  final square = await server('Square', 'http', 'https://mcp.squareup.com/mcp', 'me', 'auto', {}, [
    tool('list_payments', 'Lists card payments taken on the till, newest first.'),
    tool('get_order', 'Shows one order with its items, total and status.'),
    tool('list_gift_cards', 'Lists gift cards and their balances.'),
    tool('create_gift_card', 'Creates a gift card for an amount (creates a record).', readOnly: false),
    tool('refund_payment', 'Refunds all or part of a payment (writes data).', readOnly: false),
  ]);
  await server('Google Calendar', 'http', 'https://calendarmcp.googleapis.com/mcp/v1', 'me', 'auto', {}, [
    tool('list_events', 'Lists events in your calendars between two dates.'),
    tool('find_free_time', 'Finds free time across your calendars.'),
    tool('create_event', 'Creates a calendar event (creates a record).', readOnly: false),
    tool('update_event', 'Moves or changes an event (updates a record).', readOnly: false),
  ]);

  // What the team knows: documents, a shared folder, and the documents behind three skills.
  Future<int> source(String name, String path, String kind, int files, int chunks, Duration age) => db.insert('knowledge', {
        'name': name, 'path': path, 'scope': 'all', 'status': 'ready', 'kind': kind, 'files': files, 'chunks': chunks, 'indexed_at': ago(age),
      });
  final skillIds = <int>[];
  for (final (name, file, about, instructions, chunks) in [
    ('Trattoria Bella house guide', 'House guide.pdf', 'How we greet, seat and take orders: house rules, specials and the tone of a good host.',
        'Greet like a host, not a call centre. Offer the window or terrace when free. Mention the day’s special once. Tables are held for 15 minutes.', 14),
    ('Handling complaints', 'Complaints.docx', 'Listen, apologise once, offer what the rules allow, and pass serious ones to Paolo.',
        'Let the caller finish. Apologise once, plainly. Offer a free dessert or 10% off the next visit for a late or wrong order. Anything else, or an upset caller: pass to Paolo.', 9),
    ('Allergies & dietary needs', 'Allergens.pdf', 'Checks each dish against the 14 allergens; never guesses, and offers to ask the kitchen.',
        'Answer from the allergen chart only. Never say a dish is safe for an allergy if the chart does not say so: offer to ask the kitchen and call back. Always note allergies on the booking.', 11),
  ]) {
    final src = await source('Skill: $name', '~/Documents/Trattoria Bella/Skills/$file', 'file', 1, chunks, const Duration(days: 3));
    skillIds.add(await db.insert('skills', {'name': name, 'description': about, 'instructions': instructions, 'source_id': src, 'enabled': 1}));
  }
  final [houseGuide, complaints, allergies] = skillIds;
  // (Listed newest first: the menu at the top.)
  final policies = await source('Staff handbook & policies', '~/Documents/Trattoria Bella/Policies', 'folder', 7, 164, const Duration(days: 1));
  final events = await source('Private dining & events pack', '~/Documents/Trattoria Bella/Private dining 2026.pdf', 'file', 1, 26, const Duration(days: 1, hours: 3));
  final wine = await source('Wine list', '~/Documents/Trattoria Bella/Wine list.pdf', 'file', 1, 18, const Duration(hours: 6));
  final faq = await source('Opening hours & delivery area', '~/Documents/Trattoria Bella/FAQ.docx', 'file', 1, 12, const Duration(hours: 3));
  final menu = await source('Menu & allergens', '~/Documents/Trattoria Bella/Menu 2026.pdf', 'file', 1, 42, const Duration(hours: 2));

  // Phones paired with this computer.
  final iphone = await db.insert('devices', {'name': 'Keyhan’s iPhone', 'platform': 'ios', 'token_hash': 'demo-1', 'created_at': ago(const Duration(days: 12)), 'last_seen': ago(const Duration(minutes: 4)), 'ring': 1});
  await db.insert('devices', {'name': 'Front desk iPad', 'platform': 'ios', 'token_hash': 'demo-2', 'created_at': ago(const Duration(days: 6)), 'last_seen': ago(const Duration(hours: 2)), 'ring': 0});

  // The call flow: Ava answers for Trattoria Bella and passes calls to four specialists, who can
  // pass them on to Paolo, the manager (rung on his phone).
  final ava = (await db.all('agents', where: "handles = 'incoming'")).first['id'] as int;
  Future<int> agent(String name, String role, String when, String voice, String instructions, Map<String, Object?> access) => db.insert('agents', {
        'name': name, 'role': role, 'greeting': '', 'instructions': instructions, 'language': 'English', 'voice': voice,
        'handles': 'handoff', 'transfer_when': when, 'access': jsonEncode(access), 'enabled': 1,
      });
  final paolo = await db.insert('agents', {
    'name': 'Paolo', 'role': 'Manager (person)', 'greeting': '', 'instructions': '', 'language': 'English', 'handles': 'human',
    'transfer_when': 'The caller asks for the manager, or it needs a person.', 'access': jsonEncode({'device': iphone, 'number': '07700 900888'}), 'enabled': 1,
  });
  final lily = await agent('Lily', 'Bookings', 'Booking, moving or cancelling a table.', 'kokoro:bf_emma',
      'You are Lily, who looks after table bookings at Trattoria Bella. Check what is free with the booking system before offering a time, '
          'read the booking back (day, time, people, name), and note birthdays, high chairs and allergies. Up to 8 people; more goes to Marco.',
      {'abilities': ['booking'], 'tools': [customers], 'skills': [houseGuide, allergies], 'docs': [menu, faq], 'passTo': [paolo]});
  final sam = await agent('Sam', 'Orders', 'A takeaway or delivery order.', 'kokoro:bm_george',
      'You are Sam, who takes collection and delivery orders. Read each item and the total back, check the postcode is in the delivery area, '
          'and give a ready time. Ask about allergies before you confirm.',
      {'abilities': ['order'], 'tools': [customers], 'skills': [allergies], 'docs': [menu, faq], 'passTo': [paolo]});
  final marco = await agent('Marco', 'Events & sales', 'Private dining, parties or gift vouchers.', 'kokoro:bm_fable',
      'You are Marco, who sells private dining, parties and gift vouchers. Find the date, the number of guests and the budget, '
          'suggest a set menu from the events pack, and hold the date while Paolo sends a quote.',
      {'abilities': ['booking', 'message'], 'tools': [customers, square], 'skills': [houseGuide], 'docs': [events, wine, menu], 'passTo': [paolo]});
  final nina = await agent('Nina', 'Customer care', 'A complaint, allergy question or lost item.', 'kokoro:bf_isabella',
      'You are Nina, who looks after customers when something went wrong or they need care: complaints, allergy questions and lost property. '
          'Be calm and kind; follow the complaints and allergy skills exactly.',
      {'abilities': ['message'], 'tools': [customers], 'skills': [complaints, allergies], 'docs': [menu, policies], 'passTo': [paolo]});
  await db.update('agents', ava, {
    'greeting': 'Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?',
    'voice': 'en_GB-alba-medium',
    'instructions': 'You answer the phone for Trattoria Bella, an Italian restaurant on Harbour Street. Find out what the caller needs and pass them '
        'to the right person: Lily for tables, Sam for takeaway and delivery, Marco for private dining and vouchers, Nina when something went wrong. '
        'Answer simple questions (opening hours, where we are, parking) yourself. Be warm and quick, like a good host.',
    'access': jsonEncode({'abilities': ['message'], 'passTo': [lily, sam, marco, nina, paolo]}),
  });
  await db.setSetting('flow.layout', jsonEncode({
    '$ava': [270, 245], '$lily': [600, 20], '$sam': [600, 170], '$marco': [600, 320], '$nina': [600, 470], '$paolo': [930, 245],
  }));

  // A phone line (Twilio), answering here, and the restaurant's landline through a gateway box.
  await db.insert('lines', {
    'provider': 'twilio', 'label': 'Twilio', 'number': '+442079460123',
    'config': jsonEncode({'sid': 'AC00000000000000000000000000000000', 'number': '+442079460123', 'inbound': true}), 'status': 'verified',
  });
  await db.insert('lines', {
    'provider': 'fxo', 'label': 'Landline (FXO box)', 'number': '020 7946 0456',
    'config': jsonEncode({'host': '192.168.1.40', 'number': '020 7946 0456', 'inbound': true, 'sipUser': 'landline2', 'sipPass': 'q7Rk2mVx9TbL4wZp'}), 'status': 'verified',
  });

  // Calls the team took, and one Max made (oldest first: the newest are listed first).
  List<Map<String, Object?>> turns(List<String> lines) => [for (final (i, l) in lines.indexed) {'who': i.isEven ? 'ai' : 'them', 'text': l}];
  final calls = [
    ('incoming', 'Tom Hughes', '+447700900654', 1440, 97, 'Answered', 'Passed to Marco: private dining for 18 on 14 November. Paolo is sending a quote.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'We’re looking at a team dinner for about eighteen people.']),
    ('incoming', 'Grace Okafor', '+447700900321', 300, 186, 'Answered', 'Asked about gluten-free pizza; Lily booked 2 for Friday at 20:00.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Do you do gluten-free pizza?']),
    ('incoming', 'Unknown caller', '+447700900789', 160, 41, 'Screened', 'Sales call about card machines. Took a message, no follow-up needed.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Hi, I’m calling about your card payment fees…']),
    ('outgoing', 'Harbour Wines', '020 7946 0871', 95, 128, 'Answered', 'Delivery of the Chianti moved to Thursday morning; no extra charge.',
        ['Hi, I’m Keyhan Azarjoo’s AI assistant, calling on behalf of Trattoria Bella.', 'Hello, Harbour Wines, how can I help?']),
    ('incoming', 'Daniel Price', '+447700900456', 38, 164, 'Answered', 'Sam took 2 Margherita and a Tiramisù for collection at 18:15 (£28.00).',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Hiya, I’d like to order for collection please.', 'Sure — what would you like?', 'Two Margheritas and a tiramisù.', 'That’s £28.00, ready at 18:15. Name for the order?']),
    ('incoming', 'Sophie Turner', '+447700900123', 14, 212, 'Answered', 'Lily booked a table for 4 on Saturday at 19:30 (birthday). Window table requested.',
        ['Ciao, thanks for calling Trattoria Bella, this is Ava. How can I help?', 'Hi, can I book a table for four this Saturday, about half seven?', 'Of course. Saturday at 19:30 for four — I have a window table free. Can I take your name?', 'Sophie Turner. It’s my husband’s birthday.', 'Lovely! Booked: Saturday 19:30, four people, window table, and I’ve noted the birthday. See you then!']),
  ];
  for (final (dir, name, number, mins, secs, outcome, summary, lines) in calls) {
    await db.insert('calls', {
      'direction': dir, 'name': name, 'number': number, 'line': '+44 20 7946 0123', 'started_at': ago(Duration(minutes: mins)), 'duration_s': secs,
      'outcome': outcome, 'summary': summary, 'transcript': jsonEncode(turns(lines)),
    });
  }
  // What callers asked for.
  for (final (kind, name, phone, summary, agent, status, mins) in [
    ('message', 'Tom Hughes', '07700 900654', 'Private dining for 18 on 14 November: please send a quote with the set menu', 'Marco', 'done', 1440),
    ('order', 'Daniel Price', '07700 900456', '2 × Margherita, 1 × Tiramisù · collection 18:15 · £28.00', 'Sam', 'new', 38),
    ('booking', 'Sophie Turner', '07700 900123', 'Table for 4 · Saturday 19:30 · window · birthday', 'Lily', 'new', 14),
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
