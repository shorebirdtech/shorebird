import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';

Future<Response> onRequest(
  RequestContext context,
  String bucket,
  String path,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  // Basic security check: ensure path doesn't try to go up directories
  if (path.contains('..')) {
    return Response(statusCode: HttpStatus.forbidden);
  }
  
  // Since the path is encoded in the URL (e.g. patches%2Fuuid%2F...), 
  // Dart Frog correctly passes it as a single decoded segment to the 'path' argument.
  // We can just use the arguments directly.
  final realBucket = bucket;
  // Decode the path component which was encoded to pass as a single segment
  final realPath = Uri.decodeComponent(path);

  print('Debug Proxy: Bucket="$realBucket", Path="$realPath"');

  try {
    final stream = await storageProvider.downloadFile(
      bucket: realBucket,
      path: realPath,
    );

    // Determine content type based on extension
    var contentType = 'application/octet-stream';
    if (realPath.endsWith('.zip')) {
      contentType = 'application/zip';
    } else if (realPath.endsWith('.aab')) {
      contentType = 'application/octet-stream'; // Android App Bundle
    }

    return Response.stream(
      body: stream,
      headers: {
        HttpHeaders.contentTypeHeader: contentType,
        HttpHeaders.contentDisposition: 'attachment; filename="${realPath.split('/').last}"',
      },
    );
  } catch (e) {
    print('Failed to download artifact: $e');
    return Response(statusCode: HttpStatus.notFound, body: 'Artifact not found');
  }
}
