import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart' as shorebird_oauth;
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// A reference to an [Auth] instance.
final authRef = create(Auth.new);

/// The [Auth] instance available in the current zone.
Auth get auth => read(authRef);

/// The environment variable that holds a Shorebird API key for CI.
const shorebirdTokenEnvVar = 'SHOREBIRD_TOKEN';

/// The prefix every Shorebird API key starts with.
const apiKeyPrefix = 'sb_api_';

/// Callback for obtaining Shorebird access credentials via loopback login.
typedef ObtainCredentialsViaLoopbackLogin =
    Future<oauth2.AccessCredentials> Function({
      required http.Client httpClient,
      required Uri authBaseUrl,
      required void Function(String) userPrompt,
      Duration timeout,
    });

/// Callback when credentials are refreshed.
typedef OnRefreshCredentials =
    void Function(oauth2.AccessCredentials credentials);

/// A client that sends Shorebird-issued credentials, refreshing them through
/// the Shorebird auth service when they expire.
class AuthenticatedClient extends http.BaseClient {
  /// Creates a new [AuthenticatedClient] with the given [httpClient] and
  /// [credentials].
  AuthenticatedClient({
    required http.Client httpClient,
    required oauth2.AccessCredentials credentials,
    required Uri authServiceUri,
    OnRefreshCredentials? onRefreshCredentials,
  }) : _baseClient = httpClient,
       _credentials = credentials,
       _onRefreshCredentials = onRefreshCredentials,
       _authServiceUri = authServiceUri;

  final http.Client _baseClient;
  final OnRefreshCredentials? _onRefreshCredentials;
  final Uri _authServiceUri;
  oauth2.AccessCredentials _credentials;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_credentials.accessToken.hasExpired) {
      _credentials = await _refresh(_credentials);
      _onRefreshCredentials?.call(_credentials);
    }

    request.headers['Authorization'] =
        'Bearer ${_credentials.accessToken.data}';
    return _baseClient.send(request);
  }

  Future<oauth2.AccessCredentials> _refresh(
    oauth2.AccessCredentials credentials,
  ) async {
    try {
      return await shorebird_oauth.refreshShorebirdCredentials(
        credentials,
        _baseClient,
        authBaseUrl: _authServiceUri,
      );
    } on Exception catch (e, s) {
      logger
        ..err('Failed to refresh credentials.')
        ..info(
          '''Try logging out with ${lightBlue.wrap('shorebird logout')} and logging in again.''',
        )
        ..detail(e.toString())
        ..detail(s.toString());

      throw ProcessExit(ExitCode.software.code);
    }
  }
}

/// An HTTP client that authenticates requests using an API key.
///
/// Unlike [AuthenticatedClient], this client does not perform any token
/// refresh or exchange — the API key is sent directly in the Authorization
/// header and the server handles validation.
class ApiKeyClient extends http.BaseClient {
  /// Creates a new [ApiKeyClient].
  ApiKeyClient({required String apiKey, required http.Client httpClient})
    : _apiKey = apiKey,
      _baseClient = httpClient;

  final String _apiKey;
  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_apiKey';
    return _baseClient.send(request);
  }
}

/// An OAuth 2.0 authentication provider.
class Auth {
  /// Creates a new [Auth] instance.
  Auth({
    http.Client? httpClient,
    String? credentialsDir,
    Uri? authServiceUri,
    ObtainCredentialsViaLoopbackLogin? obtainCredentialsViaLoopbackLogin,
    CodePushClientBuilder? buildCodePushClient,
  }) : _httpClient = httpClient ?? _defaultHttpClient,
       _credentialsDir =
           credentialsDir ?? BaseDirectories(executableName).configHome,
       _authServiceUri = authServiceUri ?? shorebirdEnv.authServiceUri,
       _obtainCredentialsViaLoopbackLogin =
           obtainCredentialsViaLoopbackLogin ??
           shorebird_oauth.obtainCredentialsViaLoopbackLogin,
       _buildCodePushClient = buildCodePushClient ?? CodePushClient.new {
    _loadCredentials();
  }

  static http.Client get _defaultHttpClient => httpClient;

  final http.Client _httpClient;
  final String _credentialsDir;
  final Uri _authServiceUri;
  final ObtainCredentialsViaLoopbackLogin _obtainCredentialsViaLoopbackLogin;
  final CodePushClientBuilder _buildCodePushClient;
  String? _apiKey;

  /// The path to the credentials file.
  String get credentialsFilePath {
    return p.join(_credentialsDir, 'credentials.json');
  }

  /// The underlying HTTP client.
  http.Client get client {
    if (_apiKey != null) {
      return ApiKeyClient(apiKey: _apiKey!, httpClient: _httpClient);
    }

    if (_credentials != null) {
      return AuthenticatedClient(
        credentials: _credentials!,
        httpClient: _httpClient,
        authServiceUri: _authServiceUri,
        onRefreshCredentials: _flushCredentials,
      );
    }

    return _httpClient;
  }

  /// Whether the locally stored credentials are still usable.
  ///
  /// API keys are validated server-side on every request and are always
  /// reported as valid. Stored OAuth credentials are verified by refreshing
  /// them against the auth service, which fails once the session has expired
  /// or been revoked. Refreshed credentials are persisted so the check doubles
  /// as a refresh.
  ///
  /// Throws when the auth service could not be reached, or answered with
  /// something other than a refusal of these credentials. That says nothing
  /// about whether they are still good, and answering `false` would log a
  /// user out for running `shorebird login` off wifi.
  Future<bool> hasValidCredentials() async {
    if (_apiKey != null) return true;

    final credentials = _credentials;
    if (credentials == null) return false;

    try {
      final refreshed = await shorebird_oauth.refreshShorebirdCredentials(
        credentials,
        _httpClient,
        authBaseUrl: _authServiceUri,
      );
      _credentials = refreshed;
      _email = refreshed.email ?? _email;
      _flushCredentials(refreshed);
      return true;
    } on shorebird_oauth.ShorebirdAuthException catch (error) {
      if (!error.isCredentialRejection) rethrow;
      logger.detail('Stored credentials are no longer valid: $error');
      return false;
    }
  }

