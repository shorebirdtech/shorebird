import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/channels - List channels
/// POST /api/v1/apps/[appId]/channels - Create channel
Future<Response> onRequest(RequestContext context, String appId) async {
  return switch (context.request.method) {
    HttpMethod.get => _getChannels(context, appId),
    HttpMethod.post => _createChannel(context, appId),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _getChannels(RequestContext context, String appId) async {
  // TODO: Implement channel listing from database
  final channels = <Channel>[
    Channel(
      id: 1,
      appId: appId,
      name: 'stable',
    ),
  ];

  return Response.json(body: channels.map((c) => c.toJson()).toList());
}

Future<Response> _createChannel(RequestContext context, String appId) async {
  final body = await context.request.json() as Map<String, dynamic>;
  final channelName = body['channel'] as String;

  // TODO: Implement channel creation in database
  final channel = Channel(
    id: DateTime.now().millisecondsSinceEpoch,
    appId: appId,
    name: channelName,
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: channel.toJson(),
  );
}
