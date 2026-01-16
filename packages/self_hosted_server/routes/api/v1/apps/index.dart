import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// GET /api/v1/apps - List apps
/// POST /api/v1/apps - Create app
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => _getApps(context),
    HttpMethod.post => _createApp(context),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _getApps(RequestContext context) async {
  // TODO: Implement app listing from database
  final apps = <AppMetadata>[
    AppMetadata(
      appId: 'demo-app-id',
      displayName: 'Demo App',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      latestReleaseVersion: '1.0.0',
      latestPatchNumber: null,
    ),
  ];

  return Response.json(
    body: GetAppsResponse(apps: apps).toJson(),
  );
}

Future<Response> _createApp(RequestContext context) async {
  final body = await context.request.json() as Map<String, dynamic>;
  final request = CreateAppRequest.fromJson(body);

  // TODO: Implement app creation in database
  // Generate a UUID for the app ID
  final appId = _uuid.v4();

  final app = App(
    id: appId,
    displayName: request.displayName,
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: app.toJson(),
  );
}
