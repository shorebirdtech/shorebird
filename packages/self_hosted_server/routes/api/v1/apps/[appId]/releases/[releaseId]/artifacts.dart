import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/releases/[releaseId]/artifacts - List artifacts
/// POST /api/v1/apps/[appId]/releases/[releaseId]/artifacts - Create artifact
Future<Response> onRequest(
  RequestContext context,
  String appId,
  String releaseId,
) async {
  return switch (context.request.method) {
    HttpMethod.get => _getArtifacts(context, appId, releaseId),
    HttpMethod.post => _createArtifact(context, appId, releaseId),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _getArtifacts(
  RequestContext context,
  String appId,
  String releaseId,
) async {
  final queryParams = context.request.uri.queryParameters;
  final arch = queryParams['arch'];
  final platform = queryParams['platform'];

  // TODO: Implement artifact listing from database
  // Filter by arch and platform if provided
  final artifacts = <ReleaseArtifact>[];

  return Response.json(
    body: GetReleaseArtifactsResponse(artifacts: artifacts).toJson(),
  );
}

Future<Response> _createArtifact(
  RequestContext context,
  String appId,
  String releaseId,
) async {
  // Handle multipart form data for file upload
  final formData = await context.request.formData();
  
  final arch = formData.fields['arch'];
  final platform = formData.fields['platform'];
  final hash = formData.fields['hash'];
  final size = formData.fields['size'];
  final canSideload = formData.fields['can_sideload'];
  final filename = formData.fields['filename'];

  // TODO: Get the uploaded file and store in S3
  // final file = formData.files['file'];
  
  // TODO: Generate a signed upload URL for the client
  // This is the URL where the CLI will upload the artifact
  final uploadUrl = 'https://your-s3-endpoint.com/upload-url';

  return Response.json(
    statusCode: HttpStatus.created,
    body: CreateReleaseArtifactResponse(url: uploadUrl).toJson(),
  );
}
