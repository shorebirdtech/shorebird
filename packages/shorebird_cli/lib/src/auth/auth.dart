import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/jwt.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

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

class LoggingClient extends http.BaseClient {
  LoggingClient({
    required http.Client httpClient,
    required Logger logger,
  })  : _baseClient = httpClient,
        _logger = logger;

  final http.Client _baseClient;
  final Logger _logger;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _logger.detail('[HTTP] $request');
    return _baseClient.send(request);
  }
}

class AuthenticatedClient extends LoggingClient {
  AuthenticatedClient({
    required super.httpClient,
    required super.logger,
    required oauth2.AccessCredentials credentials,
    required OnRefreshCredentials onRefreshCredentials,
    RefreshCredentials refreshCredentials = oauth2.refreshCredentials,
  })  : _credentials = credentials,
        _onRefreshCredentials = onRefreshCredentials,
        _refreshCredentials = refreshCredentials;

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
    return super.send(request);
  }
}

class Auth {
  Auth({
    Logger? logger,
    http.Client? httpClient,
    String? credentialsDir,
    ObtainAccessCredentials? obtainAccessCredentials,
    CodePushClientBuilder? buildCodePushClient,
  })  : logger = logger ?? Logger(),
        _httpClient = httpClient ?? http.Client(),
        _credentialsDir =
            credentialsDir ?? applicationConfigHome(executableName),
        _obtainAccessCredentials = obtainAccessCredentials ??
            oauth2.obtainAccessCredentialsViaUserConsent,
        _buildCodePushClient = buildCodePushClient ?? CodePushClient.new {
    _loadCredentials();
  }

  final http.Client _httpClient;
  final String _credentialsDir;
  final ObtainAccessCredentials _obtainAccessCredentials;
  final CodePushClientBuilder _buildCodePushClient;
  final Logger logger;

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
      logger: logger,
    );
  }

  Future<void> login(void Function(String) prompt) async {
    if (_credentials != null) {
      throw UserAlreadyLoggedInException(email: _credentials!.email!);
    }

    final client = http.Client();
    try {
      _credentials = await _obtainAccessCredentials(
        _clientId,
        _scopes,
        client,
        prompt,
      );

      final codePushClient = _buildCodePushClient(httpClient: this.client);

      final user = await codePushClient.getCurrentUser();
      if (user == null) {
        throw UserNotFoundException(email: _credentials!.email!);
      }

      _email = user.email;
      _flushCredentials(_credentials!);
    } finally {
      client.close();
    }
  }

  void logout() => _clearCredentials();

  Future<User> signUp({
    required void Function(String) authPrompt,
    required String Function() namePrompt,
  }) async {
    if (_credentials != null) {
      throw UserAlreadyLoggedInException(email: _credentials!.email!);
    }

    final client = http.Client();
    final User newUser;
    try {
      _credentials = await _obtainAccessCredentials(
        _clientId,
        _scopes,
        client,
        authPrompt,
      );

      final codePushClient = _buildCodePushClient(httpClient: this.client);

      final existingUser = await codePushClient.getCurrentUser();
      if (existingUser != null) {
        throw UserAlreadyExistsException(existingUser);
      }

      newUser = await codePushClient.createUser(name: namePrompt());

      _email = newUser.email;
      _flushCredentials(_credentials!);
    } finally {
      client.close();
    }

    return newUser;
  }

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
  String? get email {
    final token = idToken;

    if (token == null) return null;

    final claims = Jwt.decodeClaims(token);

    if (claims == null) return null;

    return claims['email'] as String?;
  }
}

/// Thrown when an already authenticated user attempts to log in or sign up.
class UserAlreadyLoggedInException implements Exception {
  /// {@macro user_already_logged_in_exception}
  UserAlreadyLoggedInException({required this.email});

  /// The email of the already authenticated user, as derived from the stored
  /// auth credentials.
  final String email;
}

/// {@template user_not_found_exception}
/// Thrown when an attempt to fetch a User object results in a 404.
/// {@endtemplate}
class UserNotFoundException implements Exception {
  /// {@macro user_not_found_exception}
  UserNotFoundException({required this.email});

  /// The email used to locate the user, as derived from the stored auth
  /// credentials.
  final String email;
}

/// {@template user_already_exists_exception}
/// Thrown when an attempt to create a User object results in a 409.
/// {@endtemplate}
class UserAlreadyExistsException implements Exception {
  /// {@macro user_already_exists_exception}
  UserAlreadyExistsException(this.user);

  /// The existing user.
  final User user;
}
