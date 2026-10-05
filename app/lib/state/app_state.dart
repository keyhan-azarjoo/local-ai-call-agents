import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/auth.dart';
import '../services/agent_loop.dart';
import '../services/catalog.dart';
import '../services/cloud_llm.dart';
import '../services/hardware.dart';
import '../services/ollama.dart';
import '../services/companion/host_client.dart';
import '../services/companion/host_server.dart';
import '../services/mcp/mcp_manager.dart';
import '../services/persona.dart';
import '../services/speech.dart';
import '../services/system.dart';

enum Gate { loading, setup, signIn, app, companion }

/// Every page the app has. Simple mode shows only [simplePages].
enum PageId {
  home('Home'),
  talk('Talk to Ava'),
  chat('Chat'),
  calls('Calls'),
  outbound('Make a call'),
  assistant('My assistant'),
  lines('Phone line'),
  settings('Settings'),
  // Shown with "Show all features":
  agents('Agents'),
  automations('Automations & loops'),
  contacts('Contacts & rules'),
  knowledge('Knowledge'),
  tools('Tools (MCP)'),
  skills('Skills'),
  models('Language models'),
  speech('Voice & hearing'),
  hardware('This computer'),
  voiceServer('Voice server'),
  devices('Paired devices'),
  users('Users & access'),
  logs('Activity & logs');

  const PageId(this.title);
  final String title;
}

const simplePages = [
  PageId.home,
  PageId.chat,
  PageId.talk,
  PageId.calls,
  PageId.outbound,
  PageId.assistant,
  PageId.lines,
  PageId.settings,
];

/// "Show all features" adds tabs inside these pages; the menu never grows.
const hubTabs = <PageId, List<(PageId, String)>>{
  PageId.assistant: [
    (PageId.assistant, 'Ava'),
    (PageId.agents, 'Agents'),
    (PageId.skills, 'Skills'),
    (PageId.knowledge, 'Knowledge'),
    (PageId.tools, 'Tools'),
    (PageId.automations, 'Automations'),
  ],
  PageId.lines: [
    (PageId.lines, 'Lines'),
    (PageId.contacts, 'Contacts & rules'),
    (PageId.voiceServer, 'Voice server'),
    (PageId.devices, 'Paired devices'),
  ],
  PageId.settings: [
    (PageId.settings, 'General'),
    (PageId.models, 'Models'),
    (PageId.speech, 'Voice & hearing'),
    (PageId.hardware, 'This computer'),
    (PageId.users, 'Users'),
    (PageId.logs, 'Activity'),
  ],
};

/// The menu item a page lives under.
PageId parentOf(PageId p) {
  for (final e in hubTabs.entries) {
    if (e.value.any((t) => t.$1 == p)) return e.key;
  }
  return p;
}

class AppState extends ChangeNotifier {
  AppState({this.dbPath});
  final String? dbPath;

  late Db db;
  late AuthService auth;
  late Catalog catalog;
  late Speech speech;
  late McpManager mcp;
  final toolLoop = ToolLoop();

  /// Opens sign-in pages. Tests replace this before [init].
  Future<void> Function(String url) openBrowser = openExternal;
  final ollama = Ollama();
  Hardware? hardware;

  Gate gate = Gate.loading;
  User? user;
  PageId page = PageId.home;
  bool advanced = false;
  ThemeMode themeMode = ThemeMode.light;
  bool answering = true;

  /// Talk page speaks replies out loud.
  bool speakReplies = true;

  /// Which agent "My assistant" edits. null = the incoming receptionist.
  int? editAgentId;

  void editAgent(int? id) {
    editAgentId = id;
    go(PageId.assistant);
  }

  /// Ollama status, refreshed by [refreshEngine].
  String? ollamaVersion;
  List<OllamaModel> installedModels = [];
  List<LoadedModel> loadedModels = [];
  bool engineChecked = false;

  Future<void> refreshEngine() async {
    ollamaVersion = await ollama.version();
    if (ollamaVersion != null) {
      try {
        installedModels = await ollama.installed();
        loadedModels = await ollama.loaded();
      } catch (_) {}
      // Pick the best downloaded model when none is chosen, or the chosen one is gone.
      // A model the user picked by hand is kept as long as it is still downloaded.
      final manual = await db.setting('llm.manual') == '1';
      final missing = llmModel == null || !installedModels.any((m) => m.name == llmModel);
      if (installedModels.isNotEmpty && (missing || !manual)) {
        final pick = catalog.bestInstalled(hardware, installedModels.map((m) => m.name).toList());
        if (pick != null && pick != llmModel) await setLlmModel(pick);
      }
    } else {
      installedModels = [];
      loadedModels = [];
    }
    engineChecked = true;
    notifyListeners();
  }

