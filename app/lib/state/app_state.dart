import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/auth.dart';
import '../services/catalog.dart';
import '../services/hardware.dart';
import '../services/ollama.dart';
import '../services/speech.dart';

enum Gate { loading, setup, signIn, app }

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

const advancedGroups = <String, List<PageId>>{
  'Operate': [PageId.home, PageId.chat, PageId.talk, PageId.calls, PageId.outbound, PageId.contacts],
  'Assistant': [PageId.assistant, PageId.agents, PageId.automations, PageId.knowledge, PageId.tools, PageId.skills],
  'Engine': [PageId.models, PageId.speech, PageId.hardware],
  'Connect': [PageId.lines, PageId.voiceServer, PageId.devices],
  'Admin': [PageId.users, PageId.logs, PageId.settings],
};

class AppState extends ChangeNotifier {
  AppState({this.dbPath});
  final String? dbPath;

  late Db db;
  late AuthService auth;
  late Catalog catalog;
  late Speech speech;
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

  /// Chat with the chosen (or given) model, using the right thinking setting.
  Stream<String> chat(List<ChatMessage> messages, {String? model}) {
    final m = model ?? llmModel!;
    final entry = catalog.llm.where((e) => e.id == m).firstOrNull;
    return ollama.chat(m, messages, disableThinking: entry?.think == 'off');
  }

  bool get llmReady => ollamaVersion != null && llmModel != null && installedModels.any((m) => m.name == llmModel);

  /// Chosen models.
  String? llmModel;
  String sttModel = 'ggml-base.en.bin';
  String ttsVoice = 'en_GB-alba-medium';

  final messenger = GlobalKey<ScaffoldMessengerState>();

  Future<void> init() async {
    // Debug builds only: LOCALAILINE_DB picks a database file (for development).
    final devDb = kDebugMode ? Platform.environment['LOCALAILINE_DB'] : null;
    db = await Db.open(path: dbPath ?? devDb);
    auth = AuthService(db);
    catalog = await Catalog.load();
    speech = await Speech.create();
    advanced = await db.setting('ui.advanced') == '1';
    themeMode = await db.setting('ui.theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
    answering = await db.setting('calls.answering') != '0';
    llmModel = await db.setting('llm.model');
    sttModel = await db.setting('stt.model') ?? sttModel;
    ttsVoice = await db.setting('tts.voice') ?? ttsVoice;
    gate = await auth.hasOwner() ? Gate.signIn : Gate.setup;
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
    if (!v && !simplePages.contains(page)) page = PageId.home;
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

  Future<void> completeSetup(User owner) async {
    await db.seedDefaults(owner.name);
    await db.audit(owner.name, 'Created owner account and finished setup');
    user = owner;
    page = PageId.home;
    gate = Gate.app;
    notifyListeners();
  }

  void signedIn(User u) {
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
