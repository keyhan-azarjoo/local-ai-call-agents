"""Test MCP server with OAuth, shaped like a real hosted MCP:
- MCP (streamable HTTP) on :8771/mcp, 401 + resource_metadata until signed in
- Sign-in server on :8772 with dynamic client registration, PKCE (S256), refresh tokens
- /authorize auto-approves (no login form) so tests can follow the redirect
Run: python3 oauth_mcp_server.py
"""
import base64, hashlib, json, secrets, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from mcp.server.auth.provider import AccessToken, TokenVerifier
from mcp.server.auth.settings import AuthSettings
from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

AS = "http://127.0.0.1:8772"
RS = "http://127.0.0.1:8771"
clients, codes, tokens, refresh = {}, {}, {}, {}
weights = {"lot-7": 412.5}


class Auth(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _json(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/.well-known/oauth-authorization-server":
            return self._json(200, {
                "issuer": AS, "authorization_endpoint": AS + "/oauth/authorize",
                "token_endpoint": AS + "/oauth/token", "registration_endpoint": AS + "/oauth/register",
                "response_types_supported": ["code"], "grant_types_supported": ["authorization_code", "refresh_token"],
                "code_challenge_methods_supported": ["S256"], "token_endpoint_auth_methods_supported": ["none"]})
        if u.path == "/oauth/authorize":
            q = dict(urllib.parse.parse_qsl(u.query))
            c = clients.get(q.get("client_id"))
            if not c or q.get("redirect_uri") not in c["redirect_uris"] or q.get("code_challenge_method") != "S256":
                return self._json(400, {"error": "invalid_request"})
            code = secrets.token_urlsafe(16)
            codes[code] = (q["client_id"], q["redirect_uri"], q["code_challenge"], q.get("resource"))
            loc = q["redirect_uri"] + "?" + urllib.parse.urlencode({"code": code, "state": q.get("state", "")})
            self.send_response(302); self.send_header("Location", loc); self.end_headers(); return
        self._json(404, {"error": "not_found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); raw = self.rfile.read(n).decode()
        u = urllib.parse.urlparse(self.path)
        if u.path == "/oauth/register":
            body = json.loads(raw); cid = "c_" + secrets.token_hex(6)
            clients[cid] = {"redirect_uris": body["redirect_uris"]}
            return self._json(201, {"client_id": cid, **body})
        if u.path == "/oauth/token":
            f = dict(urllib.parse.parse_qsl(raw))
            if f.get("grant_type") == "authorization_code":
                cid, redir, chal, res = codes.pop(f.get("code"), (None,) * 4)
                calc = base64.urlsafe_b64encode(hashlib.sha256(f.get("code_verifier", "").encode()).digest()).rstrip(b"=").decode()
                if cid != f.get("client_id") or redir != f.get("redirect_uri") or calc != chal:
                    return self._json(400, {"error": "invalid_grant"})
            elif f.get("grant_type") == "refresh_token":
                if refresh.pop(f.get("refresh_token"), None) != f.get("client_id"):
                    return self._json(400, {"error": "invalid_grant"})
            else:
                return self._json(400, {"error": "unsupported_grant_type"})
            at, rt = "at_" + secrets.token_hex(8), "rt_" + secrets.token_hex(8)
            tokens[at] = time.time() + 3600; refresh[rt] = f["client_id"]
            return self._json(200, {"access_token": at, "token_type": "Bearer", "expires_in": 3600, "refresh_token": rt})
        self._json(404, {"error": "not_found"})


class Verifier(TokenVerifier):
    async def verify_token(self, token: str):
        if tokens.get(token, 0) > time.time():
            return AccessToken(token=token, client_id="x", scopes=[], expires_at=int(tokens[token]))
        return None


mcp = FastMCP("Test Weighing", token_verifier=Verifier(), host="127.0.0.1", port=8771,
              auth=AuthSettings(issuer_url=AS, resource_server_url=RS, required_scopes=[]))


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
def get_weight(lot: str) -> str:
    """Current weight of a lot in kilograms."""
    return f"{lot}: {weights.get(lot, 0)} kg"


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=False))
def record_weight(lot: str, kg: float) -> str:
    """Record a new weight for a lot."""
    weights[lot] = kg
    return f"Recorded {kg} kg for {lot}"


if __name__ == "__main__":
    threading.Thread(target=ThreadingHTTPServer(("127.0.0.1", 8772), Auth).serve_forever, daemon=True).start()
    mcp.run(transport="streamable-http")
