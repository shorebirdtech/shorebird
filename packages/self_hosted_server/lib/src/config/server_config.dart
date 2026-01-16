import 'dart:io';
import 'dart:math';

/// Server configuration loaded from environment variables.
class ServerConfig {
  const ServerConfig({
    required this.port,
    required this.host,
    required this.s3Endpoint,
    required this.s3PublicEndpoint,
    required this.s3Port,
    required this.s3AccessKey,
    required this.s3SecretKey,
    required this.s3UseSSL,
    required this.s3Region,
    required this.s3BucketReleases,
    required this.s3BucketPatches,
    required this.jwtSecret,
    this.databaseUrl,
  });

  /// Load configuration from environment variables.
  ///
  /// Throws an [ArgumentError] if required configuration is missing.
  factory ServerConfig.fromEnvironment() {
    final s3AccessKey = Platform.environment['S3_ACCESS_KEY'];
    final s3SecretKey = Platform.environment['S3_SECRET_KEY'];
    final jwtSecret = Platform.environment['JWT_SECRET'];

    if (s3AccessKey == null || s3AccessKey.isEmpty) {
      throw ArgumentError(
        'S3_ACCESS_KEY environment variable is required but not set.',
      );
    }
    if (s3SecretKey == null || s3SecretKey.isEmpty) {
      throw ArgumentError(
        'S3_SECRET_KEY environment variable is required but not set.',
      );
    }
    if (jwtSecret == null || jwtSecret.isEmpty) {
      throw ArgumentError(
        'JWT_SECRET environment variable is required but not set. '
        'Generate a secure random string for production use.',
      );
    }

    return ServerConfig(
      port: int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080,
      host: Platform.environment['HOST'] ?? '0.0.0.0',
      databaseUrl: Platform.environment['DATABASE_URL'],
      s3Endpoint: Platform.environment['S3_ENDPOINT'] ?? 'localhost',
      s3PublicEndpoint:
          Platform.environment['S3_PUBLIC_ENDPOINT'] ?? 'localhost',
      s3Port: int.tryParse(Platform.environment['S3_PORT'] ?? '9000') ?? 9000,
      s3AccessKey: s3AccessKey,
      s3SecretKey: s3SecretKey,
      s3UseSSL: Platform.environment['S3_USE_SSL']?.toLowerCase() == 'true',
      s3Region: Platform.environment['S3_REGION'] ?? 'us-east-1',
      s3BucketReleases:
          Platform.environment['S3_BUCKET_RELEASES'] ?? 'shorebird-releases',
      s3BucketPatches:
          Platform.environment['S3_BUCKET_PATCHES'] ?? 'shorebird-patches',
      jwtSecret: jwtSecret,
    );
  }

  /// Generate a random secret for development purposes only.
  /// DO NOT use this in production.
  static String generateDevSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// The port to run the server on.
  final int port;

  /// The host to bind the server to.
  final String host;

  /// Database connection URL.
  final String? databaseUrl;

  /// S3 endpoint (hostname without protocol).
  final String s3Endpoint;

  /// The S3 endpoint to use for signed URLs (publicly accessible).
  final String s3PublicEndpoint;

  /// S3 port.
  final int s3Port;

  /// S3 access key.
  final String s3AccessKey;

  /// S3 secret key.
  final String s3SecretKey;

  /// Whether to use SSL for S3 connections.
  final bool s3UseSSL;

  /// S3 region.
  final String s3Region;

  /// S3 bucket for release artifacts.
  final String s3BucketReleases;

  /// S3 bucket for patch artifacts.
  final String s3BucketPatches;

  /// JWT secret for authentication.
  final String jwtSecret;

  /// Get the full S3 endpoint URL.
  String get s3EndpointUrl {
    final protocol = s3UseSSL ? 'https' : 'http';
    return '$protocol://$s3Endpoint:$s3Port';
  }
}
