/// Ready-made connectors: popular services, set up so adding one is a click (and a sign-in).
///
/// - [ConnectorKind.signIn]: the service's own MCP server; you log in in your browser.
/// - [ConnectorKind.google]: Google's MCP servers; you log in with your own Google Cloud app.
/// - [ConnectorKind.email]: any mailbox by IMAP/SMTP (an app password), run on this computer.
/// - [ConnectorKind.token]: the service's MCP server with a personal access token.
/// - [ConnectorKind.local]: runs on this computer (files, Apple Calendar & Reminders).
enum ConnectorKind { signIn, google, email, token, local }

class Connector {
  const Connector(this.id, this.name, this.category, this.about, this.kind, {this.url, this.scope, this.command, this.mail, this.tokenHelp});
  final String id, name, category, about;
  final ConnectorKind kind;
  final String? url; // remote MCP server
  final String? scope; // Google OAuth scopes
  final String? command; // local MCP server
  final ({String imap, int imapPort, String smtp, int smtpPort, bool smtpTls, String help})? mail;
  final String? tokenHelp;

  /// What the server row stores as its target (also used to see if it's already added).
  String get target => url ?? command ?? 'npx -y mcp-mail-server #$id';
}

const googleAuth = 'https://accounts.google.com/o/oauth2/v2/auth';
const googleToken = 'https://oauth2.googleapis.com/token';

