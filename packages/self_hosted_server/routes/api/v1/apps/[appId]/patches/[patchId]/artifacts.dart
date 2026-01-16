import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
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

  // Handle multipart form data for file upload
  final formData = await context.request.formData();

  final arch = formData.fields['arch'];
  final platform = formData.fields['platform'];
  final hash = formData.fields['hash'];
  final size = formData.fields['size'];
  final hashSignature = formData.fields['hash_signature'];
  final podfileLockHash = formData.fields['podfile_lock_hash'];

  // TODO: Get the uploaded file and store in S3
  // final file = formData.files['file'];

  // TODO: Generate a signed upload URL for the client
  // This is the URL where the CLI will upload the artifact
  final uploadUrl = 'https://your-s3-endpoint.com/upload-url';

  return Response.json(
    statusCode: HttpStatus.created,
    body: CreatePatchArtifactResponse(url: uploadUrl).toJson(),
  );
}
