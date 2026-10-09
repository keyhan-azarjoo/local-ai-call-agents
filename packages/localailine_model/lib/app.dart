import 'dart:convert';

/// Every page the app has. Simple mode shows only [simplePages].
enum PageId {
  home('Home'),
  talk('Talk to Ava'),
  chat('Chat'),
  calls('Calls'),
  outbound('Make a call'),
  assistant('My assistant'),
  builder('Build an app'),
  lines('Phone line'),
  settings('Settings'),
  // Shown with "Show all features":
  agents('Call flow'),
  automations('Automations & loops'),
  contacts('Contacts & rules'),
  knowledge('Knowledge'),
  tools('Tools & connectors'),
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

enum Gate { loading, setup, signIn, app, companion }

const simplePages = [PageId.home, PageId.chat, PageId.talk, PageId.calls, PageId.outbound, PageId.assistant, PageId.builder, PageId.lines, PageId.settings];

/// "Show all features" adds tabs inside these pages; the menu never grows.
const hubTabs = <PageId, List<(PageId, String)>>{
  PageId.assistant: [(PageId.assistant, 'Ava'), (PageId.agents, 'Call flow'), (PageId.skills, 'Skills'), (PageId.knowledge, 'Knowledge'), (PageId.tools, 'Tools'), (PageId.automations, 'Automations')],
  PageId.lines: [(PageId.lines, 'Lines'), (PageId.contacts, 'Contacts & rules'), (PageId.voiceServer, 'Voice server'), (PageId.devices, 'Paired devices')],
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

/// What one agent may use on calls (null = everything shared with calls). Keeping each agent
/// to what its job needs keeps its prompt small and its answers fast.
class AgentAccess {
  const AgentAccess({this.tools, this.skills, this.docs, this.skillDocs = const {}});
  final Set<int>? tools, skills, docs; // MCP server ids, skill ids, knowledge ids
  final Set<int> skillDocs; // documents behind the allowed skills

  static AgentAccess? parse(String? json, {Map<int, int> skillSource = const {}}) {
    if (json == null || json.isEmpty) return null;
    try {
      final j = jsonDecode(json) as Map;
      Set<int>? ids(String k) => j[k] is List ? {for (final v in j[k] as List) (v as num).toInt()} : null;
      final skills = ids('skills');
      return AgentAccess(
        tools: ids('tools'),
        skills: skills,
        docs: ids('docs'),
        skillDocs: {for (final id in skills ?? <int>{}) ?skillSource[id]},
      );
    } catch (_) {
      return null;
    }
  }
}

/// One line of a live conversation: who ('caller', 'ai' or 'note'), the words so far, and whether
/// they are finished (the caller's words can still change until hearing settles on them).
class LiveLine {
  LiveLine(this.who, this.text, {this.name, this.done = false, DateTime? at}) : at = at ?? DateTime.now();
  final String who;
  String text;
  final String? name;
  bool done;
  final DateTime at;
}

/// Which scenarios to run from the app.
enum ScenarioPick { quick, app, journeys, challenges, security, bench, all }
