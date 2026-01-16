import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/releases - List releases
/// POST /api/v1/apps/[appId]/releases - Create release
Future<Response> onRequest(RequestContext context, String appId) async {
  return switch (context.request.method) {
    HttpMethod.get => _getReleases(context, appId),
    HttpMethod.post => _createRelease(context, appId),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _getReleases(RequestContext context, String appId) async {
  // Check if sideloadable only query param is present
  final sideloadableOnly =
      context.request.uri.queryParameters['sideloadable'] == 'true';

  // TODO: Implement release listing from database
  // Filter by sideloadable if requested
  final releases = <Release>[
    Release(
      id: 1,
      appId: appId,
      version: '1.0.0',
      flutterRevision: 'abc123',
      displayName: 'Version 1.0.0',
      platformStatuses: {
        ReleasePlatform.android: ReleaseStatus.active,
      },
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  return Response.json(
    body: GetReleasesResponse(releases: releases).toJson(),
  );
}

Future<Response> _createRelease(RequestContext context, String appId) async {
  final body = await context.request.json() as Map<String, dynamic>;

  final version = body['version'] as String;
  final flutterRevision = body['flutter_revision'] as String;
  final flutterVersion = body['flutter_version'] as String?;
  final displayName = body['display_name'] as String?;

  // TODO: Implement release creation in database
  final release = Release(
    id: DateTime.now().millisecondsSinceEpoch,
    appId: appId,
    version: version,
    flutterRevision: flutterRevision,
    flutterVersion: flutterVersion,
    displayName: displayName ?? 'Version $version',
    platformStatuses: {},
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: CreateReleaseResponse(release: release).toJson(),
  );
}
