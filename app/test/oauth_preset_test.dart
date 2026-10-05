import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine/services/mcp/mcp_auth.dart';

void main() {
  test('pre-registered sign-in (Google style): no registration, secret sent, offline access asked', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, String>? tokenForm;
    server.listen((req) async {
      if (req.uri.path == '/token') {
        tokenForm = Uri.splitQueryString(await utf8.decodeStream(req));
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'access_token': 'at-1', 'refresh_token': 'rt-1', 'expires_in': 3600}));
      } else {
        req.response.statusCode = 404; // a registration attempt would land here
      }
      await req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    Uri? opened;
    final oauth = McpOAuth(openBrowser: (url) async {
      opened = Uri.parse(url);
      final q = opened!.queryParameters;
      // The browser comes back to the app with a code.
      await http.get(Uri.parse('${q['redirect_uri']}?code=c-1&state=${q['state']}'));
    });
    final prev = McpAuthState(preset: {
      'authorization_endpoint': '$base/auth',
      'token_endpoint': '$base/token',
      'scope': 'https://www.googleapis.com/auth/calendar',
      'client_id': 'my-client',
      'client_secret': 'my-secret',
      'params': {'access_type': 'offline', 'prompt': 'consent'},
    });
    final s = await oauth.signIn('https://calendarmcp.googleapis.com/mcp/v1', null, prev);
    expect(opened!.queryParameters['client_id'], 'my-client');
    expect(opened!.queryParameters['access_type'], 'offline');
    expect(opened!.queryParameters['scope'], contains('calendar'));
    expect(tokenForm!['client_secret'], 'my-secret');
    expect(s.accessToken, 'at-1');
    expect(s.refreshToken, 'rt-1');
    // The setup survives saving, so refresh and sign-out keep working.
    expect(McpAuthState.fromJson(jsonDecode(jsonEncode(s.toJson()))).preset!['client_id'], 'my-client');
    await server.close(force: true);
  });
}
