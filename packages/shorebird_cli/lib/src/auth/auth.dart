import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
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
    Future<oauth2.Credentials> Function({
      required http.Client httpClient,
      required Uri authBaseUrl,
      required void Function(String) userPrompt,
      Duration timeout,
    });

/// Callback for obtaining Shorebird access credentials via the device
/// authorization grant.
typedef ObtainCredentialsViaDeviceLogin =
    Future<oauth2.Credentials> Function({
      required http.Client httpClient,
      required Uri authBaseUrl,
      required void Function(shorebird_oauth.DeviceAuthorization) userPrompt,
    });

/// A login as the credentials file stores it: the `credentials`, and the
/// `email` of the user they belong to when it is known.
typedef _StoredLogin = ({oauth2.Credentials credentials, String? email});

/// Runs a process synchronously, as [Process.runSync] does.
typedef RunProcessSync =
    ProcessResult Function(String executable, List<String> arguments);

/// A client that sends the stored Shorebird credentials, refreshed first if
/// they have expired (see `Auth._currentClient`).
///
/// A refresh the auth service answers with an OAuth error ends the command
/// with instructions to log in again; any other failure to refresh ends it as
/// a temporary failure, leaving the stored credentials in place.
class AuthenticatedClient extends http.BaseClient {
  /// Creates an [AuthenticatedClient] that sends requests through the
  /// [oauth2.Client] [currentClient] returns.
  AuthenticatedClient({required Future<oauth2.Client> Function() currentClient})
    : _currentClient = currentClient;

  final Future<oauth2.Client> Function() _currentClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final oauth2.Client client;
    try {
      client = await _currentClient();
    } on oauth2.AuthorizationException catch (e, s) {
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
    } on oauth2.ExpirationException catch (e, s) {
      logger
        ..err('Your Shorebird login has expired.')
        ..info('Run ${lightCyan.wrap('shorebird login')} to log in again.')
        ..detail(e.toString())
        ..detail(s.toString());
      throw ProcessExit(ExitCode.software.code);
    } on Exception catch (e, s) {
      // No OAuth answer: no answer at all, a 5xx, a 429, or a body that is
      // not a token response. That says nothing about the stored
      // credentials, so keep them and let the next command try again.
      logger
        ..err(
          'Could not refresh your Shorebird credentials: '
          '${_describeTransientFailure(e)}',
        )
        ..info(
          'Your login is unchanged. Check your network connection and try '
          'again.',
        )
        ..detail(e.toString())
        ..detail(s.toString());
      throw ProcessExit(ExitCode.tempFail.code);
    }
    return client.send(request);
  }
}

/// The OAuth `error` code of [error], with its `error_description` where the
/// auth service sent one.
String _describeOAuthError(oauth2.AuthorizationException error) {
  final description = error.description;
  return [error.error, if (description != null) ': $description'].join();
}

