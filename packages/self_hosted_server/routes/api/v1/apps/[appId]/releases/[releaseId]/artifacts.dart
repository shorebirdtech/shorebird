import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/releases/[releaseId]/artifacts - List artifacts
/// POST /api/v1/apps/[appId]/releases/[releaseId]/artifacts - Create artifact
Future<Response> onRequest(
  RequestContext context,
  String appId,
  String releaseId,
) async {
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

  return switch (context.request.method) {
    HttpMethod.get => _getArtifacts(context, appId, releaseIdInt),
    HttpMethod.post => _createArtifact(context, appId, releaseIdInt),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _getArtifacts(
  RequestContext context,
  String appId,
  int releaseId,
) async {
  final queryParams = context.request.uri.queryParameters;
  final archFilter = queryParams['arch'];
  final platformFilter = queryParams['platform'];

  var artifactRows = database.select(
    'release_artifacts',
    where: {'release_id': releaseId},
  );

  // Apply filters
  if (archFilter != null) {
    artifactRows = artifactRows.where((a) => a['arch'] == archFilter).toList();
  }
  if (platformFilter != null) {
    artifactRows = artifactRows.where((a) => a['platform'] == platformFilter).toList();
  }

  final artifacts = artifactRows.map((row) => ReleaseArtifact(
    id: row['id'] as int,
    releaseId: row['release_id'] as int,
    arch: row['arch'] as String,
    platform: _parsePlatform(row['platform'] as String),
    hash: row['hash'] as String,
    size: row['size'] as int,
    url: row['url'] as String,
    podfileLockHash: row['podfile_lock_hash'] as String?,
    canSideload: row['can_sideload'] == 1 || row['can_sideload'] == true,
  )).toList();

  return Response.json(
    body: GetReleaseArtifactsResponse(artifacts: artifacts).toJson(),
  );
}

Future<Response> _createArtifact(
  RequestContext context,
  String appId,
  int releaseId,
) async {
  // Handle multipart form data for file upload
  final formData = await context.request.formData();
  
  final arch = formData.fields['arch'];
  final platform = formData.fields['platform'];
  final hash = formData.fields['hash'];
  final size = formData.fields['size'];
  final canSideload = formData.fields['can_sideload'];
  final filename = formData.fields['filename'];
  final podfileLockHash = formData.fields['podfile_lock_hash'];

  if (arch == null || platform == null || hash == null || size == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'arch, platform, hash, and size are required'},
    );
  }

  // Generate upload URL using storage provider
  final storagePath = 'releases/$appId/$releaseId/$arch/$filename';
  
  String uploadUrl;
  try {
    uploadUrl = await storageProvider.getSignedUploadUrl(
      bucket: config.s3BucketReleases,
      path: storagePath,
    );
  } catch (e) {
    // If S3 is not available, construct URL manually
    final protocol = config.s3UseSSL ? 'https' : 'http';
    uploadUrl = '$protocol://${config.s3Endpoint}:${config.s3Port}/'
        '${config.s3BucketReleases}/$storagePath';
  }

  // Parse size safely
  final sizeInt = int.tryParse(size);
  if (sizeInt == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Invalid size value'},
    );
  }

  // Store artifact metadata and get the ID
  final artifactId = database.insert('release_artifacts', {
    'release_id': releaseId,
    'arch': arch,
    'platform': platform,
    'hash': hash,
    'size': sizeInt,
    'url': uploadUrl,
    'can_sideload': canSideload == 'true' ? 1 : 0,
    'podfile_lock_hash': podfileLockHash,
  });

  return Response.json(
    statusCode: HttpStatus.created,
    body: CreateReleaseArtifactResponse(
      id: artifactId,
      releaseId: releaseId,
      arch: arch,
      platform: _parsePlatform(platform),
      hash: hash,
      size: sizeInt,
      url: uploadUrl,
    ).toJson(),
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
