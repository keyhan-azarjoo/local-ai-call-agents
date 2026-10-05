import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  String? model;
  bool busy = false;

  static const system = 'You are a helpful, concise assistant running privately on the user’s own computer inside LocalAILine. '
      'Answer clearly. Use short paragraphs and simple lists when helpful.';

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

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
      final history = [ChatMessage('system', system), ...messages.where((x) => x != reply)];
      await for (final piece in s.chat(history, model: m)) {
        reply.content += piece;
        if (mounted) setState(() {});
        _scrollDown();
      }
    } catch (e) {
      reply.content = reply.content.isEmpty ? 'Couldn’t reply: $e' : reply.content;
    } finally {
      await s.db.insert('chat_messages', {'chat_id': chatId, 'role': 'assistant', 'content': reply.content, 'at': DateTime.now().millisecondsSinceEpoch});
      await s.db.update('chats', chatId!, {'updated_at': DateTime.now().millisecondsSinceEpoch});
      await _loadChats();
      if (mounted) setState(() => busy = false);
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
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    final mine = m.role == 'user';
                    return Align(
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
