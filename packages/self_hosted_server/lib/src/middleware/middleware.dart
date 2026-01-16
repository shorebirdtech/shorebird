import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/src/auth/auth_service.dart';
import 'package:self_hosted_server/src/config/server_config.dart';
import 'package:self_hosted_server/src/database/database.dart';
import 'package:self_hosted_server/src/storage/s3_storage_provider.dart';

/// Global instances (initialized on server start).
late final Database database;

/// Authentication service instance.
late final AuthService authService;

/// S3 storage provider instance.
late final S3StorageProvider storageProvider;

/// Server configuration.
late final ServerConfig config;

bool _initialized = false;

/// Initialize global services.
void initializeServices(ServerConfig cfg) {
  if (_initialized) return;
  _initialized = true;

  config = cfg;

  // Ensure data directory exists
  final dataDir = Directory('data');
  if (!dataDir.existsSync()) {
    dataDir.createSync(recursive: true);
  }

  // Initialize database
  database = Database.instance;
  database.initialize('data/database.json');

  // Initialize auth service
  authService = AuthService(db: database, jwtSecret: config.jwtSecret);

  // Initialize storage provider
  storageProvider = S3StorageProvider(
    endpoint: config.s3Endpoint,
    publicEndpoint: config.s3PublicEndpoint,
    port: config.s3Port,
    accessKey: config.s3AccessKey,
    secretKey: config.s3SecretKey,
    useSSL: config.s3UseSSL,
    region: config.s3Region,
  );

  // Create default admin user if no users exist
  if (database.count('users') == 0) {
    final adminEmail = Platform.environment['ADMIN_EMAIL'] ?? 'admin@localhost';
    final adminPassword = Platform.environment['ADMIN_PASSWORD'] ?? 'admin123';
    authService.register(
      email: adminEmail,
      password: adminPassword,
      displayName: 'Admin',
    );
    // ignore: avoid_print
    print('Created default admin user: $adminEmail');
  }
}

/// Get current user from context.
Map<String, dynamic>? getCurrentUser(RequestContext context) {
  try {
    return context.read<Map<String, dynamic>>();
  } catch (e) {
    return null;
  }
}

/// Authenticate a request and return the user.
Future<Map<String, dynamic>?> authenticateRequest(
  RequestContext context,
) async {
  final authHeader = context.request.headers['Authorization'];
  if (authHeader == null) return null;

  if (authHeader.startsWith('Bearer ')) {
    final token = authHeader.substring(7);
    final userId = authService.verifyToken(token);
    if (userId == null) return null;
    return authService.getUserById(userId);
  }

  return null;
}
