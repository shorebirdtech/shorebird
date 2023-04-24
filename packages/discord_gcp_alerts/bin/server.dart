// ignore_for_file: avoid_print

import 'dart:io';

import 'package:discord_gcp_alerts/discord_gcp_alerts.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

void main() async {
  final webhookUrl = Platform.environment['WEBHOOK_URL'];
  if (webhookUrl == null) {
    print('WEBHOOK_URL environment variable is not set.');
    exit(1);
  }
  final handler = gcpAlertHandler(webhookUrl: webhookUrl);
  final router = Router()..post('/webhook', handler);
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final ip = InternetAddress.anyIPv4;
  final server = await serve(router.call, ip, port);
  print('Server listening on port ${server.port}');
}
