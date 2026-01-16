import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/diagnostics/gcp_upload - Get upload speed test URL
Future<Response> onRequest(RequestContext context) async {
  // TODO: Generate a signed upload URL for speed testing
  // This should point to your S3 storage
  return Response.json(
    body: {
      'upload_url': 'https://your-s3-endpoint.com/test/upload-test',
    },
  );
}
