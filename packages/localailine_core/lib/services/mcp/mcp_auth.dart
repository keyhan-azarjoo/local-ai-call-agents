import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Saved sign-in for one MCP server (OAuth 2.1, as the MCP spec requires).
class McpAuthState {
  McpAuthState({
    this.clientId,
    this.redirectUri,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.tokenEndpoint,
    this.resource,
    this.preset,
  });

  String? clientId, redirectUri, accessToken, refreshToken, tokenEndpoint, resource;

  /// A sign-in known in advance, for services without automatic app registration (e.g. Google):
  /// authorization_endpoint, token_endpoint, scope, client_id, client_secret, params.
  Map<String, dynamic>? preset;
  int? expiresAt; // ms since epoch

  bool get hasToken => accessToken != null && accessToken!.isNotEmpty;
  bool get expired => expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt! - 30000;

  Map<String, Object?> toJson() => {
        'clientId': clientId,
        'redirectUri': redirectUri,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt,
        'tokenEndpoint': tokenEndpoint,
        'resource': resource,
        'preset': ?preset,
      };

  static McpAuthState fromJson(Map<String, dynamic>? j) => McpAuthState(
        clientId: j?['clientId'],
        redirectUri: j?['redirectUri'],
        accessToken: j?['accessToken'],
        refreshToken: j?['refreshToken'],
        expiresAt: j?['expiresAt'],
        tokenEndpoint: j?['tokenEndpoint'],
        resource: j?['resource'],
        preset: (j?['preset'] as Map?)?.cast<String, dynamic>(),
      );
}

class McpAuthError implements Exception {
  McpAuthError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// OAuth for MCP servers: discovery → dynamic client registration →
/// authorization code + PKCE in the user's browser → tokens, with refresh.
class McpOAuth {
  McpOAuth({http.Client? client, required this.openBrowser}) : _c = client ?? http.Client();
  final http.Client _c;

  /// Opens the sign-in page. Tests replace this.
  final Future<void> Function(String url) openBrowser;

  static const _ports = [33418, 33419, 33420];

