import 'package:dart_frog/dart_frog.dart';

/// GET /api/v1/diagnostics/gcp_download - Get download speed test URL
Future<Response> onRequest(RequestContext context) async {
  // TODO: Return a URL to a test file for download speed testing
  // This should point to your S3 storage
  return Response.json(
    body: {
      'download_url': 'https://your-s3-endpoint.com/test/download-test.bin',
    },
  );
}
