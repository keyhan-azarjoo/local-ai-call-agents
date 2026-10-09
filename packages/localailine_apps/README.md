# localailine_apps

Business apps from a description. One `AppSpec` (see `localailine_model`) becomes:

- **data** with the rules in code: no double-booking, opening hours, capacity, stock, stays, totals (`app_data.dart`);
- **a public website and a manager page**, served by `AppServer`, with PIN lockouts, upload limits and same-origin checks (`app_server.dart`);
- **MCP tools** for call agents: check, book, order, change, cancel; a caller only ever reaches their own records (`/mcp`, `/mcp/manager`);
- **the AI builder**: questions, a plan, the build, and changes in plain words (`apps_manager.dart`).

`AppsManager` runs several apps, each on its own port; behind a front door (another server in front of them), set `bindAddress` to loopback and pass requests to `handleSite`.
