import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:localailine_model/connectors.dart';
import 'package:localailine_ui/app_model.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// One-click connectors for popular services (email, calendar, work apps, payments…).
class ConnectorsSection extends StatelessWidget {
  const ConnectorsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
    return FutureBuilder(
      future: s.db.all('mcp_servers', orderBy: 'id'),
      builder: (context, snap) {
        final added = {for (final r in snap.data ?? const <Map<String, Object?>>[]) '${r['target']}'.split(' "').first};
        final groups = <String, List<Connector>>{};
        for (final c in connectors) {
          (groups[c.category] ??= []).add(c);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ready connectors', style: displayStyle(context, 18)),
          const SizedBox(height: 4),
          const Muted('Add the apps you use. Most just need you to sign in; Ava can then read and act in them for you (changes ask you first).'),
          const SizedBox(height: 14),
          for (final g in groups.entries) ...[
            Eyebrow(g.key),
            const SizedBox(height: 8),
            Grid(cols: 3, children: [for (final c in g.value) _card(context, s, c, added.contains(c.target))]),
            const SizedBox(height: 16),
          ],
        ]);
      },
    );
  }

  Widget _card(BuildContext context, AppModel s, Connector c, bool isAdded) => Panel(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LogoBox(child: Text(c.name.substring(0, c.name.length >= 2 ? 2 : 1), style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Muted(c.about, size: 12),
              const SizedBox(height: 8),
              isAdded
                  ? const Pill('Added', tone: Tone.green)
                  : Btn(switch (c.kind) {
                      ConnectorKind.signIn || ConnectorKind.google => 'Connect',
                      _ => 'Add',
                    }, small: true, kind: BtnKind.primary, onPressed: () => addConnector(context, s, c)),
            ]),
          ),
        ]),
      );
}

/// Adds a connector: asks only what's needed, then connects (opening the sign-in page if any).
Future<void> addConnector(BuildContext context, AppModel s, Connector c) async {
  Future<void> save({required String kind, required String target, required String auth, Map<String, dynamic> secret = const {}}) async {
    final id = await s.db.insert('mcp_servers', {
      'name': c.name,
      'kind': kind,
      'target': target,
      'scope': 'me',
      'auth_mode': auth,
      'secret': jsonEncode(secret),
      'enabled': 1,
    });
    await s.log('Added connector ${c.name}');
    s.refresh();
    await s.mcp.connect(id, interactive: true);
    if (s.mcp.status[id]?.name == 'connected') s.toast('${c.name} is connected.');
  }

  switch (c.kind) {
    case ConnectorKind.signIn:
      return save(kind: 'http', target: c.url!, auth: 'auto');
    case ConnectorKind.local:
      if (c.id == 'files') {
        final dir = await getDirectoryPath(confirmButtonText: 'Use this folder');
        if (dir == null) return;
        return save(kind: 'stdio', target: '${c.command} "${dir.replaceAll('"', r'\"')}"', auth: 'none');
      }
      return save(kind: 'stdio', target: c.command!, auth: 'none');
    case ConnectorKind.token:
      final token = await _ask(context, c.name, c.tokenHelp ?? '', [('Access token', true, '')]);
      if (token == null) return;
      return save(kind: 'http', target: c.url!, auth: 'token', secret: {'header': 'Authorization', 'value': 'Bearer ${token[0]}'});
    case ConnectorKind.google:
      // One Google app serves Gmail, Calendar and Drive: reuse it if it's already set up.
      Map<String, dynamic>? known;
      for (final r in await s.db.all('mcp_servers', orderBy: 'id')) {
        final p = (jsonDecode('${r['secret'] ?? '{}'}') as Map?)?['preset'];
        if (p is Map && p['authorization_endpoint'] == googleAuth) known = p.cast<String, dynamic>();
      }
      if (!context.mounted) return;
      final v = await _ask(
        context,
        'Connect ${c.name}',
        'Google needs your own sign-in app (free, one time):\n'
            '1. In Google Cloud Console create a project and enable the ${c.name} API (and its MCP API if asked).\n'
            '2. Google Auth Platform → set up the consent screen, add yourself as a test user.\n'
            '3. Clients → Create client → “Desktop app”. Paste its Client ID and Client secret here.\n'
            'Then you sign in with Google in your browser.',
        [('Client ID', false, '${known?['client_id'] ?? ''}'), ('Client secret', true, '${known?['client_secret'] ?? ''}')],
        link: ('Open Google Cloud Console', 'https://console.cloud.google.com/auth/clients'),
      );
      if (v == null) return;
      return save(kind: 'http', target: c.url!, auth: 'auto', secret: {
        'preset': {
          'authorization_endpoint': googleAuth,
          'token_endpoint': googleToken,
          'scope': c.scope,
          'client_id': v[0],
          'client_secret': v[1],
          // A refresh token, so you stay signed in.
          'params': {'access_type': 'offline', 'prompt': 'consent'},
        },
      });
    case ConnectorKind.email:
      final m = c.mail!;
      final custom = m.imap.isEmpty;
      final v = await _ask(context, 'Add ${c.name}', m.help, [
        ('Email address', false, ''),
        ('App password', true, ''),
        if (custom) ...[('IMAP server (e.g. mail.example.com)', false, ''), ('SMTP server', false, '')],
      ]);
      if (v == null) return;
      return save(kind: 'stdio', target: 'npx -y mcp-mail-server #${c.id}', auth: 'none', secret: {
        'env': {
          'EMAIL_USER': v[0],
          'EMAIL_PASS': v[1],
          'IMAP_HOST': custom ? v[2] : m.imap,
          'IMAP_PORT': '${m.imapPort}',
          'IMAP_SECURE': 'true',
          'SMTP_HOST': custom ? v[3] : m.smtp,
          'SMTP_PORT': '${m.smtpPort}',
          'SMTP_SECURE': '${m.smtpTls}',
        },
      });
  }
}

/// A small form: returns the values, or null if cancelled.
Future<List<String>?> _ask(BuildContext context, String title, String help, List<(String, bool, String)> fields, {(String, String)? link}) {
  final ctrls = [for (final f in fields) TextEditingController(text: f.$3)];
  String? error;
  return showDialog<List<String>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title, style: displayStyle(c, 20)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (help.isNotEmpty) Muted(help, size: 13),
              if (link != null) Padding(padding: const EdgeInsets.only(top: 8), child: Btn(link.$1, small: true, icon: Icons.open_in_new, onPressed: () => context.read<AppModel>().openUrl(link.$2))),
              const SizedBox(height: 14),
              for (var i = 0; i < fields.length; i++) ...[
                Field(label: fields[i].$1, child: TextField(controller: ctrls[i], obscureText: fields[i].$2)),
                const SizedBox(height: 10),
              ],
              if (error != null) Text(error!, style: const TextStyle(color: LL.red, fontSize: 13)),
              const Muted('Saved in the local database on this computer only.', size: 12),
            ]),
          ),
        ),
        actions: [
          Btn('Cancel', onPressed: () => Navigator.pop(c)),
          Btn('Connect', kind: BtnKind.primary, onPressed: () {
            final v = [for (final t in ctrls) t.text.trim()];
            if (v.any((x) => x.isEmpty)) return set(() => error = 'Fill in every box.');
            Navigator.pop(c, v);
          }),
        ],
      ),
    ),
  );
}