  // ---------- where the AI runs ----------
  /// 'local' (this computer) or 'cloud' (a provider the user connected).
  String llmSource = 'local';
  CloudConfig? cloud;
  final cloudLlm = CloudLlm();

  bool get usingCloud => llmSource == 'cloud';

  Future<void> setLlmSource(String v) async {
    llmSource = v;
    await db.setSetting('llm.source', v);
    await log(v == 'cloud' ? 'Switched AI to ${cloud?.provider.label ?? 'cloud'}' : 'Switched AI to this computer');
    notifyListeners();
  }

  Future<void> saveCloud(CloudConfig c) async {
    cloud = c;
    await db.setSetting('llm.cloud', jsonEncode(c.toJson()));
    llmSource = 'cloud';
    await db.setSetting('llm.source', 'cloud');
    await log('Connected ${c.provider.label} (${c.model})');
    notifyListeners();
  }

  Future<void> removeCloud() async {
    cloud = null;
    await db.setSetting('llm.cloud', '');
    await setLlmSource('local');
  }

  /// What the AI is thinking with, for status lines.
  String get llmLabel => usingCloud && cloud != null ? '${cloud!.provider.label} · ${cloud!.model}' : (llmModel ?? 'no model');

  /// Chat with the chosen (or given) model, using the right thinking setting.
  Stream<String> chat(List<ChatMessage> messages, {String? model}) {
    if (usingCloud && cloud != null && model == null) return cloudLlm.chat(cloud!, messages);
    final m = model ?? llmModel!;
    final entry = catalog.llm.where((e) => e.id == m).firstOrNull;
    return ollama.chat(m, messages, disableThinking: entry?.think == 'off');
  }

  ModelTarget get modelTarget {
    if (usingCloud && cloud != null) return CloudTarget(cloud!);
    final entry = catalog.llm.where((e) => e.id == llmModel).firstOrNull;
    // Memory left after the model itself decides how much context we can afford.
    final spare = (hardware?.modelBudgetGb ?? 6) - (entry?.sizeGb ?? 4);
    final maxCtx = spare > 6 ? 32768 : spare > 3 ? 16384 : 8192;
    return LocalTarget(llmModel!, disableThinking: entry?.think == 'off', maxCtx: maxCtx);
  }

  /// Tools the AI may use. [scopes]: 'me' (owner), 'contacts', 'all' (any caller).
  Future<List<ToolBinding>> toolsFor(Set<String> scopes) async {
    final out = <ToolBinding>[];
    for (final srv in await mcp.servers()) {
      if (!srv.enabled || !scopes.contains(srv.scope)) continue;
      for (final t in srv.tools) {
        out.add(ToolBinding(serverId: srv.id, serverName: srv.name, tool: t, fnName: ToolBinding.safeName(srv.name, t.name)));
      }
    }
    return out;
  }

  /// One AI reply that may use tools. Falls back to plain chat when there are none.
  Future<String> agentReply(
    List<ChatMessage> messages, {
    required Set<String> scopes,
    required Approver approve,
    void Function(ToolEvent)? onEvent,
  }) async {
    final tools = await toolsFor(scopes);
    final text = await toolLoop.run(
      target: modelTarget,
      messages: messages,
      tools: tools,
      approve: approve,
      runTool: (b, args) => mcp.call(b.serverId, b.tool.name, args),
      onEvent: (e) {
        log('${e.denied ? 'Declined' : 'AI used'} ${e.binding.serverName} › ${e.binding.tool.name}');
        onEvent?.call(e);
      },
    );
    return text;
  }

  bool get llmReady => usingCloud ? (cloud != null && cloud!.model.isNotEmpty) : localReady;

  bool get localReady => ollamaVersion != null && llmModel != null && installedModels.any((m) => m.name == llmModel);

  /// Chosen models.
  String? llmModel;
  String sttModel = 'ggml-base.en.bin';
  String ttsVoice = 'en_GB-alba-medium';

  final messenger = GlobalKey<ScaffoldMessengerState>();
  final navigator = GlobalKey<NavigatorState>();