const connectors = <Connector>[
  // ---- Email & calendar
  Connector('gmail', 'Gmail', 'Email & calendar', 'Read, search, label and draft emails.', ConnectorKind.google,
      url: 'https://gmailmcp.googleapis.com/mcp/v1', scope: 'https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.compose'),
  Connector('gcal', 'Google Calendar', 'Email & calendar', 'See, create and move events; find free time.', ConnectorKind.google,
      url: 'https://calendarmcp.googleapis.com/mcp/v1', scope: 'https://www.googleapis.com/auth/calendar'),
  Connector('gdrive', 'Google Drive', 'Email & calendar', 'Find, read and organise files in Drive.', ConnectorKind.google,
      url: 'https://drivemcp.googleapis.com/mcp/v1', scope: 'https://www.googleapis.com/auth/drive'),
  Connector('outlook', 'Outlook / Microsoft 365 mail', 'Email & calendar', 'Read, search, send and reply to email.', ConnectorKind.email,
      mail: (imap: 'outlook.office365.com', imapPort: 993, smtp: 'smtp.office365.com', smtpPort: 587, smtpTls: false,
          help: 'Use your email address and an app password (account.microsoft.com → Security → App passwords). Work accounts need IMAP allowed by the admin.')),
  Connector('icloud', 'iCloud Mail', 'Email & calendar', 'Read, search, send and reply to email.', ConnectorKind.email,
      mail: (imap: 'imap.mail.me.com', imapPort: 993, smtp: 'smtp.mail.me.com', smtpPort: 587, smtpTls: false,
          help: 'Use your iCloud email and an app-specific password (account.apple.com → Sign-In and Security → App-Specific Passwords).')),
  Connector('yahoo', 'Yahoo Mail', 'Email & calendar', 'Read, search, send and reply to email.', ConnectorKind.email,
      mail: (imap: 'imap.mail.yahoo.com', imapPort: 993, smtp: 'smtp.mail.yahoo.com', smtpPort: 465, smtpTls: true,
          help: 'Use your Yahoo email and an app password (Account security → Generate app password).')),
  Connector('imap', 'Any email (IMAP)', 'Email & calendar', 'Any mailbox with IMAP and SMTP — work, hosting or ISP email.', ConnectorKind.email,
      mail: (imap: '', imapPort: 993, smtp: '', smtpPort: 465, smtpTls: true, help: 'Your provider’s IMAP and SMTP servers are in its help pages or mail settings.')),
  Connector('apple-cal', 'Apple Calendar & Reminders', 'Email & calendar', 'Calendars and reminders on this Mac (including iCloud, Google and Exchange ones added to Calendar).',
      ConnectorKind.local, command: 'npx -y mcp-server-apple-events'),

  // ---- Work & notes
  Connector('notion', 'Notion', 'Work & notes', 'Search and edit pages and databases.', ConnectorKind.signIn, url: 'https://mcp.notion.com/mcp'),
  Connector('atlassian', 'Jira & Confluence', 'Work & notes', 'Issues, projects and wiki pages.', ConnectorKind.signIn, url: 'https://mcp.atlassian.com/v1/mcp'),
  Connector('linear', 'Linear', 'Work & notes', 'Issues, projects and cycles.', ConnectorKind.signIn, url: 'https://mcp.linear.app/mcp'),
  Connector('asana', 'Asana', 'Work & notes', 'Tasks, projects and goals.', ConnectorKind.signIn, url: 'https://mcp.asana.com/sse'),
  Connector('monday', 'monday.com', 'Work & notes', 'Boards, items and updates.', ConnectorKind.signIn, url: 'https://mcp.monday.com/mcp'),
  Connector('clickup', 'ClickUp', 'Work & notes', 'Tasks, lists and docs.', ConnectorKind.signIn, url: 'https://mcp.clickup.com/mcp'),
  Connector('airtable', 'Airtable', 'Work & notes', 'Bases, tables and records.', ConnectorKind.signIn, url: 'https://mcp.airtable.com/mcp'),
  Connector('dropbox', 'Dropbox', 'Work & notes', 'Find and read files.', ConnectorKind.signIn, url: 'https://mcp.dropbox.com/mcp'),
  Connector('intercom', 'Intercom', 'Work & notes', 'Customer conversations and contacts.', ConnectorKind.signIn, url: 'https://mcp.intercom.com/mcp'),

  // ---- Sales & payments
  Connector('stripe', 'Stripe', 'Sales & payments', 'Customers, payments, invoices and refunds.', ConnectorKind.signIn, url: 'https://mcp.stripe.com'),
  Connector('paypal', 'PayPal', 'Sales & payments', 'Invoices, orders and transactions.', ConnectorKind.signIn, url: 'https://mcp.paypal.com/mcp'),
  Connector('square', 'Square', 'Sales & payments', 'Orders, payments, customers and bookings.', ConnectorKind.signIn, url: 'https://mcp.squareup.com/mcp'),

  // ---- Build & run
  Connector('github', 'GitHub', 'Build & run', 'Repositories, issues and pull requests.', ConnectorKind.token,
      url: 'https://api.githubcopilot.com/mcp/', tokenHelp: 'A personal access token from github.com → Settings → Developer settings → Personal access tokens.'),
  Connector('sentry', 'Sentry', 'Build & run', 'Errors and performance issues.', ConnectorKind.signIn, url: 'https://mcp.sentry.dev/mcp'),
  Connector('vercel', 'Vercel', 'Build & run', 'Projects, deployments and logs.', ConnectorKind.signIn, url: 'https://mcp.vercel.com'),
  Connector('cloudflare', 'Cloudflare', 'Build & run', 'Workers, DNS and analytics.', ConnectorKind.signIn, url: 'https://mcp.cloudflare.com/mcp'),
  Connector('supabase', 'Supabase', 'Build & run', 'Databases and projects.', ConnectorKind.token,
      url: 'https://mcp.supabase.com/mcp', tokenHelp: 'A personal access token from supabase.com/dashboard/account/tokens.'),

  // ---- Design & web
  Connector('canva', 'Canva', 'Design & web', 'Designs and brand assets.', ConnectorKind.signIn, url: 'https://mcp.canva.com/mcp'),
  Connector('webflow', 'Webflow', 'Design & web', 'Sites, pages and CMS items.', ConnectorKind.signIn, url: 'https://mcp.webflow.com/mcp'),

  // ---- Automation & this computer
  Connector('zapier', 'Zapier', 'Automation', 'Thousands of apps through your Zapier actions.', ConnectorKind.signIn, url: 'https://mcp.zapier.com/api/mcp/mcp'),
  Connector('files', 'Files on this computer', 'Automation', 'Read and organise files in a folder you choose.', ConnectorKind.local,
      command: 'npx -y @modelcontextprotocol/server-filesystem'),
];
