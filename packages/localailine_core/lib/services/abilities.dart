import 'dart:convert';

import '../data/db.dart';
import 'agent_loop.dart';
import 'package:localailine_model/agent_templates.dart' show abilityLabels;

import 'mcp/mcp_client.dart';

/// Things an agent can do on a call without any connected system: they're saved on this computer
/// and show up in Calls → "Messages, bookings and orders".
class Abilities {
  static const serverId = -10;

  static const labels = abilityLabels;

  static McpTool _tool(String name, String description, Map<String, Object?> props, List<String> required) => McpTool(
        name: name,
        description: description,
        inputSchema: {'type': 'object', 'properties': props, 'required': required},
        readOnly: false,
        autoApprove: true, // the caller asked for it; the owner sees it in Calls
      );

  static final _tools = {
    'message': _tool('take_message', 'Save a message for the owner/staff, e.g. a call-back request. Ask for their name and number first.', {
      'name': {'type': 'string', 'description': 'Caller name'},
      'phone': {'type': 'string', 'description': 'Number to call back'},
      'message': {'type': 'string', 'description': 'The message, in a sentence or two'},
      'urgent': {'type': 'boolean'},
    }, ['message']),
    'booking': _tool('book', 'Save a booking (appointment, table or visit). Confirm the details back with the caller first.', {
      'name': {'type': 'string'},
      'phone': {'type': 'string'},
      'when': {'type': 'string', 'description': 'Date and time, e.g. 2026-10-07 19:00'},
      'service': {'type': 'string', 'description': 'What it is for: table for 4, haircut, check-up…'},
      'people': {'type': 'integer'},
      'notes': {'type': 'string'},
    }, ['name', 'when']),
    'order': _tool('place_order', 'Save an order once the caller has confirmed the items and total.', {
      'name': {'type': 'string'},
      'phone': {'type': 'string'},
      'items': {'type': 'string', 'description': 'Items with quantities and prices'},
      'total': {'type': 'string', 'description': 'Total with currency'},
      'delivery': {'type': 'string', 'description': 'Delivery address and postcode, or "collection"'},
      'notes': {'type': 'string', 'description': 'Allergies, timing, payment'},
    }, ['items']),
  };

  static List<ToolBinding> bindings(Iterable<String> which) => [
        for (final k in which)
          if (_tools[k] != null) ToolBinding(serverId: serverId, serverName: 'This app', tool: _tools[k]!, fnName: _tools[k]!.name),
      ];

  /// Saves what the caller asked for.
  static Future<({String text, bool isError})> run(Db db, String tool, Map<String, dynamic> a, {String? agent}) async {
    final kind = switch (tool) { 'take_message' => 'message', 'book' => 'booking', 'place_order' => 'order', _ => null };
    if (kind == null) return (text: 'Unknown action $tool', isError: true);
    // Items and totals come as text or as lists/numbers: say them plainly.
    String plain(Object? v) {
      if (v is List) {
        return v.map((i) {
          if (i is! Map) return '$i';
          final q = i['quantity'] ?? i['qty'];
          final price = i['price'];
          return '${q == null ? '' : '$q × '}${i['name'] ?? i['item'] ?? ''}${price == null ? '' : ' (${price is num ? price.toStringAsFixed(2) : price})'}';
        }).join(', ');
      }
      if (v is num) return v.toStringAsFixed(2);
      return v == null ? '' : '$v';
    }

    a = {...a, if (a['items'] != null) 'items': plain(a['items']), if (a['total'] != null) 'total': plain(a['total'])};
    final summary = switch (kind) {
      'message' => '${a['urgent'] == true ? 'URGENT: ' : ''}${a['message'] ?? ''}',
      'booking' => '${a['service'] ?? 'Booking'}${a['people'] != null ? ' for ${a['people']}' : ''} · ${a['when'] ?? ''}',
      _ => '${a['items'] ?? ''}${a['total'] != null ? ' · ${a['total']}' : ''}${a['delivery'] != null ? ' · ${a['delivery']}' : ''}',
    };
    final id = await db.insert('requests', {
      'kind': kind,
      'name': a['name']?.toString(),
      'phone': a['phone']?.toString(),
      'summary': summary.trim(),
      'details': jsonEncode(a),
      'agent': agent,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.audit(agent ?? 'Ava', 'Saved a $kind: $summary');
    return (text: 'Saved (${kind == 'message' ? 'message' : kind} #$id). Tell the caller it’s done.', isError: false);
  }
}
