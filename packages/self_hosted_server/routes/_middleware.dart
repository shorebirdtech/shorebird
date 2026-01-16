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
      final responseBody = await response.body();
      if (responseBody != null) {
        // ignore: avoid_print
        print('Response Body: $responseBody');
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
