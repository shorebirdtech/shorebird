import 'dart:convert';
import 'dart:io';

import 'package:discord_gcp_alerts/discord_gcp_alerts.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('gcpAlertHandler', () {
    const webHookUrl = 'http://example.com/webhook';
    late http.Client client;
    late Handler handler;

    setUp(() {
      client = _MockHttpClient();
      handler = gcpAlertHandler(webhookUrl: webHookUrl, client: client);
    });

    test('forwards the request to the webhook', () async {
      when(
        () => client.post(
          Uri.parse(webHookUrl),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 200));

      await handler(
        Request(
          'POST',
          Uri.parse('http://localhost:8080/'),
          body: json.encode(
            {
              'version': 'test',
              'incident': {
                'incident_id': '12345',
                'scoping_project_id': '12345',
                'scoping_project_number': 12345,
                'url': 'http://www.example.com',
                'started_at': 0,
                'ended_at': 0,
                'state': 'OPEN',
                'summary': 'Test Incident',
                'apigee_url': 'http://www.example.com',
                'observed_value': '1.0',
                'resource': {
                  'type': 'example_resource',
                  'labels': {'example': 'label'}
                },
                'resource_type_display_name': 'Example Resource Type',
                'resource_id': '12345',
                'resource_display_name': 'Example Resource',
                'resource_name': 'projects/12345/example_resources/12345',
                'metric': {
                  'type': 'test.googleapis.com/metric',
                  'displayName': 'Test Metric',
                  'labels': {'example': 'label'}
                },
                'metadata': {
                  'system_labels': {'example': 'label'},
                  'user_labels': {'example': 'label'}
                },
                'policy_name': 'projects/12345/alertPolicies/12345',
                'policy_user_labels': {'example': 'label'},
                'documentation': 'Test documentation',
                'condition': {
                  'name': 'projects/12345/alertPolicies/12345/conditions/12345',
                  'displayName': 'Example condition',
                  'conditionThreshold': {
                    'filter':
                        'metric.type="test.googleapis.com/metric" resource.type="example_resource"',
                    'comparison': 'COMPARISON_GT',
                    'thresholdValue': 0.5,
                    'duration': '0s',
                    'trigger': {'count': 1}
                  }
                },
                'condition_name': 'Example condition',
                'threshold_value': '0.5'
              }
            },
          ),
        ),
      );

      verify(
        () => client.post(
          Uri.parse(webHookUrl),
          headers: {HttpHeaders.contentTypeHeader: ContentType.json.value},
          body: json.encode({
            'embeds': [
              {
                'title': '🚨 projects/12345/alertPolicies/12345 🚨',
                'description': 'Test Incident',
                'url': 'http://www.example.com',
                'color': 16711680,
                'fields': [
                  {'name': 'State', 'value': 'OPEN', 'inline': true},
                  {
                    'name': 'Resource',
                    'value': 'projects/12345/example_resources/12345',
                    'inline': true
                  },
                  {
                    'name': 'Condition',
                    'value': 'Example condition',
                    'inline': true
                  }
                ]
              }
            ],
            'attachments': <dynamic>[]
          }),
        ),
      ).called(1);
    });
  });
}
