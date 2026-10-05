import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/agent_loop.dart';
import '../../services/ollama.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Text chat with the local AI, like any chat assistant. Chats are saved on
/// this computer, per user.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  List<Map<String, Object?>> chats = [];
  int? chatId;
  final messages = <ChatMessage>[];

  /// Stable identity per message so inserting tool notes doesn't shift others.
  final _keys = Expando<Key>();
  int _nextKey = 0;
  Key _keyOf(ChatMessage m) => _keys[m] ??= ValueKey('m${_nextKey++}');
  String? model;
  bool busy = false;
  int toolCount = 0;
  String? progress;
  DateTime? started;

  static const system = 'You are a helpful, concise assistant running privately on the user’s own computer inside LocalAILine. '
      'Answer clearly. Use short paragraphs and simple lists when helpful. '
      'When tools from the user’s connected services are available and the question is about their data, use the tools instead of guessing.';

  static const _scopes = {'me', 'contacts', 'all'};

  @override
  void initState() {
    super.initState();
    _loadChats();
    s.toolsFor(_scopes).then((t) => mounted ? setState(() => toolCount = t.length) : null);
  }

  Future<bool> _approve(ToolBinding b, Map<String, dynamic> args) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Allow this action?', style: displayStyle(c, 20)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.serverName} › ${b.tool.title ?? b.tool.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Muted(b.tool.description),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: LL.navy, borderRadius: BorderRadius.circular(LL.rSm)),
                child: SelectableText(const JsonEncoder.withIndent('  ').convert(args),
                    style: const TextStyle(fontFamily: LL.mono, fontSize: 12, color: Color(0xFFCFE0F3))),
              ),
              const SizedBox(height: 8),
              const Muted('This tool can change data. Ava only runs it if you allow.'),
            ]),
          ),
          actions: [
            Btn('Don’t allow', onPressed: () => Navigator.pop(c, false)),
            Btn('Allow', kind: BtnKind.primary, onPressed: () => Navigator.pop(c, true)),
          ],
        ),
      ) ??
      false;

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  AppState get s => context.read<AppState>();

  Future<void> _loadChats() async {
    chats = await s.db.all('chats', where: 'user_id = ?', args: [s.user?.id], orderBy: 'updated_at DESC');
    if (mounted) setState(() {});
  }

  Future<void> _open(int id) async {
    final rows = await s.db.all('chat_messages', where: 'chat_id = ?', args: [id], orderBy: 'id');
    setState(() {
      chatId = id;
      messages
        ..clear()
        ..addAll(rows.map((r) => ChatMessage(r['role'] as String, r['content'] as String)));
    });
    _scrollDown();
  }

  void _new() {
    setState(() {
      chatId = null;
      messages.clear();
    });
    focus.requestFocus();
  }

  Future<void> _delete(int id) async {
    await s.db.delete('chats', id);
    if (chatId == id) _new();
    await _loadChats();
  }

  Future<void> _send() async {
    final text = input.text.trim();
    final m = s.usingCloud ? null : (model ?? s.llmModel);
    if (text.isEmpty || busy) return;
    if (!s.llmReady) return s.toast('Set up the AI first (Settings).');
    input.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    chatId ??= await s.db.insert('chats', {
      'user_id': s.user?.id,
      'title': text.length > 48 ? '${text.substring(0, 48)}…' : text,
      'model': m ?? s.llmLabel,
      'updated_at': now,
    });
    unawaited(_loadChats()); // show the new chat in the list straight away
    started = DateTime.now();
    progress = 'Thinking…';
    final user = ChatMessage('user', text);
    final reply = ChatMessage('assistant', '');
    setState(() {
      messages
        ..add(user)
        ..add(reply);
      busy = true;
    });
    await s.db.insert('chat_messages', {'chat_id': chatId, 'role': 'user', 'content': text, 'at': now});
    _scrollDown();
    try {
      final history = [ChatMessage('system', system), ...messages.where((x) => x != reply && x.role != 'tool')];
      final tools = await s.toolsFor(_scopes);
      if (tools.isNotEmpty) {
        reply.content = await s.agentReply(history, scopes: _scopes, approve: _approve, onText: (t) {
          if (!mounted) return;
          setState(() {
            reply.content = t;
            if (t.isNotEmpty) progress = 'Writing the answer…';
          });
          _scrollDown();
        }, onEvent: (e) async {
          final note = ChatMessage('tool', jsonEncode({
            'server': e.binding.serverName,
            'tool': e.binding.tool.title ?? e.binding.tool.name,
            'args': e.args,
            'ok': e.ok,
            'denied': e.denied,
            'result': e.result.length > 600 ? '${e.result.substring(0, 600)}…' : e.result,
          }));
          setState(() {
            messages.insert(messages.indexOf(reply), note);
            final used = messages.where((x) => x.role == 'tool').map((x) => (jsonDecode(x.content) as Map)['tool']).toSet();
            progress = 'Used ${used.join(', ')} · writing the answer…';
          });
          await s.db.insert('chat_messages', {'chat_id': chatId, 'role': 'tool', 'content': note.content, 'at': DateTime.now().millisecondsSinceEpoch});
          _scrollDown();
        });
        if (reply.content.isEmpty) reply.content = '(No answer.)';
      } else {
        await for (final piece in s.chat(history, model: m)) {
          reply.content += piece;
          if (mounted) setState(() {});
          _scrollDown();
        }
      }
    } catch (e) {
      reply.content = reply.content.isEmpty ? 'Couldn’t reply: $e' : reply.content;
    } finally {
      await s.db.insert('chat_messages', {'chat_id': chatId, 'role': 'assistant', 'content': reply.content, 'at': DateTime.now().millisecondsSinceEpoch});
      await s.db.update('chats', chatId!, {'updated_at': DateTime.now().millisecondsSinceEpoch});
      await _loadChats();
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
      focus.requestFocus();
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.c;
    final height = (MediaQuery.of(context).size.height - 140).clamp(420.0, 2000.0);
    final models = {for (final m in st.installedModels) m.name: m.name};
    final current = model ?? st.llmModel;

    final list = Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(12), child: Btn('New chat', icon: Icons.add, kind: BtnKind.primary, onPressed: _new)),
        Expanded(
          child: chats.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Muted('Your chats appear here.'))
              : ListView(children: [
                  for (final ch in chats)
                    Material(
                      color: ch['id'] == chatId ? c.canvas : Colors.transparent,
                      child: InkWell(
                        onTap: () => _open(ch['id'] as int),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(ch['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                Muted(ago(ch['updated_at'] as int), size: 11, mono: true),
                              ]),
                            ),
                            IconButton(
                              tooltip: 'Delete chat',
                              icon: const Icon(Icons.close, size: 15),
                              onPressed: () => _delete(ch['id'] as int),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
        ),
      ]),
    );

    final conversation = Panel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            Text('Chat with AI', style: displayStyle(context, 17)),
            const Spacer(),
            if (toolCount > 0) ...[
              Pill('$toolCount tools', tone: Tone.green),
              const SizedBox(width: 8),
            ],
            if (st.usingCloud)
              Pill(st.llmLabel, tone: Tone.blue)
            else if (models.isNotEmpty)
              SizedBox(
                width: 220,
                child: Dropdown(value: current ?? models.keys.first, items: models, onChanged: (v) => setState(() => model = v)),
              ),
          ]),
        ),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 30, color: c.muted),
                      const SizedBox(height: 10),
                      Text('Ask anything', style: displayStyle(context, 20)),
                      const SizedBox(height: 4),
                      Muted(st.usingCloud ? 'Uses ${st.cloud!.provider.label}. Your messages go to them.' : 'Runs on your own computer. Nothing is sent anywhere.', size: 13.5),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                        for (final q in const [
                          'Write a friendly voicemail greeting for my business',
                          'What should my assistant ask unknown callers?',
                          'Summarise the pros and cons of SIP vs a landline box',
                        ])
                          ActionChip(
                            label: Text(q, style: const TextStyle(fontSize: 12.5)),
                            onPressed: () {
                              input.text = q;
                              _send();
                            },
                          ),
                      ]),
                    ]),
                  ),
                )
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  findChildIndexCallback: (key) {
                    final i = messages.indexWhere((m) => _keyOf(m) == key);
                    return i < 0 ? null : i;
                  },
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    if (m.role == 'tool') return ToolNote(m.content, key: _keyOf(m));
                    final mine = m.role == 'user';
                    return Align(
                      key: _keyOf(m),
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 680),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? (Theme.of(context).brightness == Brightness.dark ? LL.navy3 : LL.navy) : c.canvas,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: m.content.isEmpty
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : SelectableText(m.content, style: TextStyle(color: mine ? Colors.white : c.ink, height: 1.45)),
                      ),
                    );
                  },
                ),
        ),
        if (busy && progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6)),
              const SizedBox(width: 8),
              Expanded(child: _Elapsed(label: progress!, since: started ?? DateTime.now())),
            ]),
          ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Focus(
                // Enter sends; Shift+Enter adds a new line.
                onKeyEvent: (_, e) {
                  if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: input,
                  focusNode: focus,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 6,
                  style: const TextStyle(fontSize: 14.5),
                  decoration: const InputDecoration(hintText: 'Message the AI…  (Enter to send, Shift+Enter for a new line)'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Btn(busy ? 'Thinking…' : 'Send', icon: Icons.arrow_upward_rounded, kind: BtnKind.primary, large: true, onPressed: busy ? null : _send),
          ]),
        ),
      ]),
    );

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth > 860
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 240, child: list),
                const SizedBox(width: 16),
                Expanded(child: conversation),
              ])
            : conversation,
      ),
    );
  }

}

