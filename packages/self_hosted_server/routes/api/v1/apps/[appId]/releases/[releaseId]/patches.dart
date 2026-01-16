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

  final patchRows = database.select('patches', where: {'release_id': releaseIdInt});
  
  final patches = <ReleasePatch>[];
  for (final row in patchRows) {
    // Get channels this patch is promoted to
    final channelPatches = database.select(
      'channel_patches',
      where: {'patch_id': row['id']},
    );
    
    final channels = <Channel>[];
    for (final cp in channelPatches) {
      final channel = database.selectOne('channels', where: {'id': cp['channel_id']});
      if (channel != null) {
        channels.add(Channel(
          id: channel['id'] as int,
          appId: channel['app_id'] as String,
          name: channel['name'] as String,
        ));
      }
    }

    // Get artifacts for this patch
    final artifactRows = database.select(
      'patch_artifacts',
      where: {'patch_id': row['id']},
    );

    final artifacts = artifactRows.map((a) => PatchArtifact(
      id: a['id'] as int,
      patchId: a['patch_id'] as int,
      arch: a['arch'] as String,
      platform: _parsePlatform(a['platform'] as String),
      hash: a['hash'] as String,
      hashSignature: a['hash_signature'] as String?,
      size: a['size'] as int,
    )).toList();

    patches.add(ReleasePatch(
      id: row['id'] as int,
      number: row['number'] as int,
      channels: channels,
      artifacts: artifacts,
      createdAt: DateTime.parse(row['created_at'] as String),
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
