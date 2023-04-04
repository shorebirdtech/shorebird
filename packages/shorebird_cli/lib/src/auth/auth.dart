import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/jwt.dart';
import 'package:shorebird_cli/src/auth/models/models.dart';
import 'package:shorebird_cli/src/config/config.dart';

export 'package:shorebird_cli/src/auth/models/models.dart' show User;

final _clientId = ClientId(
  /// Shorebird CLI's OAuth 2.0 identifier.
  '523302233293-eia5antm0tgvek240t46orctktiabrek.apps.googleusercontent.com',

  /// Shorebird CLI's OAuth 2.0 secret.
  ///
  /// This isn't actually meant to be kept secret.
  /// There is no way to properly secure a secret for installed/console applications.
  /// Fortunately the OAuth2 flow used in this case assumes that the app cannot
  /// keep secrets so this particular secret DOES NOT need to be kept secret.
  /// You should however make sure not to re-use the same secret
  /// anywhere secrecy is required.
  ///
  /// For more info see: https://developers.google.com/identity/protocols/oauth2/native-app
  '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',
);
final _scopes = ['openid', 'https://www.googleapis.com/auth/userinfo.email'];

typedef ObtainAccessCredentials = Future<AccessCredentials> Function(
  ClientId clientId,
  List<String> scopes,
  http.Client client,
  void Function(String) userPrompt,
);

class Auth {
  Auth({
    http.Client? httpClient,
    ObtainAccessCredentials? obtainAccessCredentials,
  })  : _httpClient = httpClient ?? http.Client(),
        _obtainAccessCredentials =
            obtainAccessCredentials ?? obtainAccessCredentialsViaUserConsent {
    _loadCredentials();
  }

  static const _credentialsFileName = 'credentials.json';

  final http.Client _httpClient;
  final ObtainAccessCredentials _obtainAccessCredentials;
  final credentialsFilePath = p.join(shorebirdConfigDir, _credentialsFileName);

  http.Client get client {
    if (_credentials == null) return _httpClient;
    return autoRefreshingClient(_clientId, _credentials!, _httpClient);
  }

  Future<void> login(void Function(String) prompt) async {
    if (_credentials != null) return;

    final client = http.Client();
    try {
      _credentials = await _obtainAccessCredentials(
        _clientId,
        _scopes,
        client,
        prompt,
      );
      _user = _credentials?.toUser();
      _flushCredentials(_credentials!);
    } finally {
      client.close();
    }
  }

  void logout() => _clearCredentials();

  AccessCredentials? _credentials;

  User? _user;

  User? get user => _user;

  bool get isAuthenticated => _user != null;

  void _loadCredentials() {
    final credentialsFile = File(credentialsFilePath);

    if (credentialsFile.existsSync()) {
      try {
        final contents = credentialsFile.readAsStringSync();
        _credentials = AccessCredentials.fromJson(
          json.decode(contents) as Map<String, dynamic>,
        );
        _user = _credentials?.toUser();
      } catch (_) {}
    }
  }

  void _flushCredentials(AccessCredentials credentials) {
    File(credentialsFilePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(json.encode(credentials.toJson()));
  }

  void _clearCredentials() {
    _credentials = null;
    _user = null;

    final credentialsFile = File(credentialsFilePath);
    if (credentialsFile.existsSync()) {
      credentialsFile.deleteSync(recursive: true);
    }
  }

  void close() {
    _httpClient.close();
  }
}

extension on AccessCredentials {
  User toUser() {
    final claims = Jwt.decodeClaims(idToken!);

    if (claims == null) throw Exception('Invalid JWT');

    try {
      return User(email: claims['email'] as String);
    } catch (_) {
      throw Exception('Malformed claims');
    }
  }
}
