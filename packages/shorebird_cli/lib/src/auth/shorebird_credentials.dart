import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';

/// The default base URL for the Shorebird auth service.
const defaultAuthServiceUrl = 'https://auth.shorebird.dev';

/// Environment variable to override the auth service URL.
const authServiceUrlEnvVar = 'SHOREBIRD_AUTH_URL';

/// {@template shorebird_credentials}
/// Credentials issued by auth.shorebird.dev.
/// {@endtemplate}
class ShorebirdCredentials {
  /// {@macro shorebird_credentials}
  ShorebirdCredentials({
    required this.accessToken,
    required this.refreshToken,
  });

  /// Creates [ShorebirdCredentials] from a JSON map.
  factory ShorebirdCredentials.fromJson(Map<String, dynamic> json) {
    return ShorebirdCredentials(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
  }

  /// The Shorebird JWT (access token).
  String accessToken;

  /// The refresh token (sb_rt_...).
  final String refreshToken;

  /// Converts to a JSON map for storage.
  Map<String, dynamic> toJson() => {
        'type': 'shorebird',
        'access_token': accessToken,
        'refresh_token': refreshToken,
      };

  /// The email from the JWT claims, or null if unavailable.
  String? get email {
    try {
      final jwt = Jwt.parse(accessToken);
      return jwt.claims['email'] as String?;
    } on Exception {
      return null;
    }
  }

  /// Whether this is an API key (sb_api_...) rather than a JWT.
  bool get isApiKey => accessToken.startsWith('sb_api_');

  /// Whether the access token has expired.
  ///
  /// API keys never expire (server validates them directly).
  /// Empty access tokens are treated as expired to trigger a refresh.
  bool get isExpired {
    if (isApiKey) return false;
    if (accessToken.isEmpty) return true;
    try {
      final jwt = Jwt.parse(accessToken);
      final exp = DateTime.fromMillisecondsSinceEpoch(jwt.payload.exp * 1000);
      return exp.isBefore(DateTime.now());
    } on Exception {
      return true;
    }
  }

  /// Refreshes the access token by calling auth.shorebird.dev/token.
  ///
  /// Returns the new access token, or throws on failure.
  Future<void> refresh({
    required http.Client httpClient,
    String authServiceUrl = defaultAuthServiceUrl,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$authServiceUrl/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=refresh_token&refresh_token=$refreshToken',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to refresh token: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    accessToken = body['access_token'] as String;
  }
}