  /// Logs in the user via the Shorebird loopback OAuth flow.
  Future<void> login({required void Function(String) prompt}) async {
    if (isAuthenticated) {
      throw UserAlreadyLoggedInException(email: _email);
    }

    final client = http.Client();
    try {
      _credentials = await _obtainCredentialsViaLoopbackLogin(
        httpClient: client,
        authBaseUrl: _authServiceUri,
        userPrompt: prompt,
      );

      final codePushClient = _buildCodePushClient(
        httpClient: this.client,
        hostedUri: shorebirdEnv.hostedUri,
      );

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

  /// Logs out the user.
  ///
  /// Revokes the stored refresh token with the auth service, which ends the
  /// server-side session, then clears local credentials. Local credentials
  /// are cleared even if revocation fails. Returns whether the auth service
  /// confirmed the revocation (true when there was nothing to revoke).
  Future<bool> logout() async {
    final revoked = await _revokeSession();
    clearCredentials();
    return revoked;
  }

  /// Revokes the current refresh token through the auth service's RFC 7009
  /// revocation endpoint. Returns whether the server confirmed it, or true
  /// when there is no refresh token to revoke. A failure is logged at detail
  /// level and otherwise swallowed, so that local logout always succeeds.
  Future<bool> _revokeSession() async {
    final refreshToken = _credentials?.refreshToken;
    if (refreshToken == null) return true;

    try {
      await shorebird_oauth.revokeShorebirdRefreshToken(
        refreshToken,
        _httpClient,
        authBaseUrl: _authServiceUri,
      );
      return true;
    } on Exception catch (e) {
      logger.detail('Failed to revoke session: $e');
      return false;
    }
  }

  oauth2.AccessCredentials? _credentials;

  String? _email;

  /// The current user's email.
  String? get email => _email;

  /// Whether the user is authenticated.
  bool get isAuthenticated => _email != null || _apiKey != null;

  void _loadCredentials() {
    final envToken = platform.environment[shorebirdTokenEnvVar];
    if (envToken != null) {
      final trimmed = envToken.trim();
      logger.detail('[env] $shorebirdTokenEnvVar detected');

      if (!trimmed.startsWith(apiKeyPrefix)) {
        // Most likely a CI token from the removed `shorebird login:ci`, which
        // the server no longer accepts.
        logger
          ..err(
            '$shorebirdTokenEnvVar is not a Shorebird API key '
            '(API keys start with $apiKeyPrefix).',
          )
          ..info(
            '''CI tokens from `shorebird login:ci` are no longer supported. Create an API key at ${link(uri: Uri.parse('https://console.shorebird.dev'))} and set it as your ${lightCyan.wrap(shorebirdTokenEnvVar)} environment variable.''',
          );
        throw ProcessExit(ExitCode.config.code);
      }

      _apiKey = trimmed;
      logger.detail('[env] $shorebirdTokenEnvVar parsed as API key');
      return;
    }

    final credentialsFile = File(credentialsFilePath);
    if (!credentialsFile.existsSync()) return;

    final oauth2.AccessCredentials credentials;
    try {
      credentials = oauth2.AccessCredentials.fromJson(
        json.decode(credentialsFile.readAsStringSync()) as Map<String, dynamic>,
      );
    } on Exception {
      // Swallow json decode exceptions.
      return;
    }

    // Credentials from before Shorebird ran its own auth service were issued
    // by Google or Microsoft, which the server no longer accepts. Ignore them
    // rather than send them; `shorebird login` overwrites the file.
    if (!_isShorebirdIssued(credentials)) {
      logger.warn(
        '''Your stored credentials are no longer valid. Run ${lightCyan.wrap('shorebird login')} to sign in again.''',
      );
      return;
    }

    _credentials = credentials;
    _email = credentials.email;
  }

  bool _isShorebirdIssued(oauth2.AccessCredentials credentials) {
    try {
      return Jwt.parse(credentials.accessToken.data).payload.iss ==
          shorebirdEnv.jwtIssuer;
    } on Exception {
      return false;
    }
  }

  void _flushCredentials(oauth2.AccessCredentials credentials) {
    File(credentialsFilePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(json.encode(credentials.toJson()));
  }

  /// Deletes the locally stored credentials without revoking the server-side
  /// session.
  void clearCredentials() {
    _credentials = null;
    _email = null;

    final credentialsFile = File(credentialsFilePath);
    if (credentialsFile.existsSync()) {
      credentialsFile.deleteSync(recursive: true);
    }
  }

  /// Closes the underlying HTTP client.
  void close() {
    _httpClient.close();
  }
}

/// Extensions on [oauth2.AccessCredentials] for working with JWT claims.
extension JwtClaims on oauth2.AccessCredentials {
  /// Get the email from the claims of the access token, which the Shorebird
  /// auth service issues as a JWT.
  String? get email {
    final Jwt jwt;
    try {
      jwt = Jwt.parse(accessToken.data);
    } on Exception {
      return null;
    }

    return jwt.claims['email'] as String?;
  }
}

/// Thrown when an already authenticated user attempts to log in or sign up.
class UserAlreadyLoggedInException implements Exception {
  /// {@macro user_already_logged_in_exception}
  UserAlreadyLoggedInException({this.email});

  /// The email of the already authenticated user, or `null` when
  /// authenticated via an environment variable (API key / CI token).
  final String? email;
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
