/// Phone lines: who takes the calls on a line (its answer mode), and the settings of a line that
/// connects the person's own number through their phone provider (provider `sip`).
/// Pure logic, shared by the engine and the pages.
library;

// ---------------- who takes calls on a line ----------------

/// Who takes calls on a line, kept in the line's config as `answerMode`.
enum AnswerMode {
  /// The AI answers at once (what every line did before modes existed).
  ai('ai', 'AI answers'),

  /// Your paired devices and this computer ring. If nobody answers in time, the AI takes a message.
  ring('ring', 'Ring me'),

  /// Your devices ring first; after the line's ring time the AI answers as usual.
  ringThenAi('ring_then_ai', 'Ring me, then the AI'),

  /// Calls on this line are not answered here.
  off('off', 'Off');

  const AnswerMode(this.id, this.label);
  final String id;
  final String label;

  static AnswerMode parse(Object? v) => values.firstWhere((m) => m.id == '$v', orElse: () => ai);
}

/// A line's answer mode and ring time.
class LineAnswer {
  const LineAnswer(this.mode, {this.ringSeconds = defaultRingSeconds});

  final AnswerMode mode;

  /// How long your devices ring before the AI steps in (or takes a message).
  final int ringSeconds;

  static const defaultRingSeconds = 20;
  static const minRingSeconds = 5;
  static const maxRingSeconds = 120;

  /// From a line's config. Anything missing or unknown is today's behaviour: the AI answers.
  factory LineAnswer.of(Map<String, dynamic> cfg) {
    final s = cfg['ringSeconds'];
    final n = s is num ? s.toInt() : int.tryParse('${s ?? ''}');
    return LineAnswer(AnswerMode.parse(cfg['answerMode']), ringSeconds: (n ?? defaultRingSeconds).clamp(minRingSeconds, maxRingSeconds));
  }

  /// What is wrong with a ring time typed in the page (null: fine).
  static String? ringSecondsProblem(String text) {
    final n = int.tryParse(text.trim());
    if (n == null) return 'Enter the number of seconds, e.g. 20.';
    if (n < minRingSeconds || n > maxRingSeconds) return 'Choose between $minRingSeconds and $maxRingSeconds seconds.';
    return null;
  }

  Map<String, dynamic> applyTo(Map<String, dynamic> cfg) => {...cfg, 'answerMode': mode.id, 'ringSeconds': ringSeconds};

  /// What the voice worker is told for a new call on this line (null: answer at once, as before).
  ///  - `{"off": true}`: not answered here, hang up without a word;
  ///  - `{"wait": N, "then": "ai" | "message"}`: ring the owner first; wait until told (or N s).
  Map<String, Object>? plan() => switch (mode) {
        AnswerMode.ai => null,
        AnswerMode.off => const {'off': true},
        AnswerMode.ring => {'wait': ringSeconds, 'then': 'message'},
        AnswerMode.ringThenAi => {'wait': ringSeconds, 'then': 'ai'},
      };

  /// A short description for the line's page.
  String get summary => switch (mode) {
        AnswerMode.ai => 'The AI answers every call.',
        AnswerMode.ring => 'Your devices and this computer ring for $ringSeconds seconds. If nobody answers, the AI takes a message.',
        AnswerMode.ringThenAi => 'Your devices and this computer ring for $ringSeconds seconds, then the AI answers.',
        AnswerMode.off => 'Calls on this line are not answered here.',
      };
}

// ---------------- your own number, through your provider ----------------

/// A provider's usual settings, to fill in the form. They are a starting point only:
/// products differ and change, so the page says to check them with the provider.
class SipPreset {
  const SipPreset(this.id, this.name, {this.domain = '', this.port, this.transport = 'tls', this.note = ''});
  final String id, name, domain, transport, note;
  final int? port;
}

const sipPresets = <SipPreset>[
  SipPreset('generic', 'Any SIP provider', note: 'Use the SIP server, username and password from your provider’s “SIP device” or “SIP phone” settings. Prefer TLS, then TCP.'),
  SipPreset('sipgate_uk', 'sipgate (UK)', domain: 'sipgate.co.uk', port: 5060, transport: 'tcp', note: 'Username is your SIP-ID (e.g. 1234567e0). TLS on some plans.'),
  SipPreset('sipgate_de', 'sipgate (Germany)', domain: 'sipgate.de', port: 5060, transport: 'tcp', note: 'Username is your SIP-ID. TLS on some plans.'),
  SipPreset('telnyx', 'Telnyx', domain: 'sip.telnyx.com', port: 5061, transport: 'tls', note: 'Use a credential SIP connection’s username and password.'),
  SipPreset('vonage', 'Vonage Business', port: 5060, transport: 'tcp', note: 'Use a “SIP device / BYOD” login from the admin portal; the server comes with it.'),
  SipPreset('bt', 'BT Cloud Voice', port: 5060, transport: 'tcp', note: 'Only where BT gives SIP details for a third-party SIP device. Home Digital Voice lines usually don’t.'),
  SipPreset('zen', 'Zen Internet (UK)', port: 5060, transport: 'udp', note: 'Server and account number from Zen’s VoIP setup sheet.'),
];

/// The settings of a `sip` line: the person's own number, signed in to their provider.
class SipLine {
  const SipLine({
    required this.number,
    required this.domain,
    this.port,
    this.transport = 'tls',
    required this.username,
    this.authUsername = '',
    required this.password,
    this.outboundProxy = '',
    this.preset = 'generic',
  });

