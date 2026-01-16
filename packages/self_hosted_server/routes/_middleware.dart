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

    // Process request and add CORS headers
    final response = await handler(context);
    return response.copyWith(
      headers: {
        ...response.headers,
        ..._corsHeaders,
      },
    );
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Content-Type, Authorization, X-Version, X-Cli-Version',
};
