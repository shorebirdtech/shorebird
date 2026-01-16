import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/releases - List releases
/// POST /api/v1/apps/[appId]/releases - Create release
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
    HttpMethod.get => _getReleases(context, appId),
    HttpMethod.post => _createRelease(context, appId),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

Future<Response> _getReleases(RequestContext context, String appId) async {
  final sideloadableOnly =
      context.request.uri.queryParameters['sideloadable'] == 'true';

  final releaseRows = database.select('releases', where: {'app_id': appId});

  final releases = <Release>[];
  for (final row in releaseRows) {
    // Get platform statuses
    final statusRows = database.select(
      'release_platform_statuses',
      where: {'release_id': row['id']},
    );

    final platformStatuses = <ReleasePlatform, ReleaseStatus>{};
    for (final statusRow in statusRows) {
      platformStatuses[_parsePlatform(statusRow['platform'] as String)] =
          _parseStatus(statusRow['status'] as String);
    }

    // If sideloadable only, check if any artifacts can be sideloaded
    if (sideloadableOnly) {
      final artifacts = database.select(
        'release_artifacts',
        where: {'release_id': row['id']},
      );
      final hasSideloadable = artifacts.any(
        (a) => a['can_sideload'] == 1 || a['can_sideload'] == true,
      );
      if (!hasSideloadable) continue;
    }

    releases.add(
      Release(
        id: row['id'] as int,
        appId: row['app_id'] as String,
        version: row['version'] as String,
        flutterRevision: row['flutter_revision'] as String,
        flutterVersion: row['flutter_version'] as String?,
        displayName: row['display_name'] as String?,
        platformStatuses: platformStatuses,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      ),
    );
  }

  return Response.json(body: GetReleasesResponse(releases: releases).toJson());
}

Future<Response> _createRelease(RequestContext context, String appId) async {
  final body = await context.request.json() as Map<String, dynamic>;

  final version = body['version'] as String?;
  final flutterRevision = body['flutter_revision'] as String?;
  final flutterVersion = body['flutter_version'] as String?;
  final displayName = body['display_name'] as String?;

  if (version == null || flutterRevision == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'version and flutter_revision are required'},
    );
  }

  // Check if release already exists
  final existing = database.selectOne(
    'releases',
    where: {'app_id': appId, 'version': version},
  );

  if (existing != null) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'message': 'Release with this version already exists'},
    );
  }

  final releaseId = database.insert('releases', {
    'app_id': appId,
    'version': version,
    'flutter_revision': flutterRevision,
    'flutter_version': flutterVersion,
    'display_name': displayName ?? 'Version $version',
  });

  final release = Release(
    id: releaseId,
    appId: appId,
    version: version,
    flutterRevision: flutterRevision,
    flutterVersion: flutterVersion,
    displayName: displayName ?? 'Version $version',
    platformStatuses: const {},
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: CreateReleaseResponse(release: release).toJson(),
  );
}

ReleasePlatform _parsePlatform(String platform) {
  switch (platform) {
    case 'android':
      return ReleasePlatform.android;
    case 'ios':
      return ReleasePlatform.ios;
    case 'macos':
      return ReleasePlatform.macos;
    case 'windows':
      return ReleasePlatform.windows;
    case 'linux':
      return ReleasePlatform.linux;
    default:
      return ReleasePlatform.android;
  }
}

ReleaseStatus _parseStatus(String status) {
  switch (status) {
    case 'draft':
      return ReleaseStatus.draft;
    case 'active':
      return ReleaseStatus.active;
    default:
      return ReleaseStatus.draft;
  }
}