  final String number, domain, transport, username, authUsername, password, outboundProxy, preset;
  final int? port;

  static const transports = ['tls', 'tcp', 'udp'];

  /// From a line's config (also lines saved before this type could connect: server, sipUser, sipPass).
  factory SipLine.of(Map<String, dynamic> cfg) {
    String s(String k, [String? old]) => '${cfg[k] ?? (old == null ? null : cfg[old]) ?? ''}'.trim();
    final p = cfg['port'];
    final t = s('transport').toLowerCase();
    return SipLine(
      number: s('number'),
      domain: s('domain', 'server'),
      port: p is num ? p.toInt() : int.tryParse('${p ?? ''}'),
      transport: transports.contains(t) ? t : 'tls',
      username: s('username', 'sipUser'),
      authUsername: s('authUsername'),
      password: '${cfg['password'] ?? cfg['sipPass'] ?? ''}',
      outboundProxy: s('outboundProxy'),
      preset: s('preset').isEmpty ? 'generic' : s('preset'),
    );
  }

  /// The port used: the one given, else 5061 for TLS and 5060 otherwise.
  int get effectivePort => port ?? (transport == 'tls' ? 5061 : 5060);

  Map<String, dynamic> toConfig() => {
        'number': number,
        'preset': preset,
        'domain': domain,
        'port': ?port,
        'transport': transport,
        'username': username,
        if (authUsername.isNotEmpty) 'authUsername': authUsername,
        'password': password,
        if (outboundProxy.isNotEmpty) 'outboundProxy': outboundProxy,
      };

  static final _number = RegExp(r'^\+[1-9][0-9]{6,14}$');
  static final _host = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$');
  static final _user = RegExp(r"^[A-Za-z0-9!$&'()*+,;=?/._~%-]{1,128}$");

  /// What is wrong, in plain words (null: all fine). [needPassword] false when editing a saved
  /// line and leaving the password empty to keep it.
  String? problem({bool needPassword = true}) {
    if (number.isEmpty) return 'Add your phone number.';
    if (!_number.hasMatch(number)) return 'Write the number with its country code, e.g. +44 7700 900123 (not starting with 0).';
    if (domain.isEmpty) return 'Add your provider’s SIP server (the “registrar” or “domain”, e.g. sip.example.com).';
    if (!_host.hasMatch(domain) || domain.contains('..')) return 'The SIP server should be a name like sip.example.com or an IP address, without “sip:” or a port.';
    if (port != null && (port! < 1 || port! > 65535)) return 'The port should be between 1 and 65535 (usually 5061 for TLS, 5060 otherwise).';
    if (username.isEmpty) return 'Add the SIP username your provider gave you.';
    if (!_user.hasMatch(username)) return 'The username has characters a SIP username can’t have. Copy it again from your provider.';
    if (authUsername.isNotEmpty && !_user.hasMatch(authUsername)) return 'The authentication username has characters that aren’t allowed.';
    if (needPassword && password.isEmpty) return 'Add the SIP password.';
    if (password.length > 256) return 'That password is too long.';
    if (outboundProxy.isNotEmpty) {
      final parts = outboundProxy.split(':');
      final okPort = parts.length == 1 || (parts.length == 2 && (int.tryParse(parts[1]) ?? 0) > 0 && int.parse(parts[1]) <= 65535);
      if (parts.length > 2 || !okPort || !_host.hasMatch(parts.first)) return 'The outbound proxy should be a host, or host:port.';
    }
    return null;
  }

  /// The line as the phone gateway takes it (PUT /v1/accounts/{id}). An empty password keeps the
  /// one the gateway already has.
  Map<String, Object> toGatewayAccount({required bool on}) => {
        'number': number,
        'domain': domain.toLowerCase(),
        'port': effectivePort,
        'transport': transport,
        'username': username,
        if (authUsername.isNotEmpty) 'auth_username': authUsername,
        if (password.isNotEmpty) 'password': password,
        if (outboundProxy.isNotEmpty) 'outbound_proxy': outboundProxy,
        'mode': on ? 'on' : 'off',
      };

  /// The gateway's name for line [lineId].
  static String gatewayId(int lineId) => 'line$lineId';
}

/// "+44 7700 900123", "0044…" → "+447700900123". Numbers need their country code.
String normalizePhoneNumber(String n) {
  final t = n.trim();
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (t.startsWith('+')) return '+$digits';
  if (t.startsWith('00') && digits.length > 2) return '+${digits.substring(2)}';
  return digits;
}

/// A `sip` line's sign-in state, from the phone gateway.
class SipLineStatus {
  const SipLineStatus(this.state, [this.detail = '']);

  /// registering | registered | failed | off | stopped (the gateway isn't running)
  final String state;
  final String detail;

  factory SipLineStatus.fromGateway(Map<String, dynamic> view) {
    final st = (view['status'] as Map?) ?? const {};
    return SipLineStatus('${st['state'] ?? 'registering'}', '${st['last_error'] ?? ''}');
  }

  String get words => switch (state) {
        'registered' => 'Connected: calls to this number come here',
        'registering' => 'Signing in to your provider…',
        'failed' => detail.isEmpty ? 'Couldn’t sign in to your provider' : 'Couldn’t sign in: $detail',
        'off' => 'Off: calls go to your other phones as before',
        _ => 'Not connected while the phone gateway is stopped',
      };
}
