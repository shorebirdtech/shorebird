import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:self_hosted_server/src/database/database.dart';

/// Authentication service for JWT-based authentication.
class AuthService {
  AuthService({
    required this.db,
    required this.jwtSecret,
    this.tokenExpiry = const Duration(days: 30),
  });

  final Database db;
  final String jwtSecret;
  final Duration tokenExpiry;

  /// Hash a password using SHA-256 with salt.
  String hashPassword(String password, String salt) {
    final saltedPassword = '$salt:$password';
    return sha256.convert(utf8.encode(saltedPassword)).toString();
  }

  /// Generate a salt for password hashing.
  String generateSalt() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return sha256.convert(utf8.encode('$now')).toString().substring(0, 16);
  }

  /// Register a new user.
  /// Returns the user ID on success.
  int? register({
    required String email,
    required String password,
    required String displayName,
  }) {
    // Check if user already exists
    final existing = db.selectOne('users', where: {'email': email});
    if (existing != null) {
      return null; // User already exists
    }

    // Hash password
    final salt = generateSalt();
    final passwordHash = '$salt:${hashPassword(password, salt)}';

    // Create user
    final userId = db.insert('users', {
      'email': email,
      'password_hash': passwordHash,
      'display_name': displayName,
    });

    // Create default organization for user
    final orgId = db.insert('organizations', {
      'name': '$displayName\'s Organization',
    });

    // Add user to organization as owner
    db.insert('organization_members', {
      'organization_id': orgId,
      'user_id': userId,
      'role': 'owner',
    });

    return userId;
  }

  /// Login a user and return a JWT token.
  String? login({
    required String email,
    required String password,
  }) {
    final user = db.selectOne('users', where: {'email': email});
    if (user == null) {
      return null;
    }

    // Verify password
    final storedHash = user['password_hash'] as String;
    final parts = storedHash.split(':');
    if (parts.length != 2) {
      return null;
    }

    final salt = parts[0];
    final expectedHash = parts[1];
    final actualHash = hashPassword(password, salt);

    if (expectedHash != actualHash) {
      return null;
    }

    // Generate JWT
    return generateToken(user['id'] as int, user['email'] as String);
  }

  /// Generate a JWT token for a user.
  String generateToken(int userId, String email) {
    final jwt = JWT(
      {
        'user_id': userId,
        'email': email,
      },
      issuer: 'self-hosted-shorebird',
    );

    return jwt.sign(
      SecretKey(jwtSecret),
      expiresIn: tokenExpiry,
    );
  }

  /// Verify a JWT token and return the user ID.
  int? verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;
      return payload['user_id'] as int?;
    } catch (e) {
      return null;
    }
  }

  /// Get user by ID.
  Map<String, dynamic>? getUserById(int userId) {
    return db.selectOne('users', where: {'id': userId});
  }

  /// Get user by email.
  Map<String, dynamic>? getUserByEmail(String email) {
    return db.selectOne('users', where: {'email': email});
  }
}
