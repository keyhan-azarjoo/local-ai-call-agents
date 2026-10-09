import 'package:flutter/material.dart';
import 'package:localailine_model/agent_templates.dart';
import 'package:localailine_model/api.dart';
import 'package:localailine_model/app.dart';
import 'package:localailine_model/catalog.dart';
import 'package:localailine_model/llm.dart';
import 'package:localailine_model/mcp.dart';
import 'package:localailine_model/phone_lines.dart';
import 'package:localailine_model/users.dart';

import 'state/call_monitor.dart';

export 'package:localailine_model/api.dart';
export 'package:localailine_model/app.dart';
export 'package:localailine_model/phone_lines.dart';

/// Everything the shared pages need from LocalAILine.
///
/// The desktop app implements it on the engine in this process (`AppState`); a remote client
/// implements it on an engine running elsewhere. Pages read it with
/// `context.watch<AppModel>()`; it notifies when anything they show changes.
abstract class AppModel implements Listenable {
  // ---------- which edition ----------

  /// The engine runs on a server: the AI, hearing and voice aren't on this machine, and the pages
  /// about this computer (models, hardware, voice server, paired phones) aren't there.
  bool get isHosted;

  // ---------- services ----------
  DataApi get db;
  AuthApi get auth;
  McpApi get mcp;
  KnowledgeApi get knowledge;
  AppsApi get apps;
  Catalog get catalog;

  /// Joining live calls (listening in, taking over).
  CallRoomsApi get callRooms;
  CallMonitor get callMonitor;

  // ---------- the person and the app ----------
  Gate get gate;
  abstract User? user;
  PageId get page;
  void go(PageId p);
  bool get advanced;
  Future<void> setAdvanced(bool v);
  ThemeMode get themeMode;
  Future<void> toggleTheme();
  GlobalKey<ScaffoldMessengerState> get messenger;
  GlobalKey<NavigatorState> get navigator;
  void toast(String msg);
  void refresh();
  Future<void> log(String what);
  Future<void> openUrl(String url);

  /// Shows where the app keeps its data (desktop).
  Future<void> openDataFolder();

  /// A place for a short-lived file (a voice note being recorded).
  String tempFile(String name);

  /// A call's recording can be played here, and plays it.
  bool hasRecording(String? path);
  Future<void> playRecording(String path);

  /// Taking a picture of part of the screen (macOS: drag over it); null when cancelled.
  bool get canScreenshot;
  Future<List<int>?> takeScreenshot();
  Future<void> completeSetup(User owner);
  void signedIn(User u);
  Future<void> signOut();
  int? get editAgentId;
  void editAgent(int? id);
  abstract String callsFilter;
  void openTests();

  // ---------- answering calls ----------
  bool get answering;
  Future<void> setAnswering(bool v);
  bool get recordCalls;
  Future<void> setRecordCalls(bool on);
  int get lines;
  Future<void> setLines(int n);
  int get maxLines;
  int get activeCalls;
  int get defaultMaxCalls;
  Future<void> setMaxCalls(int n);
  Future<void> placeCall(int taskId);

  /// Answer calls to a phone line here, or give it back (null: not something this edition does).
  Future<String> setInbound(int lineId, bool on);

  /// Settings for a landline gateway box (FXO) on this network, to type into the box.
  List<(String, String)> gatewaySettings(Map<String, dynamic> cfg);

  /// Who takes calls on a line (AI, ring me, ring me then the AI, off). Returns what happened.
  Future<String> setLineAnswer(int lineId, AnswerMode mode, {int? ringSeconds});

  /// Connects a saved line where that needs a step (your own number: signs it in to the provider).
  Future<String> connectLine(int lineId);

  /// Tries a line's provider details once ([lineId]: the saved line being edited, if any).
  Future<({bool ok, String result})> testSipLine(Map<String, dynamic> cfg, {int? lineId});

  /// Removes a line (signed out of its provider first).
  Future<void> removeLine(int lineId);

  /// Each of your own numbers' sign-in state (line id → state).
  Map<int, SipLineStatus> get sipStatus;

  /// Calls ringing you now, before anyone answers (room → line, caller, when the AI steps in).
  Map<String, ({String line, String number, DateTime until})> get ringing;

  /// "Let the AI answer" a call that is ringing you.
  void releaseCall(String room);

  // ---------- the AI ----------
  bool get llmReady;
  String get llmLabel;
  String? get llmModel;
  bool get usingCloud;
  bool get usingServer;
  bool get usingOllama;
  CloudConfig? get cloud;
  List<OllamaModel> get installedModels;
  Map<String, double?> get pulls;
  Future<void> pullModel(String id, {bool select = true});
  Future<String?> visionModel();

  /// One turn of a chat with Ava: streams the answer as it's written ([onText]), with each tool
  /// the AI uses ([onEvent]); actions that change something are asked about first ([approve]).
  Future<String> agentReply(
    List<ChatMessage> messages, {
    required Set<String> scopes,
    required Future<bool> Function(ToolBinding b, Map<String, dynamic> args) approve,
    void Function(ToolEvent)? onEvent,
    void Function(String textSoFar)? onText,
    List<String> earlier,
    String? excludeFile,
    List<String>? sticky,
  });

  /// Gets the model ready for the next turn (loads it, reads the instructions).
  Future<void> prewarm(List<ChatMessage> history, {required Set<String> scopes, List<String>? sticky});
  Future<List<ToolBinding>> toolsFor(Set<String> scopes);
  Future<void> rememberChat(int chatId, String title, List<ChatMessage> msgs);

  /// The words in a recorded voice note (16 kHz mono WAV, where the recorder saved it).
  Future<String> transcribeVoiceNote(String path);
  Stream<String> chat(List<ChatMessage> messages, {String? model, bool json = false, double temperature = 0.6});

  // ---------- voices ----------
  String get ttsVoice;
  Future<void> setTtsVoice(String v);

  /// Says [text] in [voice] through this device's speaker (Settings → greeting preview).
  Future<void> previewVoice(String text, String voice);

  /// The voices to choose from here, with a note when one isn't ready (id → label).
  Map<String, String> voiceChoices();

  // ---------- the team ----------
  Future<int> addRole(RoleTemplate t);
  Future<void> setUpTeam(BusinessTemplate b);

  // ---------- live calls ----------
  Map<String, ({String agent, String caller, String number, String name, DateTime at})> get liveCalls;
  Map<String, List<LiveLine>> get liveText;
  List<({String room, String number, DateTime ended, List<LiveLine> lines})> get recentLive;
  Map<String, String> get takenOver;
  Map<String, String> get callerAs;
  Set<String> get ownerSpeaking;
  String get ownerName;
  void liveTakeover(String room, String by);
  void liveHandedBack(String room);
  void liveOnCall(String room, {required bool owner, required bool caller});
  void liveCallGone(String room);
  void liveCallerAs(String room, String? by);

  /// Test runs going on (spoken test calls never ring a real phone).
  bool get testsRunning;

  /// Voice test calls can be placed here (the local voice engine is running).
  bool get canVoiceTest;

  /// Voice test calls (a simulated caller on a real voice call): ports of the ones running.
  Iterable<int> get voiceTestPorts;
  Future<List<Map<String, dynamic>>> voicePersonas();
  Future<List<({int id, String label})>> voiceTestAgents();
  Future<void> startVoiceTest(String persona, {int? agentId});
  void stopVoiceTests();
}
