import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// POST /api/v1/apps/[appId]/patches/[patchId]/artifacts - Create patch artifact
Future<Response> onRequest(
  RequestContext context,
  String appId,
  String patchId,
) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  final patchIdInt = int.tryParse(patchId);
  if (patchIdInt == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Invalid patch ID'},
    );
  }

  // Verify patch exists
  final patch = database.selectOne('patches', where: {'id': patchIdInt});
  if (patch == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'Patch not found'},
    );
  }

  // Handle multipart form data for file upload
  final formData = await context.request.formData();

  final arch = formData.fields['arch'];
  final platform = formData.fields['platform'];
  final hash = formData.fields['hash'];
  final size = formData.fields['size'];

  if (arch == null || platform == null || hash == null || size == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'arch, platform, hash, and size are required'},
    );
  }

  // Generate upload URL using storage provider
  final storagePath =
      'patches/$appId/${patch['release_id']}/$patchId/$arch/patch.zip';

  String uploadUrl;
  try {
    uploadUrl = await storageProvider.getSignedUploadUrl(
      bucket: config.s3BucketPatches,
      path: storagePath,
    );
  } catch (e) {
    // If S3 is not available, construct URL manually
    final protocol = config.s3UseSSL ? 'https' : 'http';
    uploadUrl =
        '$protocol://${config.s3Endpoint}:${config.s3Port}/'
        '${config.s3BucketPatches}/$storagePath';
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
  final artifactId = database.insert('patch_artifacts', {
    'patch_id': patchIdInt,
    'arch': arch,
    'platform': platform,
    'hash': hash,
    'size': sizeInt,
    'url': uploadUrl,
    'storage_path': storagePath,
  });

  return Response.json(
    statusCode: HttpStatus.created,
    body: CreatePatchArtifactResponse(
      id: artifactId,
      patchId: patchIdInt,
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
