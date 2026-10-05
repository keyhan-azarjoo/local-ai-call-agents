import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'pages/engine_pages.dart' show EngineSetupPanel;
import 'widgets.dart';

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: LL.navy3, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.graphic_eq, size: 18, color: LL.amber),
        ),
        const SizedBox(width: 10),
        const Text.rich(TextSpan(
          style: TextStyle(fontFamily: LL.display, fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -.4),
          children: [TextSpan(text: 'Local'), TextSpan(text: 'AI', style: TextStyle(color: LL.amber)), TextSpan(text: 'Line')],
        )),
      ]);
}

/// Navy side panel + content, used by setup and sign-in.
class _FullScreen extends StatelessWidget {
  const _FullScreen({required this.side, required this.child});
  final Widget side;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > 900;
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (wide)
              Container(
                width: 400,
                color: context.c.shell,
                padding: const EdgeInsets.all(40),
                child: DefaultTextStyle.merge(style: const TextStyle(color: LL.navText), child: side),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: wide ? 64 : 22, vertical: 48),
                child: Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child)),
              ),
            ),
          ]);
        }),
      );
}

// ======================= Setup wizard =======================

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  static const steps = ['Welcome', 'Create your account', 'Set up the AI', 'Connect your phone line', 'Try it'];
  int step = 0;
  User? owner;

  final name = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _createOwner() async {
    final s = context.read<AppState>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      owner ??= await s.auth.createUser(
          name: name.text, username: username.text, password: password.text, role: Role.owner);
      s.user = owner;
      await s.db.seedDefaults(owner!.name);
      setState(() => step++);
    } on AuthError catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _next() => setState(() => step++);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return _FullScreen(
      side: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Brand(),
        const SizedBox(height: 40),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < step ? LL.green : i == step ? LL.amber : null,
                  border: Border.all(color: i <= step ? Colors.transparent : LL.navy3),
                ),
                child: i < step
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('${i + 1}', style: TextStyle(fontFamily: LL.mono, fontSize: 11, color: i == step ? LL.navy : LL.navText)),
              ),
              const SizedBox(width: 12),
              Text(steps[i],
                  style: TextStyle(
                      color: i == step ? Colors.white : LL.navText, fontWeight: i == step ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        const Spacer(),
        const Text('Nothing is sent to any LocalAILine server. There isn’t one.', style: TextStyle(color: LL.navMuted, fontSize: 12.5)),
      ]),
      child: switch (step) {
        0 => _welcome(),
        1 => _account(),
        2 => _ai(s),
        3 => _line(),
        _ => _done(s),
      },
    );
  }

  Widget _title(String t, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: displayStyle(context, 30)),
          const SizedBox(height: 8),
          Text(sub, style: TextStyle(color: context.c.muted, fontSize: 14.5)),
        ]),
      );

  Widget _welcome() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Setup · about 5 minutes'),
        const SizedBox(height: 10),
        _title('Let’s turn this computer into your AI phone.',
            'LocalAILine runs an AI that answers your calls and makes calls for you — all on this computer. You can change everything later.'),
        Grid(cols: 3, children: const [
          _Point(Icons.hearing, 'Hears', 'Understands callers, locally'),
          _Point(Icons.psychology_outlined, 'Thinks', 'A language model you choose'),
          _Point(Icons.record_voice_over_outlined, 'Speaks', 'Natural voices, no cloud'),
        ]),
        const SizedBox(height: 24),
        Btn('Start setup', kind: BtnKind.primary, large: true, onPressed: _next),
      ]);

  Widget _account() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Create your account', 'You’ll be the owner. You can add other people later.'),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Field(label: 'Your name', child: TextField(controller: name, enabled: owner == null)),
            const SizedBox(height: 14),
            Field(label: 'Username', child: TextField(controller: username, enabled: owner == null)),
            const SizedBox(height: 14),
            Field(
              label: 'Password',
              hint: 'At least 10 characters. Stored as an Argon2id hash on this computer.',
              child: TextField(controller: password, obscureText: true, enabled: owner == null, onSubmitted: (_) => _createOwner()),
            ),
            if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: LL.red))],
          ]),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Btn('Back', onPressed: () => setState(() => step--)),
          const SizedBox(width: 8),
          Btn(busy ? 'Creating…' : 'Create account', kind: BtnKind.primary, large: true, onPressed: busy ? null : _createOwner),
        ]),
      ]);

  Widget _ai(AppState s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Set up the AI', 'We checked this computer and picked what runs well here. Downloads happen once.'),
        const EngineSetupPanel(),
        const SizedBox(height: 22),
        Btn('Continue', kind: BtnKind.primary, large: true, onPressed: _next),
      ]);

  Widget _line() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Connect your phone line', 'You can do this later from “Phone line”. Try the assistant from this computer first.'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Supported', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Muted('Twilio · Telnyx · Vonage · Plivo · any SIP provider · a landline through an FXO box (e.g. Grandstream HT813)',
                size: 13.5),
          ]),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Btn('Skip for now', onPressed: _next),
          const SizedBox(width: 8),
          Btn('Connect a line after setup', kind: BtnKind.primary, large: true, onPressed: () {
            _next();
          }),
        ]),
      ]);

  Widget _done(AppState s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('You’re set up.', 'Talk to Ava now — as if you were calling — or give her instructions.'),
        Row(children: [
          Btn('Talk to Ava', icon: Icons.mic_none, kind: BtnKind.amber, large: true, onPressed: () async {
            await s.completeSetup(owner!);
            s.go(PageId.talk);
          }),
          const SizedBox(width: 8),
          Btn('Go to Home', kind: BtnKind.primary, large: true, onPressed: () => s.completeSetup(owner!)),
        ]),
      ]);
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.title, this.body);
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: context.c.amberInk),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Muted(body),
        ]),
      );
}

// ======================= Sign in =======================

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _signIn() async {
    final s = context.read<AppState>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final u = await s.auth.signIn(username.text, password.text);
      await s.db.seedDefaults(u.name);
      s.signedIn(u);
    } on AuthError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FullScreen(
        side: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Brand(),
          const SizedBox(height: 60),
          const Text.rich(TextSpan(
            style: TextStyle(fontFamily: LL.display, fontSize: 38, height: 1.05, fontWeight: FontWeight.w700, color: Colors.white),
            children: [TextSpan(text: 'Your computer\nanswers '), TextSpan(text: 'your phone.', style: TextStyle(color: LL.amber))],
          )),
          const SizedBox(height: 16),
          const Text('A private AI that answers and makes your calls. Models, calls and recordings stay on this machine.'),
        ]),
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sign in', style: displayStyle(context, 26)),
              const SizedBox(height: 20),
              Field(label: 'Username', child: TextField(controller: username, autofocus: true)),
              const SizedBox(height: 14),
              Field(label: 'Password', child: TextField(controller: password, obscureText: true, onSubmitted: (_) => _signIn())),
              if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: LL.red))],
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: Btn(busy ? 'Signing in…' : 'Sign in', kind: BtnKind.primary, large: true, onPressed: busy ? null : _signIn)),
              const SizedBox(height: 14),
              Muted('Forgot your password? Ask the owner of this computer to reset it in Users & access.'),
            ]),
          ),
        ),
      );
}
