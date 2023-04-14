import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/jwt.dart';
import 'package:shorebird_cli/src/command_runner.dart';

final _clientId = oauth2.ClientId(
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

typedef ObtainAccessCredentials = Future<oauth2.AccessCredentials> Function(
  oauth2.ClientId clientId,
  List<String> scopes,
  http.Client client,
  void Function(String) userPrompt,
);

typedef RefreshCredentials = Future<oauth2.AccessCredentials> Function(
  oauth2.ClientId clientId,
  oauth2.AccessCredentials credentials,
  http.Client client,
);

typedef OnRefreshCredentials = void Function(
  oauth2.AccessCredentials credentials,
);

class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient({
    required oauth2.AccessCredentials credentials,
    required http.Client httpClient,
    required OnRefreshCredentials onRefreshCredentials,
    RefreshCredentials refreshCredentials = oauth2.refreshCredentials,
  })  : _credentials = credentials,
        _baseClient = httpClient,
        _onRefreshCredentials = onRefreshCredentials,
        _refreshCredentials = refreshCredentials;

  final http.Client _baseClient;
  final OnRefreshCredentials _onRefreshCredentials;
  final RefreshCredentials _refreshCredentials;
  oauth2.AccessCredentials _credentials;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_credentials.accessToken.hasExpired) {
      _credentials = await _refreshCredentials(
        _clientId,
        _credentials,
        _baseClient,
      );
      _onRefreshCredentials(_credentials);
    }
    final token = _credentials.idToken;
    request.headers['Authorization'] = 'Bearer $token';
    return _baseClient.send(request);
  }
}

class Auth {
  Auth({
    http.Client? httpClient,
    String? credentialsDir,
    ObtainAccessCredentials? obtainAccessCredentials,
  })  : _httpClient = httpClient ?? http.Client(),
        _credentialsDir =
            credentialsDir ?? applicationConfigHome(executableName),
        _obtainAccessCredentials = obtainAccessCredentials ??
            oauth2.obtainAccessCredentialsViaUserConsent {
    _loadCredentials();
  }

  final http.Client _httpClient;
  final String _credentialsDir;
  final ObtainAccessCredentials _obtainAccessCredentials;

  String get credentialsFilePath {
    return p.join(_credentialsDir, 'credentials.json');
  }

  http.Client get client {
    final credentials = _credentials;
    if (credentials == null) return _httpClient;
    return AuthenticatedClient(
      credentials: credentials,
      httpClient: _httpClient,
      onRefreshCredentials: _flushCredentials,
    );
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
      _email = _credentials?.email;
      _flushCredentials(_credentials!);
    } finally {
      client.close();
    }
  }

  void logout() => _clearCredentials();

  oauth2.AccessCredentials? _credentials;

  String? _email;

  String? get email => _email;

  bool get isAuthenticated => _email != null;

  void _loadCredentials() {
    final credentialsFile = File(credentialsFilePath);

    if (credentialsFile.existsSync()) {
      try {
        final contents = credentialsFile.readAsStringSync();
        _credentials = oauth2.AccessCredentials.fromJson(
          json.decode(contents) as Map<String, dynamic>,
        );
        _email = _credentials?.email;
      } catch (_) {}
    }
  }

  void _flushCredentials(oauth2.AccessCredentials credentials) {
    File(credentialsFilePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(json.encode(credentials.toJson()));
  }

  void _clearCredentials() {
    _credentials = null;
    _email = null;

    final credentialsFile = File(credentialsFilePath);
    if (credentialsFile.existsSync()) {
      credentialsFile.deleteSync(recursive: true);
    }
  }

  void close() {
    _httpClient.close();
  }
}

extension on oauth2.AccessCredentials {
  String get email {
    final token = idToken;

    if (token == null) throw Exception('Missing JWT');

    final claims = Jwt.decodeClaims(token);

    if (claims == null) throw Exception('Invalid JWT');

    try {
      return claims['email'] as String;
    } catch (_) {
      throw Exception('Malformed claims');
    }
  }
}
