# localailine_ui

LocalAILine's pages (Flutter): home, calls and the live view, the call flow, my assistant, build an app, phone lines, knowledge, tools and connectors, skills, users and the activity log.

The pages read an `AppModel` (`lib/app_model.dart`) from `Provider`, never a concrete engine, and import nothing from `dart:io`. So the same pages run:

- in the desktop app, where `AppState` (the engine in-process) is the `AppModel`;
- in a browser, where a remote model talks to an engine on a server.

An edition adds its own pages and panels with `UiExtras` (`lib/ui/extras.dart`). The desktop adds its local AI engines, voice server, hardware and paired phones.

```dart
MultiProvider(
  providers: [
    ListenableProvider<AppModel>.value(value: model),
    Provider<UiExtras>.value(value: const UiExtras()),
  ],
  child: const MaterialApp(home: Shell()),
);
```