/// One tool call shown in the conversation (tap to see input and result).
/// Keeps its open/closed state itself (no PageStorage, which clashed with the
/// list's scroll position).
class ToolNote extends StatefulWidget {
  const ToolNote(this.content, {super.key});
  final String content;
  @override
  State<ToolNote> createState() => _ToolNoteState();
}

class _ToolNoteState extends State<ToolNote> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(widget.content) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox();
    }
    final ok = j['ok'] == true, denied = j['denied'] == true;
    final checked = '${j['result']}'.startsWith('The tool was not called because of its inputs');
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(color: c.blueSoft, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(denied ? Icons.block : checked ? Icons.info_outline : ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 18, color: denied || checked ? c.muted : ok ? LL.green : LL.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${denied ? 'Not allowed' : checked ? 'Fixing inputs for' : ok ? 'Used' : 'Error from'} ${j['server']} › ${j['tool']}',
                      style: const TextStyle(fontFamily: LL.mono, fontSize: 12.5)),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: c.muted),
              ]),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text('Input: ${jsonEncode(j['args'])}\n\nResult: ${j['result']}',
                  style: const TextStyle(fontFamily: LL.mono, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

/// "Used … · 17 s": only this line repaints each second, not the conversation.
class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.label, required this.since});
  final String label;
  final DateTime since;
  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _t;
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Muted('${widget.label} · ${DateTime.now().difference(widget.since).inSeconds} s');
}
