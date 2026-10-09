import 'apps/app_spec.dart';
import 'apps/app_templates.dart';
import 'apps/built_app.dart';
import 'knowledge.dart';
import 'mcp.dart';
import 'users.dart';

/// What the pages use of LocalAILine's services. The desktop app's services implement these
/// directly; a remote client (the web app) implements them over the network.

/// The app's own records (agents, calls, contacts, settings…).
abstract interface class DataApi {
  /// Where the data is kept (shown in Settings).
  String get path;
  Future<String?> setting(String key);
  Future<void> setSetting(String key, String value);
  Future<List<Map<String, Object?>>> all(String table, {String? orderBy, String? where, List<Object?>? args});
  Future<int> insert(String table, Map<String, Object?> row);
  Future<void> update(String table, int id, Map<String, Object?> row);
  Future<void> delete(String table, int id);
  Future<int> count(String table, {String? where, List<Object?>? args});
  Future<void> seedDefaults(String ownerName);

  /// Skills made from a knowledge source stay, but no longer follow it.
  Future<void> unlinkSkills(int sourceId);
}

abstract interface class AuthApi {
  Future<User> createUser({required String name, required String username, required String password, required Role role});
  Future<User> signIn(String username, String password);
  Future<List<User>> users();
  Future<void> setRole(int id, Role role);
}

abstract interface class McpApi {
  Future<List<McpServer>> servers();
  Map<int, McpStatus> get status;
  McpStatus statusOf(McpServer s);
  String? errorOf(McpServer s);
  Future<void> connect(int id, {bool interactive = false});
  Future<void> disconnect(int id);
  Future<void> signOut(int id);
}

abstract interface class KnowledgeApi {
  String? get embedError;
  Map<int, IndexProgress> get progress;

  /// Folders on the machine the engine runs on, watched for changes (the desktop app).
  bool get canAddFolders;
  Future<int> addSource(String path, {required String scope, String? name});

  /// A document picked by the person: read from [path] where the engine can (and watched for
  /// changes), otherwise from [bytes] (an upload).
  Future<int> addFile({required String name, String? path, required Future<List<int>> Function() bytes, required String scope, String? title});

  /// The text of a document (PDF, Word, Excel, text…).
  Future<String> readText({required String name, String? path, required Future<List<int>> Function() bytes});
  Future<({List<KnowledgeHit> hits, int ms})> search(String query, {Set<int>? sources, int k = 5});
  Future<void> removeSource(int id);
  Future<void> reindex(int id);
}

/// Business apps: building them with the AI, running them, changing them.
abstract interface class AppsApi {
  /// The "create an app" conversation in progress (kept while you move around the app).
  BuildJob? get job;
  BuildJob newJob();
  void cancelJob();
  Future<void> askQuestions(BuildJob j);
  Future<void> makePlan(BuildJob j);
  Future<void> changePlan(BuildJob j, String change);
  void editPlan(BuildJob j, AppSpec plan);
  Future<void> build(BuildJob j);
  Future<void> retryFrom(BuildJob j);
  Future<String?> addPicture(BuildJob j, String base64);
  void removePicture(BuildJob j, int i);

  Future<List<BuiltApp>> apps();
  Future<BuiltApp?> app(int id);
  AppRun runOf(int id);

  /// What the AI is changing in an app right now (app id → message).
  Map<int, String> get editing;
  Future<int> createFromTemplate(AppTemplate t, {bool ava = true, String name = '', String phone = '', String address = ''});
  Future<void> start(int id, {bool quiet = false});
  Future<void> pause(int id);
  Future<void> stop(int id);
  Future<void> delete(int id);
  Future<String> newPin(int id);
  Future<List<McpServer>> avaServers(int id);
  Future<void> connectAva(int id);
  Future<void> disconnectAva(int id);
  Future<void> setAccess(int id, String table, Access access);
  Future<String?> changeTable(int id, String tableId, String request);
  Future<String?> changePage(int id, String pageId, String request);
  Future<String?> changeLook(int id, String request, {String? pictureBase64});
  Future<String?> changeAnything(int id, String request);
  Future<void> removePart(int id, {String? table, String? page});
  Future<void> setStyle(int id, String style, {String? accent});
  Future<List<Map<String, dynamic>>> rowsFromPicture(int id, String table, String base64);
  Future<int> addRows(int id, String table, List<Map<String, dynamic>> rows);

  /// The address people use for an app's website (`/manage` on it is the manager page).
  String siteUrl(BuiltApp a);

  /// Every address the website can be reached at, with what each is for (this computer, the Wi-Fi…).
  Future<List<(String label, String url)>> siteLinks(BuiltApp a);
}

/// Joining a live call's audio from an app (LiveKit).
abstract interface class CallRoomsApi {
  /// Why calls can't be joined from here now, or null when they can.
  String? get notReady;

  /// The LiveKit server to connect to.
  String get url;
  Future<String> joinToken({required String identity, required String room, String? name, bool canPublish = true, bool hidden = false, bool canUpdateOwnMetadata = false});
  Future<bool> roomExists(String room);

  /// Ends a call: everyone leaves (a phone caller is hung up on).
  Future<void> endCall(String room);

  /// Sends the voice agent (back) into a call; [metadata] reaches it as the job's metadata.
  Future<void> sendAgent(String room, {String metadata = ''});
}
