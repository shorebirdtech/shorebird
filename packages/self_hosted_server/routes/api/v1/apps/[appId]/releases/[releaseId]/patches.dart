import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/releases/[releaseId]/patches - List patches
Future<Response> onRequest(
  RequestContext context,
  String appId,
  String releaseId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  final releaseIdInt = int.tryParse(releaseId);
  if (releaseIdInt == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Invalid release ID'},
    );
  }

  final patchRows = database.select(
    'patches',
    where: {'release_id': releaseIdInt},
  );

  final patches = <ReleasePatch>[];
  for (final row in patchRows) {
    // Get channels this patch is promoted to
    final channelPatches = database.select(
      'channel_patches',
      where: {'patch_id': row['id']},
    );

    String? channelName;
    if (channelPatches.isNotEmpty) {
      final channel = database.selectOne(
        'channels',
        where: {'id': channelPatches.first['channel_id']},
      );
      if (channel != null) {
        channelName = channel['name'] as String;
      }
    }

    // Get artifacts for this patch
    final artifactRows = database.select(
      'patch_artifacts',
      where: {'patch_id': row['id']},
    );

    final artifacts = artifactRows.map((a) {
      final createdAtStr = a['created_at'] as String?;
      return PatchArtifact(
        id: a['id'] as int,
        patchId: a['patch_id'] as int,
        arch: a['arch'] as String,
        platform: _parsePlatform(a['platform'] as String),
        hash: a['hash'] as String,
        size: a['size'] as int,
        createdAt: createdAtStr != null
            ? DateTime.parse(createdAtStr)
            : DateTime.now(),
      );
    }).toList();

    patches.add(ReleasePatch(
      id: row['id'] as int,
      number: row['number'] as int,
      channel: channelName,
      artifacts: artifacts,
      isRolledBack: false,
    ));
  }

  return Response.json(
    body: GetReleasePatchesResponse(patches: patches).toJson(),
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
