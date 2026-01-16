import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// GET /api/v1/apps - List apps
/// POST /api/v1/apps - Create app
Future<Response> onRequest(RequestContext context) async {
  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  return switch (context.request.method) {
    HttpMethod.get => _getApps(context, user),
    HttpMethod.post => _createApp(context, user),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _getApps(
  RequestContext context,
  Map<String, dynamic> user,
) async {
  // Get organizations the user belongs to
  final memberships = database.select(
    'organization_members',
    where: {'user_id': user['id']},
  );

  final orgIds = memberships.map((m) => m['organization_id']).toSet();

  // Get all apps from user's organizations
  final allApps = database.select('apps');
  final userApps = allApps
      .where((app) => orgIds.contains(app['organization_id']))
      .toList();

  final apps = <AppMetadata>[];
  for (final app in userApps) {
    // Get latest release for this app
    final releases = database.select('releases', where: {'app_id': app['id']});
    releases.sort((a, b) =>
        DateTime.parse(b['created_at'] as String)
            .compareTo(DateTime.parse(a['created_at'] as String)));

    String? latestVersion;
    int? latestPatchNumber;

    if (releases.isNotEmpty) {
      latestVersion = releases.first['version'] as String;
      final patches = database.select(
        'patches',
        where: {'release_id': releases.first['id']},
      );
      if (patches.isNotEmpty) {
        patches.sort((a, b) => (b['number'] as int).compareTo(a['number'] as int));
        latestPatchNumber = patches.first['number'] as int;
      }
    }

    apps.add(
      AppMetadata(
        appId: app['id'] as String,
        displayName: app['display_name'] as String,
        createdAt: DateTime.parse(app['created_at'] as String),
        updatedAt: DateTime.parse(app['updated_at'] as String),
        latestReleaseVersion: latestVersion,
        latestPatchNumber: latestPatchNumber,
      ),
    );
  }

  return Response.json(
    body: GetAppsResponse(apps: apps).toJson(),
  );
}

Future<Response> _createApp(
  RequestContext context,
  Map<String, dynamic> user,
) async {
  final body = await context.request.json() as Map<String, dynamic>;
  final request = CreateAppRequest.fromJson(body);

  // Verify user has access to the organization
  final membership = database.selectOne(
    'organization_members',
    where: {
      'user_id': user['id'],
      'organization_id': request.organizationId,
    },
  );

  if (membership == null) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'message': 'You do not have access to this organization'},
    );
  }

  // Generate app ID
  final appId = _uuid.v4();

  // Create the app
  database.insertWithId('apps', {
    'id': appId,
    'organization_id': request.organizationId,
    'display_name': request.displayName,
  });

  final app = App(
    id: appId,
    displayName: request.displayName,
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: app.toJson(),
  );
}
