# localailine_model

The shared language of LocalAILine: plain types and pure logic with no `dart:io`, so they work in a server, a desktop app and a browser alike.

- **Chat and models:** `ChatMessage`, LLM settings (`OpenAiServer`, `CloudConfig`), the model `Catalog`.
- **People:** `User`, `Role`, permissions.
- **Tools:** `McpTool`, `McpServer`, `ToolBinding`, `ToolEvent`, argument and result helpers.
- **Business apps:** `AppSpec` (tables, fields, access, pages, look), the 11 templates, site styles, the AI app builder's prompts and repairs, and the generated website and manager page (`app_web.dart`).
- **The app:** `PageId`, `LiveLine`, voices and languages.
- **Service interfaces** (`api.dart`): `DataApi`, `AuthApi`, `McpApi`, `KnowledgeApi`, `AppsApi`. The engine's services implement them; a remote client implements them over the network.

```dart
import 'package:localailine_model/apps/app_templates.dart';
import 'package:localailine_model/apps/app_web.dart';

final barber = appTemplates.firstWhere((t) => t.id == 'barber');
// The same spec drives the website, the manager page and the MCP tools.
```
