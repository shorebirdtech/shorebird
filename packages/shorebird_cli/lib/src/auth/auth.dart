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

/// Callback for obtaining Shorebird access credentials via the device
/// authorization grant.
typedef ObtainCredentialsViaDeviceLogin =
    Future<oauth2.AccessCredentials> Function({
      required http.Client httpClient,
      required Uri authBaseUrl,
      required void Function(shorebird_oauth.DeviceAuthorization) userPrompt,
    });

/// Runs a process synchronously, as [Process.runSync] does.
typedef RunProcessSync =
    ProcessResult Function(String executable, List<String> arguments);

/// Callback when credentials are refreshed.
typedef OnRefreshCredentials =
    void Function(oauth2.AccessCredentials credentials);

/// Exchanges [expired] credentials for current ones.
typedef RefreshCredentials =
    Future<oauth2.AccessCredentials> Function(
      oauth2.AccessCredentials expired,
    );

/// A client that sends Shorebird-issued credentials, refreshing them through
/// the Shorebird auth service when they expire.
class AuthenticatedClient extends http.BaseClient {
  /// Creates a new [AuthenticatedClient] with the given [httpClient] and
  /// [credentials].
  ///
  /// Expired credentials are exchanged through [refreshCredentials] when
  /// given, and otherwise refreshed directly with the auth service.
  AuthenticatedClient({
    required http.Client httpClient,
    required oauth2.AccessCredentials credentials,
    required Uri authServiceUri,
    OnRefreshCredentials? onRefreshCredentials,
    RefreshCredentials? refreshCredentials,
  }) : _baseClient = httpClient,
       _credentials = credentials,
       _onRefreshCredentials = onRefreshCredentials,
       _refreshCredentials = refreshCredentials,
       _authServiceUri = authServiceUri;

  final http.Client _baseClient;
  final OnRefreshCredentials? _onRefreshCredentials;
  final RefreshCredentials? _refreshCredentials;
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
      final refreshCredentials = _refreshCredentials;
      if (refreshCredentials != null) {
        return await refreshCredentials(credentials);
      }
      return await shorebird_oauth.refreshShorebirdCredentials(
        credentials,
        _baseClient,
        authBaseUrl: _authServiceUri,
      );
    } on Exception catch (e, s) {
      if (e is shorebird_oauth.ShorebirdAuthException &&
          e.isCredentialRejection) {
        // The auth service answered with an OAuth error: these credentials
        // will not refresh again, whichever error code it was.
        logger
          ..err(
            'The Shorebird auth service rejected your stored credentials '
            '(${_describeOAuthError(e)}).',
          )
          ..info('Run ${lightCyan.wrap('shorebird login')} to log in again.')
          ..detail(e.toString())
          ..detail(s.toString());

        throw ProcessExit(ExitCode.software.code);
      }

      // No usable answer, which says nothing about the stored credentials.
      // Keep them and let the next command try again.
      final isRateLimited =
          e is shorebird_oauth.ShorebirdAuthException && e.isRateLimited;
      logger
        ..err(
          'Could not refresh your Shorebird credentials: '
          '${_describeTransientFailure(e)}',
        )
        ..info(
          isRateLimited
              ? 'Your login is unchanged. Try again shortly.'
              : 'Your login is unchanged. Check your network connection and '
                    'try again.',
        )
        ..detail(e.toString())
        ..detail(s.toString());

      throw ProcessExit(ExitCode.tempFail.code);
    }
  }
}

/// The OAuth `error` code of [error], with its `error_description` where the
/// auth service sent one.
String _describeOAuthError(shorebird_oauth.ShorebirdAuthException error) {
  final description = error.oauthErrorDescription;
  return [
    '${error.oauthError}',
    if (description != null) ': $description',
  ].join();
}