/// Why a refresh got no OAuth answer, as a sentence, without echoing a
/// response body.
///
/// `package:oauth2` reports any answer that is neither a token response nor
/// an RFC 6749 section 5.2 error response (a 5xx, a 429, a page from a proxy)
/// as a [FormatException].
String _describeTransientFailure(Exception error) => error is FormatException
    ? 'The Shorebird auth service sent an unexpected answer.'
    : 'Could not reach the Shorebird auth service.';

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

  /// The path to the credentials file: [oauth2.Credentials] as JSON, with
  /// an `email` field naming the user they belong to.
  String get credentialsFilePath {
    return p.join(_credentialsDir, 'credentials-v2.json');
  }

  /// The path of the credentials file CLIs before `package:oauth2` wrote, in
  /// `package:googleapis_auth`'s format. Read once, to carry a login over to
  /// [credentialsFilePath] (see [_migrateLegacyCredentials]).
  String get legacyCredentialsFilePath {
    return p.join(_credentialsDir, 'credentials.json');
  }

  /// The underlying HTTP client.
  http.Client get client {
    if (_apiKey != null) {
      return ApiKeyClient(apiKey: _apiKey!, httpClient: _httpClient);
    }

    if (_oauthClient != null) {
      return AuthenticatedClient(currentClient: _currentClient);
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
  /// `_currentClient`).
  ///
  /// Returns false when the auth service answered the refresh with an OAuth
  /// error response ([oauth2.AuthorizationException]), or there is no refresh
  /// token to send.
  ///
  /// Throws when the auth service could not be reached, or answered with
  /// something other than a token or an OAuth error response. That says
  /// nothing about whether they are still good, and answering `false` would
  /// log a user out for running `shorebird login` off wifi.
  Future<bool> hasValidCredentials() async {
    if (_apiKey != null) return true;
    if (_oauthClient == null) return false;

    try {
      await _currentClient(force: true);
      return true;
    } on oauth2.AuthorizationException catch (error) {
      logger.detail('Stored credentials are no longer valid: $error');
      return false;
    } on oauth2.ExpirationException catch (error) {
      logger.detail('Stored credentials are no longer valid: $error');
      return false;
    }
  }

  /// The [oauth2.Client] for the stored credentials, refreshed first if its
  /// access token has expired (or, with [force], regardless).
  ///
  /// Never presents a refresh token another shorebird process has already
  /// rotated. The auth service rotates the refresh token on every refresh and
  /// treats a rotated one presented again, more than a short grace window
  /// later, as a sign it was stolen, revoking the session. Shorebird processes
  /// started from one login share that refresh token through the credentials
  /// file, and a long-running command may refresh long after another has
  /// rotated it. So before refreshing, adopt whatever the file holds now: an
  /// access token another process stored that has not expired is used as is
  /// (unless [force]); otherwise the refresh uses the refresh token on disk,
  /// which is the newest one. The client's `onCredentialsRefreshed` writes
  /// the rotated tokens back.
  ///
  /// Two processes that refresh at the same moment both present the same
  /// token, which the grace window allows.
  ///
  /// Throws [oauth2.AuthorizationException] when the auth service answers the
  /// refresh with an OAuth error, and [oauth2.ExpirationException] when the
  /// credentials have expired and hold no refresh token.
  Future<oauth2.Client> _currentClient({bool force = false}) async {
    var client = _oauthClient!;
    if (!force && !client.credentials.isExpired) return client;

    final stored = _readCredentialsFile();
    if (stored != null &&
        stored.credentials.accessToken != client.credentials.accessToken) {
      client = _useLogin(stored);
    }
    if (!force && !client.credentials.isExpired) return client;
    if (!client.credentials.canRefresh) {
      throw oauth2.ExpirationException(client.credentials);
    }
    await client.refreshCredentials();
    return client;
  }

  /// Makes [login]'s credentials the ones this process sends.
  oauth2.Client _useLogin(_StoredLogin login) {
    _email = login.email ?? _email;
    return _oauthClient = _clientFor(login.credentials);
  }

  /// An [oauth2.Client] that sends [credentials] and refreshes them as
  /// `shorebird-cli`, saving each refresh to the credentials file.
  oauth2.Client _clientFor(oauth2.Credentials credentials) {
    return oauth2.Client(
      credentials,
      identifier: shorebird_oauth.shorebirdCliClientId,
      httpClient: _httpClient,
      onCredentialsRefreshed: _saveRefreshedCredentials,
    );
  }

  void _saveRefreshedCredentials(oauth2.Credentials credentials) {
    try {
      _flushCredentials(credentials);
    } on FileSystemException catch (error) {
      // The refresh succeeded, so this command can carry on with the new
      // credentials. The file still holds the rotated refresh token, which
      // the auth service will reject once its grace window has passed.
      logger
        ..warn(
          'Could not save your refreshed Shorebird credentials to '
          '$credentialsFilePath. You may need to run '
          '${lightCyan.wrap('shorebird login')} again.',
        )
        ..detail(error.toString());
    }
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
    Future<oauth2.Credentials> Function(http.Client client) obtainCredentials,
  ) async {
    if (isAuthenticated) {
      throw UserAlreadyLoggedInException(email: _email);
    }

    final client = http.Client();
    try {
      final credentials = await obtainCredentials(client);
      final oauthClient = _clientFor(credentials);

      final codePushClient = _buildCodePushClient(
        httpClient: oauthClient,
        hostedUri: shorebirdEnv.hostedUri,
      );

      final user = await codePushClient.getCurrentUser();
      if (user == null) throw UserNotFoundException();

      _oauthClient = oauthClient;
      _email = user.email;
      _flushCredentials(oauthClient.credentials);
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
    final refreshToken = _oauthClient?.credentials.refreshToken;
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

  oauth2.Client? _oauthClient;

  String? _email;

  /// The current user's email, when it is known without asking the API:
  /// stored with the credentials at login. Null when authenticated with an
  /// API key. See [fetchEmail].
  String? get email => _email;

  /// Whether the user is authenticated: with an API key, or with stored
  /// credentials, which the auth service may still reject.
  bool get isAuthenticated => _oauthClient != null || _apiKey != null;

  /// Whether requests are authenticated with an API key from
  /// [shorebirdTokenEnvVar], which takes priority over stored credentials.
  bool get isUsingApiKey => _apiKey != null;

  /// The current user's email, fetched from the Shorebird API and saved with
  /// the credentials when they were stored without one, as credentials
  /// carried over from an older CLI are.
  ///
  /// Null when authenticated with an API key, when not logged in, or when
  /// the user could not be fetched. The access token is opaque to the CLI,
  /// so the API is the only place to learn who it belongs to.
  Future<String?> fetchEmail() async {
    if (_email != null || _apiKey != null || _oauthClient == null) {
      return _email;
    }

    final String email;
    try {
      final user = await _buildCodePushClient(
        httpClient: await _currentClient(),
        hostedUri: shorebirdEnv.hostedUri,
      ).getCurrentUser();
      if (user == null) return null;
      email = user.email;
    } on Exception catch (error) {
      logger.detail('Could not fetch the current user: $error');
      return null;
    }
    _email = email;

    // Add the email to the login on disk only while it is still this
    // process's login; another process may have stored a newer one.
    final stored = _readCredentialsFile();
    if (stored != null &&
        stored.credentials.accessToken ==
            _oauthClient?.credentials.accessToken) {
      try {
        _flushCredentials(stored.credentials);
      } on FileSystemException catch (error) {
        logger.detail(
          'Could not save your email to $credentialsFilePath: $error',
        );
      }
    }
    return email;
  }

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

    final login = _readCredentialsFile(warn: true);
    if (login == null) return;
    _useLogin(login);
  }

  /// Reads the credentials file, returning null when it is missing or cannot
  /// be parsed. With [warn], tells the user why unreadable credentials were
  /// ignored.
  ///
  /// When there is no credentials file but a legacy one, carries its login
  /// over first (see [_migrateLegacyCredentials]).
  _StoredLogin? _readCredentialsFile({bool warn = false}) {
    final credentialsFile = File(credentialsFilePath);
    if (!credentialsFile.existsSync()) {
      final credentials = _migrateLegacyCredentials(warn: warn);
      if (credentials == null) return null;
      return (credentials: credentials, email: null);
    }

    try {
      final contents = credentialsFile.readAsStringSync();
      // fromJson ignores fields it does not know, such as `email`.
      final credentials = oauth2.Credentials.fromJson(contents);
      final email = (jsonDecode(contents) as Map)['email'];
      return (credentials: credentials, email: email is String ? email : null);
    } on Exception {
      if (warn) _warnUnreadableCredentials();
      return null;
      // A field fromJson does not validate, such as a missing `scopes`,
      // surfaces as a TypeError.
      // ignore: avoid_catching_errors
    } on TypeError {
      if (warn) _warnUnreadableCredentials();
      return null;
    }
  }

  /// Carries a login stored in [legacyCredentialsFilePath], in
  /// `package:googleapis_auth`'s `AccessCredentials` format, over to
  /// [credentialsFilePath], then deletes the legacy file.
  ///
  /// The legacy file is deleted rather than left for older CLIs on this
  /// machine: the two files would hold one session, and once this CLI rotated
  /// its refresh token, an older CLI presenting the old one would look like a
  /// stolen token to the auth service, which revokes the session for both.
  /// An older CLI finds itself logged out instead, and `shorebird login`
  /// there starts a session of its own.
  ///
  /// The credentials are used even if they cannot be written to the new
  /// file, in which case the legacy file is kept and read again next time.
  oauth2.Credentials? _migrateLegacyCredentials({required bool warn}) {
    final legacyFile = File(legacyCredentialsFilePath);
    if (!legacyFile.existsSync()) return null;

    final oauth2.Credentials credentials;
    try {
      final json = jsonDecode(legacyFile.readAsStringSync());
      if (json case {
        'accessToken': {
          'data': final String accessToken,
          'expiry': final String expiry,
        },
      } when json['refreshToken'] is String?) {
        credentials = oauth2.Credentials(
          accessToken,
          refreshToken: json['refreshToken'] as String?,
          tokenEndpoint: shorebird_oauth.tokenEndpointFor(_authServiceUri),
          scopes: [shorebird_oauth.shorebirdCliScope],
          expiration: DateTime.parse(expiry),
        );
      } else {
        throw const FormatException('Not googleapis_auth credentials.');
      }
    } on FormatException {
      if (warn) _warnUnreadableCredentials();
      return null;
    }

    try {
      _flushCredentials(credentials);
      legacyFile.deleteSync();
    } on FileSystemException catch (error) {
      logger.detail(
        'Could not move $legacyCredentialsFilePath to '
        '$credentialsFilePath: $error',
      );
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

  /// Writes [credentials], with the current user's email when it is known,
  /// to the credentials file atomically: to a temporary file in the same
  /// directory, then renamed over it. Other shorebird processes read the
  /// file at any time, so they must see either the old credentials or the
  /// new ones, never a partial write.
  ///
  /// Deletes the temporary file if the write fails, since it holds a refresh
  /// token.
  void _flushCredentials(oauth2.Credentials credentials) {
    final temp = File('$credentialsFilePath.$pid.tmp')
      ..createSync(recursive: true);
    try {
      _writeCredentials(temp, credentials);
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  void _writeCredentials(File temp, oauth2.Credentials credentials) {
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
    final contents = jsonEncode({
      ...jsonDecode(credentials.toJson()) as Map<String, Object?>,
      'email': ?_email,
    });
    temp.writeAsStringSync(contents, flush: true);
    try {
      temp.renameSync(credentialsFilePath);
    } on FileSystemException catch (error) {
      // Windows refuses to replace a file another process has open, such as
      // another shorebird command reading it or an antivirus scanner. Write
      // in place instead, which Windows allows, rather than lose credentials
      // the auth service has already rotated. A process reading at that
      // moment may see a partial file, which it treats as unreadable.
      logger.detail(
        'Could not replace $credentialsFilePath ($error); writing it in '
        'place.',
      );
      File(credentialsFilePath).writeAsStringSync(contents, flush: true);
    }
  }

  /// Deletes the locally stored credentials without revoking the server-side
  /// session.
  ///
  /// Deletes a legacy credentials file too, which an older CLI may have
  /// written since, so that this CLI does not carry that login over again.
  void clearCredentials() {
    _oauthClient = null;
    _email = null;

    for (final path in [credentialsFilePath, legacyCredentialsFilePath]) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// Closes the underlying HTTP client.
  void close() {
    _httpClient.close();
  }
}

/// Thrown when an already authenticated user attempts to log in or sign up.
class UserAlreadyLoggedInException implements Exception {
  /// {@macro user_already_logged_in_exception}
  UserAlreadyLoggedInException({this.email});

  /// The email of the already authenticated user, or `null` when
  /// authenticated with an API key or the email is not known.
  final String? email;
}

/// Thrown when the credentials a login obtained belong to no Shorebird
/// user: fetching the current user results in a 404.
class UserNotFoundException implements Exception {}