  // ---------- main computer vs paired device ----------
  /// 'host' = this computer runs LocalAILine; 'companion' = connects to one.
  String? role;
  HostServer? host;
  HostClient? remote;
  String? remoteName;

  /// Set while a call is ringing on this device.
  Map<String, dynamic>? incoming;
  String? ringStatus;

  static bool get isPhone => Platform.isIOS || Platform.isAndroid;
  static String get deviceName {
    final h = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '');
    return isPhone ? '${Platform.isIOS ? 'iPhone' : 'Android'} · $h' : h;
  }

  Future<void> init() async {
    // Debug builds only: LOCALAILINE_DB picks a database file (for development).
    final devDb = kDebugMode ? Platform.environment['LOCALAILINE_DB'] : null;
    db = await Db.open(path: dbPath ?? devDb);
    auth = AuthService(db);
    catalog = await Catalog.load();
    speech = await Speech.create();
    mcp = McpManager(db, openBrowser: (u) => openBrowser(u))..addListener(notifyListeners);
    advanced = await db.setting('ui.advanced') == '1';
    themeMode = await db.setting('ui.theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
    answering = await db.setting('calls.answering') != '0';
    llmModel = await db.setting('llm.model');
    sttModel = await db.setting('stt.model') ?? sttModel;
    ttsVoice = await db.setting('tts.voice') ?? ttsVoice;
    llmSource = await db.setting('llm.source') ?? 'local';
    final cj = await db.setting('llm.cloud');
    cloud = cj == null || cj.isEmpty ? null : CloudConfig.fromJson(jsonDecode(cj) as Map<String, dynamic>);
    if (cloud == null) llmSource = 'local';
    role = await db.setting('app.role');
    if (role == '') role = null;
    gate = await auth.hasOwner() ? Gate.signIn : Gate.setup;
    if (role == 'companion') {
      final base = await db.setting('companion.base'), token = await db.setting('companion.token');
      if (base != null && token != null) {
        remoteName = await db.setting('companion.hostName');
        _startRemote(base, token);
        gate = Gate.companion;
      } else {
        gate = Gate.setup;
      }
    } else if (gate == Gate.signIn && !isPhone) {
      await startHost();
    }
    // Debug builds only, and only together with LOCALAILINE_DB: skip sign-in as this user.
    final devUser = kDebugMode && devDb != null ? Platform.environment['LOCALAILINE_DEV_USER'] : null;
    if (devUser != null) {
      final rows = await db.all('users', where: 'username = ?', args: [devUser]);
      if (rows.isNotEmpty) {
        user = User.fromRow(rows.first);
        gate = Gate.app;
        final devPage = Platform.environment['LOCALAILINE_DEV_PAGE'];
        page = PageId.values.firstWhere((p) => p.name == devPage, orElse: () => PageId.home);
      }
    }
    notifyListeners();
    Hardware.detect().then((h) {
      hardware = h;
      notifyListeners();
      refreshEngine();
    });
  }

  void toast(String msg) {
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void go(PageId p) {
    page = p;
    notifyListeners();
  }

  Future<void> setAdvanced(bool v) async {
    advanced = v;
    if (!v) page = parentOf(page);
    await db.setSetting('ui.advanced', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await db.setSetting('ui.theme', themeMode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setAnswering(bool v) async {
    answering = v;
    await db.setSetting('calls.answering', v ? '1' : '0');
    await log(v ? 'Turned answering on' : 'Turned answering off');
    notifyListeners();
  }

  Future<void> setLlmModel(String m, {bool manual = false}) async {
    llmModel = m;
    await db.setSetting('llm.model', m);
    if (manual) await db.setSetting('llm.manual', '1');
    notifyListeners();
  }

  Future<void> setSttModel(String m) async {
    sttModel = m;
    await db.setSetting('stt.model', m);
    notifyListeners();
  }

  Future<void> setTtsVoice(String v) async {
    ttsVoice = v;
    await db.setSetting('tts.voice', v);
    notifyListeners();
  }

  Future<void> log(String what) => db.audit(user?.name ?? 'System', what);

  // ---------- host side ----------
  Future<void> startHost({int port = companionPort}) async {
    if (host?.running == true) return;
    role = 'host';
    await db.setSetting('app.role', 'host');
    host = HostServer(db, hostName: deviceName, handlers: {
      'status': (_, _) async => {
            'hostName': deviceName,
            'answering': answering,
            'ai': llmReady ? llmLabel : null,
            'agent': (await db.all('agents', where: "handles = 'incoming'", orderBy: 'id')).firstOrNull?['name'] ?? 'Ava',
            'lines': await db.count('lines'),
            'calls': await db.count('calls'),
          },
      'calls': (_, _) async => [
            for (final c in await db.all('calls')) {...c}..remove('transcript')
          ],
      'answering': (_, b) async {
        await setAnswering(b['on'] == true);
        return {'answering': answering};
      },
      'chat': (deviceId, b) async {
        if (!llmReady) throw StateError('The AI isn’t set up on the computer yet.');
        final msgs = [for (final m in (b['messages'] as List)) ChatMessage(m['role'] as String, m['content'] as String)];
        final used = <Map<String, Object?>>[];
        final reply = await agentReply(msgs,
            scopes: {'me', 'contacts', 'all'},
            approve: (t, args) => host!.approveOn(deviceId, t.serverName, t.tool.title ?? t.tool.name, args),
            onEvent: (e) => used.add({'server': e.binding.serverName, 'tool': e.binding.tool.name, 'ok': e.ok, 'denied': e.denied}));
        return {'reply': reply, 'tools': used};
      },
      'talk': (deviceId, b) async => talkTurn(deviceId, b),
    });
    await host!.start(port: port);
    host!.changes.listen((_) => notifyListeners());
    // Debug builds only: a fixed pairing code and an automatic test ring, for device testing.
    if (kDebugMode) {
      final code = Platform.environment['LOCALAILINE_DEV_PAIRCODE'];
      if (code != null) {
        host!.newPairingCode();
        host!.pairingCode = code;
      }
      if (Platform.environment['LOCALAILINE_DEV_RING'] == '1') {
        var seen = 0;
        host!.changes.listen((_) {
          if (host!.live.length > seen) Future.delayed(const Duration(seconds: 4), testRing);
          seen = host!.live.length;
        });
      }
    }
    notifyListeners();
  }

  /// One spoken turn from a paired device: its audio in, Ava's voice out.
  Future<Map<String, Object?>> talkTurn(int deviceId, Map<String, dynamic> b) async {
    if (!llmReady) throw StateError('The AI isn’t set up on the computer yet.');
    final agent = (await db.all('agents', where: "handles = 'incoming'", orderBy: 'id')).firstOrNull;
    final history = [for (final m in (b['history'] as List? ?? [])) ChatMessage(m['role'] as String, m['content'] as String)];
    if (history.isEmpty) history.addAll(Persona.callerStart(agent));
    var heard = (b['text'] as String?)?.trim() ?? '';
    if (b['audio'] != null) {
      final model = speech.sttModelPath(sttModel);
      if (model == null) throw StateError('The computer has no hearing model yet.');
      final f = File('${Directory.systemTemp.path}/ll_in_${DateTime.now().microsecondsSinceEpoch}.wav');
      await f.writeAsBytes(base64Decode(b['audio'] as String));
      heard = await speech.transcribe(f.path, modelPath: model, language: sttModel.contains('.en') ? 'en' : 'auto');
      await f.delete().catchError((_) => f);
    }
    if (heard.isEmpty) return {'heard': '', 'reply': '', 'history': [for (final m in history) m.toJson()]};
    history.add(ChatMessage('user', heard));
    final reply = await agentReply(history,
        scopes: {'all'}, approve: (t, args) => host!.approveOn(deviceId, t.serverName, t.tool.title ?? t.tool.name, args));
    history.add(ChatMessage('assistant', reply));
    final wav = await speech.synthesize(reply, voicePath: speech.ttsVoicePath(ttsVoice));
    return {
      'heard': heard,
      'reply': reply,
      'audio': wav == null ? null : base64Encode(await File(wav).readAsBytes()),
      'history': [for (final m in history) m.toJson()],
    };
  }

  /// Test ring: like a real incoming call, rings paired devices first.
  Future<void> testRing() async {
    if (host == null) return;
    final callId = 'test-${DateTime.now().millisecondsSinceEpoch}';
    final targets = host!.live.length;
    ringStatus = targets == 0 ? null : 'Ringing $targets device${targets == 1 ? '' : 's'}…';
    notifyListeners();
    if (targets == 0) return toast('No paired device is connected. Open LocalAILine on your phone.');
    final a = await host!.ring(callId: callId, from: 'Test call', number: '+44 20 7946 0000', line: 'Test');
    ringStatus = null;
    notifyListeners();
    final what = switch (a.action) {
      'me' => 'Answered on ${a.deviceName}',
      'decline' => 'Declined on ${a.deviceName}',
      _ => a.deviceName == null ? 'No answer — Ava would have answered' : 'Ava answered (chosen on ${a.deviceName})',
    };
    await log('Test ring: $what');
    toast(what);
  }

  // ---------- paired device side ----------
  void _startRemote(String base, String token) {
    remote = HostClient(base, token);
    remote!.onApprove = _approveRemotely;
    remote!.events.listen((e) {
      switch (e['type']) {
        case 'ring':
          incoming = e;
        case 'ring_end':
          if (incoming?['callId'] == e['callId']) incoming = null;
      }
      notifyListeners();
    });
    remote!.connect();
  }

  Future<bool> _approveRemotely(Map<String, dynamic> r) async {
    final ctx = navigator.currentContext;
    if (ctx == null) return false;
    return await showDialog<bool>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: Text('Allow ${r['server']} › ${r['tool']}?'),
            content: Text('Ava wants to run this action:\n${jsonEncode(r['args'])}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Don’t allow')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Allow')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> pairWith(String base, String code) async {
    final r = await HostClient.pair(base, code, deviceName, Platform.operatingSystem);
    role = 'companion';
    remoteName = r.hostName;
    await db.setSetting('app.role', 'companion');
    await db.setSetting('companion.base', base);
    await db.setSetting('companion.token', r.token);
    await db.setSetting('companion.hostName', r.hostName);
    _startRemote(base, r.token);
    gate = Gate.companion;
    notifyListeners();
  }

  Future<void> unpair() async {
    await remote?.close();
    remote = null;
    role = null;
    for (final k in ['app.role', 'companion.base', 'companion.token', 'companion.hostName']) {
      await db.setSetting(k, '');
    }
    gate = await auth.hasOwner() ? Gate.signIn : Gate.setup;
    notifyListeners();
  }

  void answerIncoming(String action) {
    final id = incoming?['callId'] as String?;
    if (id != null) remote?.answer(id, action);
    incoming = null;
    notifyListeners();
  }

  Future<void> completeSetup(User owner) async {
    await db.seedDefaults(owner.name);
    await db.audit(owner.name, 'Created owner account and finished setup');
    user = owner;
    page = PageId.home;
    gate = Gate.app;
    if (!isPhone) await startHost();
    notifyListeners();
  }

  void signedIn(User u) {
    if (!isPhone) startHost();
    user = u;
    page = PageId.home;
    gate = Gate.app;
    notifyListeners();
  }

  Future<void> signOut() async {
    await log('Signed out');
    user = null;
    gate = Gate.signIn;
    notifyListeners();
  }

  /// Something changed in the database; pages re-read.
  void refresh() => notifyListeners();

  // ---------- downloads (kept here so progress survives page changes) ----------
  final pulls = <String, double?>{};
  final speechDownloads = <String, double>{};

  Future<void> pullModel(String id) async {
    if (pulls.containsKey(id)) return;
    pulls[id] = null;
    notifyListeners();
    try {
      await for (final p in ollama.pull(id)) {
        pulls[id] = p.fraction;
        notifyListeners();
      }
      await log('Downloaded model $id');
      // The user just chose this model: use it for calls.
      await setLlmModel(id, manual: true);
      await refreshEngine();
      toast('$id downloaded and selected.');
    } catch (e) {
      toast('Download of $id failed: $e');
    } finally {
      pulls.remove(id);
      await refreshEngine();
    }
  }

  Future<void> downloadSpeech(SpeechEntry e, {required bool tts}) async {
    if (speechDownloads.containsKey(e.id)) return;
    speechDownloads[e.id] = 0;
    notifyListeners();
    try {
      await for (final f in speech.download(e, tts: tts)) {
        speechDownloads[e.id] = f;
        notifyListeners();
      }
      if (tts) {
        await setTtsVoice(e.id);
      } else {
        await setSttModel(e.id);
      }
      await log('Downloaded ${tts ? 'voice' : 'hearing model'} ${e.name}');
      toast('${e.name} is ready.');
    } catch (err) {
      toast('Download failed: $err');
    } finally {
      speechDownloads.remove(e.id);
      notifyListeners();
    }
  }
}
