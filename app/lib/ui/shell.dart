import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'auth_pages.dart' show Brand;
import 'pages/admin_pages.dart';
import 'pages/engine_pages.dart';
import 'pages/main_pages.dart';
import 'pages/talk_page.dart';
import 'widgets.dart';

const pageIcons = <PageId, IconData>{
  PageId.home: Icons.space_dashboard_outlined,
  PageId.talk: Icons.mic_none_rounded,
  PageId.calls: Icons.call_outlined,
  PageId.outbound: Icons.phone_forwarded_outlined,
  PageId.assistant: Icons.smart_toy_outlined,
  PageId.lines: Icons.dns_outlined,
  PageId.settings: Icons.settings_outlined,
  PageId.agents: Icons.groups_outlined,
  PageId.automations: Icons.repeat_rounded,
  PageId.contacts: Icons.contact_phone_outlined,
  PageId.knowledge: Icons.menu_book_outlined,
  PageId.tools: Icons.power_outlined,
  PageId.skills: Icons.auto_awesome_outlined,
  PageId.models: Icons.memory_outlined,
  PageId.speech: Icons.graphic_eq,
  PageId.hardware: Icons.computer_outlined,
  PageId.voiceServer: Icons.hub_outlined,
  PageId.devices: Icons.smartphone_outlined,
  PageId.users: Icons.manage_accounts_outlined,
  PageId.logs: Icons.receipt_long_outlined,
};

Widget pageFor(PageId p) => switch (p) {
      PageId.home => const HomePage(),
      PageId.talk => const TalkPage(),
      PageId.calls => const CallsPage(),
      PageId.outbound => const OutboundPage(),
      PageId.assistant => const AssistantPage(),
      PageId.lines => const LinesPage(),
      PageId.settings => const SettingsPage(),
      PageId.agents => const AgentsPage(),
      PageId.automations => const AutomationsPage(),
      PageId.contacts => const ContactsPage(),
      PageId.knowledge => const KnowledgePage(),
      PageId.tools => const ToolsPage(),
      PageId.skills => const SkillsPage(),
      PageId.models => const ModelsPage(),
      PageId.speech => const SpeechPage(),
      PageId.hardware => const HardwarePage(),
      PageId.voiceServer => const VoiceServerPage(),
      PageId.devices => const DevicesPage(),
      PageId.users => const UsersPage(),
      PageId.logs => const LogsPage(),
    };

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final body = Column(children: [
        _TopBar(showMenu: !wide),
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey(s.page),
            padding: EdgeInsets.all(wide ? 28 : 16),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180), child: pageFor(s.page)),
            ),
          ),
        ),
      ]);
      return Scaffold(
        drawer: wide ? null : const Drawer(width: 250, child: _Sidebar()),
        body: wide ? Row(children: [const SizedBox(width: 236, child: _Sidebar()), Expanded(child: body)]) : body,
      );
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget item(PageId p, {bool big = false}) {
      final active = s.page == p;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: active ? LL.navy3 : Colors.transparent,
          borderRadius: BorderRadius.circular(LL.rSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(LL.rSm),
            hoverColor: LL.navy2,
            onTap: () {
              s.go(p);
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.pop(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: big ? 10 : 7),
              child: Row(children: [
                Icon(pageIcons[p], size: big ? 19 : 17, color: active ? Colors.white : LL.navText),
                const SizedBox(width: 10),
                Text(p.title, style: TextStyle(fontSize: big ? 14.5 : 13.5, color: active ? Colors.white : LL.navText)),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      color: context.c.shell,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 18), child: InkWell(onTap: () => s.go(PageId.home), child: const Brand())),
        Expanded(
          child: ListView(children: [
            if (!s.advanced)
              for (final p in simplePages) item(p, big: true)
            else
              for (final g in advancedGroups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                  child: Text(g.key.toUpperCase(), style: const TextStyle(fontFamily: LL.mono, fontSize: 10.5, letterSpacing: 1.3, color: LL.navMuted)),
                ),
                for (final p in g.value) item(p),
              ],
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                const Expanded(child: Text('Show all features', style: TextStyle(color: Color(0xFF8FA6C2), fontSize: 12.5))),
                Transform.scale(scale: .75, child: Switch(value: s.advanced, onChanged: s.setAdvanced)),
              ]),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: LL.navy2))),
          child: Row(children: [
            CircleAvatar(radius: 15, backgroundColor: LL.amber, child: Text(s.user?.initials ?? '', style: const TextStyle(color: LL.navy, fontWeight: FontWeight.w700, fontSize: 11.5))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.user?.name ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                InkWell(onTap: s.signOut, child: Text('${s.user?.role.name ?? ''} · Sign out', style: const TextStyle(color: LL.navMuted, fontSize: 11.5))),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showMenu});
  final bool showMenu;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: context.c.panel, border: Border(bottom: BorderSide(color: context.c.line))),
      child: Row(children: [
        if (showMenu) Builder(builder: (c) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(c).openDrawer())),
        Text(s.page.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        InkWell(
          onTap: () => s.setAnswering(!s.answering),
          borderRadius: BorderRadius.circular(99),
          child: Pill(s.answering ? 'Answering' : 'Not answering', tone: s.answering ? Tone.green : Tone.neutral, lamp: s.answering ? LampState.on : LampState.off),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Dark appearance',
          icon: Icon(s.themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 18),
          onPressed: s.toggleTheme,
        ),
      ]),
    );
  }
}
