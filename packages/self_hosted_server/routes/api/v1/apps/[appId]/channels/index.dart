import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/channels - List channels
/// POST /api/v1/apps/[appId]/channels - Create channel
Future<Response> onRequest(RequestContext context, String appId) async {
  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  // Verify app exists
  final app = database.selectOne('apps', where: {'id': appId});
  if (app == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'App not found'},
    );
  }

  return switch (context.request.method) {
    HttpMethod.get => _getChannels(context, appId),
    HttpMethod.post => _createChannel(context, appId),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _getChannels(RequestContext context, String appId) async {
  final channelRows = database.select('channels', where: {'app_id': appId});
  
  final channels = channelRows.map((row) => Channel(
    id: row['id'] as int,
    appId: row['app_id'] as String,
    name: row['name'] as String,
  )).toList();

  return Response.json(body: channels.map((c) => c.toJson()).toList());
}

Future<Response> _createChannel(RequestContext context, String appId) async {
  final body = await context.request.json() as Map<String, dynamic>;
  final channelName = body['channel'] as String?;

  if (channelName == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'channel is required'},
    );
  }

  // Check if channel already exists
  final existing = database.selectOne(
    'channels',
    where: {'app_id': appId, 'name': channelName},
  );

  if (existing != null) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'message': 'Channel already exists'},
    );
  }

  final channelId = database.insert('channels', {
    'app_id': appId,
    'name': channelName,
  });

  final channel = Channel(
    id: channelId,
    appId: appId,
    name: channelName,
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: channel.toJson(),
  );
}
