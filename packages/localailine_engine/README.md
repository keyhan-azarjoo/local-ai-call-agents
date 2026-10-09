# localailine_engine

`AppEngine`: everything LocalAILine does, with no user interface.

- the call flow (receptionist, specialists, people, hand-overs) and live calls;
- the per-turn call pipeline (`agentReply`) and its guards: the caller's own number forced into "my booking" tools, days and times taken from what was said, saving only on "yes", never speaking tool syntax, the goodbye;
- business apps, knowledge, MCP servers, phone lines, the voice engine's API (`engineRequest`);
- the spoken scenario runner used for testing.

The desktop app wraps it in `AppState`, which adds the Flutter parts. It also runs **headless** (no Flutter), for example on a home server with an OpenAI-compatible model server:

```dart
final engine = AppEngine(dbPath: '/data/localailine.db');
await engine.init();
```

Subclasses can serve the engine from elsewhere: `runsLocalEngines`, `configureServices` and `applyModelChoice` choose what runs on the machine and which models are used.

```bash
dart test   # boots the engine headless against a fake model server
```