/// Why a refresh got no usable answer, as a sentence, without echoing a
/// response body.
String _describeTransientFailure(Exception error) {
  if (error is! shorebird_oauth.ShorebirdAuthException) {
    return 'Could not reach the Shorebird auth service.';
  }
  if (error.isRateLimited) return 'Too many requests.';
  final status = error.statusCode;
  if (status != null) return 'The Shorebird auth service answered $status.';
  return error.message;
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
    ObtainCredentialsViaDeviceLogin? obtainCredentialsViaDeviceLogin,
    CodePushClientBuilder? buildCodePushClient,
    RunProcessSync? runProcessSync,
  }) : _httpClient = httpClient ?? _defaultHttpClient,
       _runProcessSync = runProcessSync ?? Process.runSync,
       _credentialsDir =
           credentialsDir ?? BaseDirectories(executableName).configHome,
       _authServiceUri = authServiceUri ?? shorebirdEnv.authServiceUri,
       _obtainCredentialsViaLoopbackLogin =
           obtainCredentialsViaLoopbackLogin ??
           shorebird_oauth.obtainCredentialsViaLoopbackLogin,
       _obtainCredentialsViaDeviceLogin =
           obtainCredentialsViaDeviceLogin ??
           shorebird_oauth.obtainCredentialsViaDeviceLogin,
       _buildCodePushClient = buildCodePushClient ?? CodePushClient.new {
    _loadCredentials();
  }

  static http.Client get _defaultHttpClient => httpClient;

  final http.Client _httpClient;
  final String _credentialsDir;
  final Uri _authServiceUri;
  final ObtainCredentialsViaLoopbackLogin _obtainCredentialsViaLoopbackLogin;
  final ObtainCredentialsViaDeviceLogin _obtainCredentialsViaDeviceLogin;
  final CodePushClientBuilder _buildCodePushClient;
  final RunProcessSync _runProcessSync;
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
        refreshCredentials: _refreshCredentials,
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
  /// as a refresh, with the newest refresh token on disk (see
  /// [_refreshCredentials]).
  ///
  /// Returns false when the auth service answered the refresh with any OAuth
  /// error response (see
  /// [shorebird_oauth.ShorebirdAuthException.isCredentialRejection]).
  ///
  /// Throws when the auth service could not be reached, or answered with
  /// something other than an OAuth error response. That says nothing
  /// about whether they are still good, and answering `false` would log a
  /// user out for running `shorebird login` off wifi.
  Future<bool> hasValidCredentials() async {
    if (_apiKey != null) return true;

    final credentials = _credentials;
    if (credentials == null) return false;

    try {
      await _refreshCredentials(credentials, force: true);
      return true;
    } on shorebird_oauth.ShorebirdAuthException catch (error) {
      if (!error.isCredentialRejection) rethrow;
      logger.detail('Stored credentials are no longer valid: $error');
      return false;
    }
  }

  /// Exchanges [expired] for current credentials without presenting a
  /// refresh token another shorebird process has already rotated.
  ///
  /// The auth service rotates the refresh token on every refresh and treats
  /// a rotated one presented again, more than a short grace window later, as
  /// a sign it was stolen, revoking the session. Shorebird processes started
  /// from one login share that refresh token through the credentials file,
  /// and a long-running command may refresh long after another has rotated
  /// it. So re-read the file first: if another process has stored an access
  /// token that has not expired, use it (unless [force]); otherwise refresh
  /// with the refresh token on disk, which is the newest one.
  ///
  /// Two processes that refresh at the same moment both present the same
  /// token, which the grace window allows.
  Future<oauth2.AccessCredentials> _refreshCredentials(
    oauth2.AccessCredentials expired, {
    bool force = false,
  }) async {
    final stored = _readCredentialsFile() ?? expired;
    if (!force && !stored.accessToken.hasExpired) {
      return _useCredentials(stored);
    }
    final refreshed = await _refreshWithAuthService(stored);
    _flushCredentials(refreshed);
    return _useCredentials(refreshed);
  }

  Future<oauth2.AccessCredentials> _refreshWithAuthService(
    oauth2.AccessCredentials credentials,
  ) {
    return shorebird_oauth.refreshShorebirdCredentials(
      credentials,
      _httpClient,
      authBaseUrl: _authServiceUri,
    );
  }

  oauth2.AccessCredentials _useCredentials(
    oauth2.AccessCredentials credentials,
  ) {
    _credentials = credentials;
    _email = credentials.email ?? _email;
    return credentials;
  }

  /// Logs in the user via the Shorebird loopback OAuth flow.
  Future<void> login({required void Function(String) prompt}) {
    return _login(
      (client) => _obtainCredentialsViaLoopbackLogin(
        httpClient: client,
        authBaseUrl: _authServiceUri,
        userPrompt: prompt,
      ),
    );
  }

  /// Logs in the user via the device authorization grant (RFC 8628), which
  /// needs no browser on this machine: [prompt] is shown a code to approve
  /// in a browser on any device.
  ///
  /// Stores credentials exactly as [login] does, so refresh and [logout]
  /// work the same either way.
  Future<void> loginWithDeviceCode({
    required void Function(shorebird_oauth.DeviceAuthorization) prompt,
  }) {
    return _login(
      (client) => _obtainCredentialsViaDeviceLogin(
        httpClient: client,
        authBaseUrl: _authServiceUri,
        userPrompt: prompt,
      ),
    );
  }

  Future<void> _login(
    Future<oauth2.AccessCredentials> Function(http.Client client)
    obtainCredentials,
  ) async {
    if (isAuthenticated) {
      throw UserAlreadyLoggedInException(email: _email);
    }

    final client = http.Client();
    try {
      _credentials = await obtainCredentials(client);

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

    final credentials = _readCredentialsFile(warn: true);
    if (credentials == null) return;
    _credentials = credentials;
    _email = credentials.email;
  }

  /// Reads the credentials file, returning null when it is missing, cannot
  /// be parsed, or holds credentials Shorebird did not issue. With [warn],
  /// tells the user why unusable credentials were ignored.
  oauth2.AccessCredentials? _readCredentialsFile({bool warn = false}) {
    final credentialsFile = File(credentialsFilePath);
    if (!credentialsFile.existsSync()) return null;

    final oauth2.AccessCredentials credentials;
    try {
      final decoded = json.decode(credentialsFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Credentials are not a JSON object.');
      }
      credentials = oauth2.AccessCredentials.fromJson(decoded);
      // A field of the wrong type surfaces as a TypeError from fromJson.
      // ignore: avoid_catching_errors
    } on TypeError {
      if (warn) _warnUnreadableCredentials();
      return null;
      // An invalid value, such as a non-UTC expiry, surfaces as an
      // ArgumentError from AccessToken's constructor.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      if (warn) _warnUnreadableCredentials();
      return null;
    } on Exception {
      if (warn) _warnUnreadableCredentials();
      return null;
    }

    // Credentials from before Shorebird ran its own auth service were issued
    // by Google or Microsoft, which the server no longer accepts. Ignore them
    // rather than send them; `shorebird login` overwrites the file.
    if (!_isShorebirdIssued(credentials)) {
      if (warn) {
        logger.warn(
          '''Your stored credentials are no longer valid. Run ${lightCyan.wrap('shorebird login')} to sign in again.''',
        );
      }
      return null;
    }

    return credentials;
  }

  // Treat an unreadable credentials file as logged out rather than crashing,
  // so `shorebird login` and `shorebird logout` still work.
  void _warnUnreadableCredentials() {
    logger.warn(
      '''Your stored credentials could not be read. Run ${lightCyan.wrap('shorebird login')} to sign in again.''',
    );
  }

  bool _isShorebirdIssued(oauth2.AccessCredentials credentials) {
    try {
      return Jwt.parse(credentials.accessToken.data).payload.iss ==
          shorebirdEnv.jwtIssuer;
    } on Exception {
      return false;
    }
  }

  /// Writes [credentials] to the credentials file atomically: to a temporary
  /// file in the same directory, then renamed over it. Other shorebird
  /// processes read the file at any time, so they must see either the old
  /// credentials or the new ones, never a partial write.
  void _flushCredentials(oauth2.AccessCredentials credentials) {
    final temp = File('$credentialsFilePath.$pid.tmp')
      ..createSync(recursive: true);
    // The file holds a refresh token. Restrict it to the owner before the
    // token is written, so it is never readable by others, even briefly. This
    // checks the real host, not the scoped platform, because it is a real
    // file. Windows has no chmod; files under the user profile are already
    // private to the user. A missing chmod throws, so the token is never
    // written without the restriction having been attempted.
    if (!Platform.isWindows) {
      final result = _runProcessSync('chmod', ['600', temp.path]);
      if (result.exitCode != 0) {
        logger.detail(
          'Failed to restrict permissions on $credentialsFilePath '
          '(chmod exited ${result.exitCode}): ${result.stderr}',
        );
      }
    }
    temp
      ..writeAsStringSync(json.encode(credentials.toJson()), flush: true)
      ..renameSync(credentialsFilePath);
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
