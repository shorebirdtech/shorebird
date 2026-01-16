import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';

bool _servicesInitialized = false;

/// Root middleware that initializes services and adds CORS headers.
Handler middleware(Handler handler) {
  return (RequestContext context) async {
    // Initialize services once
    if (!_servicesInitialized) {
      _servicesInitialized = true;
      try {
        final cfg = ServerConfig.fromEnvironment();
        initializeServices(cfg);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to load config from environment: $e');
        // ignore: avoid_print
        print('Using development defaults...');

        // Use development defaults
        const devConfig = ServerConfig(
          port: 8080,
          host: '0.0.0.0',
          s3Endpoint: 'localhost',
          s3PublicEndpoint: 'localhost',
          s3Port: 9000,
          s3AccessKey: 'minioadmin',
          s3SecretKey: 'minioadmin',
          s3UseSSL: false,
          s3Region: 'us-east-1',
          s3BucketReleases: 'shorebird-releases',
          s3BucketPatches: 'shorebird-patches',
          jwtSecret: 'dev-secret-change-in-production',
        );
        initializeServices(devConfig);
      }
    }

    // Handle CORS preflight
    if (context.request.method == HttpMethod.options) {
      return Response(headers: _corsHeaders);
    }

    // Log request
    // ignore: avoid_print
    print('--- Request ---');
    // ignore: avoid_print
    print('${context.request.method.value} ${context.request.uri}');
    if (context.request.uri.queryParameters.isNotEmpty) {
      // ignore: avoid_print
      print('Query: ${context.request.uri.queryParameters}');
    }

    // Attempt to log request body if not binary
    final contentType = context.request.headers['content-type'];
    final isMultipart = contentType?.contains('multipart/form-data') ?? false;

    if (!isMultipart) {
      try {
        final body = await context.request.body();
        if (body.isNotEmpty) {
          // ignore: avoid_print
          print('Request Body: $body');
        }
      } catch (e) {
        // ignore: avoid_print
        print('Could not read request body: $e');
      }
    }

    // ignore: avoid_print
    print('----------------');

    try {
      // Process request and add CORS headers
      final response = await handler(context);

      // ignore: avoid_print
      print('--- Response ---');
      // ignore: avoid_print
      print('Status: ${response.statusCode}');

      // We need to read the body to log it, but reading it consumes the stream.
      // We read it, log it, and then create a new response with the same body.
      // This is expensive but fine for debugging.
      // EXCEPTION: Do not try to read body if it is a binary stream (e.g. zip file download)
      // or if response is streamed. The Utf8Decoder will fail on binary data.

      // since reading it might fail for binary data or consume a stream we can't recreate easily.
      final isBinary =
          response.headers[HttpHeaders.contentTypeHeader]?.contains(
                'application/zip',
              ) ==
              true ||
          response.headers[HttpHeaders.contentTypeHeader]?.contains(
                'application/octet-stream',
              ) ==
              true;

      if (isBinary) {
        // ignore: avoid_print
        print('Response Body: [Binary Data Omitted]');
        print('----------------');
        // Start a new response that copies everything but adds CORS
        // Note: This relies on the original response stream not being consumed yet.
        return Response.stream(
          body: response.bytes(),
          statusCode: response.statusCode,
          headers: {...response.headers, ..._corsHeaders},
        );
      }

      String? responseBody;
      try {
        responseBody = await response.body();
        if (responseBody != null) {
          // ignore: avoid_print
          print('Response Body: $responseBody');
        }
      } catch (_) {
        // If we fail to read string body, just proceed
      }

      // ignore: avoid_print
      print('----------------');

      return Response(
        statusCode: response.statusCode,
        body: responseBody,
        headers: {...response.headers, ..._corsHeaders},
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('Error processing request: $e\n$st');
      rethrow;
    }
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Content-Type, Authorization, X-Version, X-Cli-Version',
};