  /// Reads `resource_metadata="..."` and `scope="..."` from a 401 header.
  static (String?, String?) parseChallenge(String? header) {
    if (header == null) return (null, null);
    String? v(String k) => RegExp('$k="([^"]+)"').firstMatch(header)?.group(1);
    return (v('resource_metadata'), v('scope'));
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final r = await _c.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Finds the authorization server for an MCP endpoint.
  Future<({Map<String, dynamic> as, String? resource, String? scope})> discover(String mcpUrl, String? wwwAuthenticate) async {
    final u = Uri.parse(mcpUrl);
    final origin = '${u.scheme}://${u.authority}';
    final (metaUrl, challengeScope) = parseChallenge(wwwAuthenticate);
    Map<String, dynamic>? prm;
    for (final url in [
      ?metaUrl,
      '$origin/.well-known/oauth-protected-resource${u.path == '/' ? '' : u.path}',
      '$origin/.well-known/oauth-protected-resource',
    ]) {
      prm = await _getJson(url);
      if (prm != null) break;
    }
    final issuer = (prm?['authorization_servers'] as List?)?.cast<String>().firstOrNull ?? origin;
    final iu = Uri.parse(issuer);
    final io = '${iu.scheme}://${iu.authority}';
    final ip = iu.path == '/' ? '' : iu.path;
    Map<String, dynamic>? as;
    for (final url in [
      '$io/.well-known/oauth-authorization-server$ip',
      '$io/.well-known/openid-configuration$ip',
      if (ip.isNotEmpty) '$issuer/.well-known/openid-configuration',
    ]) {
      as = await _getJson(url);
      if (as != null) break;
    }
    // Older servers without metadata: default endpoint paths.
    as ??= {
      'authorization_endpoint': '$io/authorize',
      'token_endpoint': '$io/token',
      'registration_endpoint': '$io/register',
    };
    final scopes = (prm?['scopes_supported'] as List?)?.cast<String>();
    return (as: as, resource: prm?['resource'] as String?, scope: challengeScope ?? scopes?.join(' '));
  }

  Future<HttpServer> _bindLoopback() async {
    for (final p in _ports) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, p);
      } catch (_) {}
    }
    return HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  }

  static String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  static String _random(int n) {
    final r = Random.secure();
    return _b64url(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// Full interactive sign-in. Returns the new auth state.
  Future<McpAuthState> signIn(String mcpUrl, String? wwwAuthenticate, McpAuthState prev) async {
    final preset = prev.preset;
    final d = preset != null
        ? (as: preset, resource: null as String?, scope: preset['scope'] as String?)
        : await discover(mcpUrl, wwwAuthenticate);
    final authEndpoint = d.as['authorization_endpoint'] as String?;
    final tokenEndpoint = d.as['token_endpoint'] as String?;
    final clientSecret = preset?['client_secret'] as String?;
    if (authEndpoint == null || tokenEndpoint == null) throw McpAuthError('The server’s sign-in details are incomplete.');

    final server = await _bindLoopback();
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';
    try {
      // Register this app with the sign-in server (once per redirect address).
      var clientId = (preset?['client_id'] as String?) ?? (prev.redirectUri == redirectUri ? prev.clientId : null);
      if (clientId == null) {
        final reg = d.as['registration_endpoint'] as String?;
        if (reg == null) throw McpAuthError('This server needs a pre-registered app. Use “API key or token” instead.');
        final r = await _c.post(Uri.parse(reg),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'client_name': 'LocalAILine',
              'redirect_uris': [redirectUri],
              'grant_types': ['authorization_code', 'refresh_token'],
              'response_types': ['code'],
              'token_endpoint_auth_method': 'none',
            }));
        if (r.statusCode != 200 && r.statusCode != 201) throw McpAuthError('Could not register with the sign-in server (${r.statusCode}).');
        clientId = (jsonDecode(r.body) as Map)['client_id'] as String;
      }

      final verifier = _random(48);
      final challenge = _b64url((await Sha256().hash(utf8.encode(verifier))).bytes);
      final state = _random(16);
      final url = Uri.parse(authEndpoint).replace(queryParameters: {
        ...Uri.parse(authEndpoint).queryParameters,
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        if (d.scope != null && d.scope!.isNotEmpty) 'scope': d.scope!,
        if (d.resource != null) 'resource': d.resource!,
        ...?(preset?['params'] as Map?)?.cast<String, String>(),
      });

      final codeFuture = server.firstWhere((req) => req.uri.path == '/callback').then((req) async {
        final q = req.uri.queryParameters;
        final ok = q['code'] != null && q['state'] == state;
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<html><body style="font-family:sans-serif;padding:40px">'
              '<h2>${ok ? 'Signed in to LocalAILine' : 'Sign-in failed'}</h2>'
              '<p>${ok ? 'You can close this window and go back to the app.' : (q['error_description'] ?? q['error'] ?? 'Please try again.')}</p></body></html>');
        await req.response.close();
        if (!ok) throw McpAuthError('Sign-in was cancelled or failed: ${q['error'] ?? 'no code'}');
        return q['code']!;
      });

      await openBrowser(url.toString());
      final code = await codeFuture.timeout(const Duration(minutes: 5), onTimeout: () => throw McpAuthError('Sign-in timed out.'));

      final t = await _c.post(Uri.parse(tokenEndpoint), body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'client_secret': ?clientSecret,
        'code_verifier': verifier,
        if (d.resource != null) 'resource': d.resource!,
      });
      if (t.statusCode != 200) {
        var why = '';
        try {
          final j = jsonDecode(t.body) as Map;
          why = ': ${j['error_description'] ?? j['error'] ?? ''}';
        } catch (_) {}
        throw McpAuthError('The sign-in server refused the login (${t.statusCode}$why).');
      }
      return _fromToken(jsonDecode(t.body) as Map<String, dynamic>, clientId, redirectUri, tokenEndpoint, d.resource, null)..preset = preset;
    } finally {
      await server.close(force: true);
    }
  }

  /// Uses the refresh token. Returns null when the user must sign in again.
  Future<McpAuthState?> refresh(McpAuthState s) async {
    if (s.refreshToken == null || s.tokenEndpoint == null || s.clientId == null) return null;
    try {
      final t = await _c.post(Uri.parse(s.tokenEndpoint!), body: {
        'grant_type': 'refresh_token',
        'refresh_token': s.refreshToken!,
        'client_id': s.clientId!,
        'client_secret': ?(s.preset?['client_secret'] as String?),
        if (s.resource != null) 'resource': s.resource!,
      });
      if (t.statusCode != 200) return null;
      return _fromToken(jsonDecode(t.body) as Map<String, dynamic>, s.clientId!, s.redirectUri, s.tokenEndpoint!, s.resource, s.refreshToken)..preset = s.preset;
    } catch (_) {
      return null;
    }
  }

  McpAuthState _fromToken(Map<String, dynamic> j, String clientId, String? redirect, String tokenEndpoint, String? resource, String? oldRefresh) =>
      McpAuthState(
        clientId: clientId,
        redirectUri: redirect,
        accessToken: j['access_token'] as String?,
        refreshToken: (j['refresh_token'] as String?) ?? oldRefresh,
        expiresAt: j['expires_in'] == null ? null : DateTime.now().millisecondsSinceEpoch + (j['expires_in'] as num).toInt() * 1000,
        tokenEndpoint: tokenEndpoint,
        resource: resource,
      );
}
