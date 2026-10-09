# localailine_core

The engine room of LocalAILine, in plain Dart (no Flutter).

| | |
|---|---|
| `services/agent_loop.dart` | One tool-calling loop for every model: streaming, tool-call assembly, tool selection for small models, warm-ups |
| `services/openai_compat.dart`, `cloud_llm.dart`, `ollama.dart`, `builtin_llm.dart` | LLM clients: any OpenAI-compatible server, cloud providers, Ollama, and a managed llama.cpp |
| `services/mcp/` | MCP client: HTTP, SSE and stdio transports, OAuth 2.1 with PKCE and dynamic registration |
| `services/knowledge/` | Documents to searchable knowledge: extraction (PDF, Word, Excel…), structure-aware chunking, hybrid search with local or OpenAI embeddings |
| `services/phone.dart`, `voice_engine.dart` | Twilio trunks and LiveKit SIP set-up; the local voice engine's processes |
| `services/auth.dart` | Users, roles, Argon2id passwords |
| `data/db.dart` | The SQLite database and its migrations (`Db.supportDir` chooses where it lives) |
| `notifier.dart` | A change notifier with Flutter's shape, without Flutter |

```dart
final loop = ToolLoop();
final target = OpenAiTarget(OpenAiServer(baseUrl: 'http://127.0.0.1:8000/v1', model: 'qwen3-4b'));
// loop.run(target, messages, tools: …) streams the answer and runs the tools it asks for.
```
