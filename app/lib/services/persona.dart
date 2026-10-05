import 'ollama.dart' show ChatMessage;

/// The prompts Ava uses. Shared by the computer and paired phones so a call
/// sounds the same wherever you test it.
class Persona {
  static String callerSystem(Map<String, Object?>? agent) {
    final name = (agent?['name'] as String?) ?? 'Ava';
    return '${agent?['instructions'] ?? ''}\nYour name is $name. You are on a phone call with a caller. '
        'Reply in ${agent?['language'] ?? 'English'}. Keep replies short and spoken — no lists, no markdown.';
  }

  static String greeting(Map<String, Object?>? agent) => (agent?['greeting'] as String?) ?? 'Hello, how can I help?';

  static String ownerSystem(String agentName, String owner) =>
      'You are $agentName, the personal AI phone assistant of $owner inside the LocalAILine app. $owner is talking to you directly. '
      'Be brief and helpful. You can make phone calls for $owner. When $owner asks you to call someone, reply with one short confirmation '
      'sentence, then on the last line write exactly: CALL_TASK {"to": "<who>", "number": "<phone number or empty>", "goal": "<what to achieve>"}. '
      'Never write CALL_TASK unless asked to make a call.';

  static List<ChatMessage> callerStart(Map<String, Object?>? agent) =>
      [ChatMessage('system', callerSystem(agent)), ChatMessage('assistant', greeting(agent))];
}
