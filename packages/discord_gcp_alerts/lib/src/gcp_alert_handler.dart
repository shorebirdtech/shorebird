import 'dart:convert';
import 'dart:io';

import 'package:discord_gcp_alerts/discord_gcp_alerts.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

/// A handler which notifies a Discord channel of a GCP alert.
Handler gcpAlertHandler({required String webhookUrl, http.Client? client}) {
  return (Request req) async {
    final body = await req.readAsString();
    final notification = GCPAlert.fromJson(
      json.decode(body) as Map<String, dynamic>,
    );
    final incident = notification.incident;
    final summary = incident?.summary;
    final state = incident?.state;
    final url = incident?.url;
    final resource = incident?.resourceName;
    final conditionName = incident?.conditionName;
    final policyName = incident?.policyName ?? '--';
    final discordPayload = {
      'embeds': [
        {
          'title': '🚨 $policyName 🚨',
          'description': summary,
          'url': url,
          'color': 0xFF0000,
          'fields': [
            {'name': 'State', 'value': state, 'inline': true},
            {'name': 'Resource', 'value': resource, 'inline': true},
            {'name': 'Condition', 'value': conditionName, 'inline': true},
          ]
        }
      ],
      'attachments': const <dynamic>[]
    };

    final post = client?.post ?? http.post;
    final response = await post(
      Uri.parse(webhookUrl),
      headers: {HttpHeaders.contentTypeHeader: ContentType.json.value},
      body: json.encode(discordPayload),
    );

    return Response(response.statusCode, body: response.body);
  };
}
