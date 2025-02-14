// cspell:words googleapis bryanoltman endtemplate CLI tgvek orctktiabrek
// cspell:words GOCSPX googleusercontent Pkkwp Entra
import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/ci_token.dart';
import 'package:shorebird_cli/src/auth/endpoints/endpoints.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

export 'ci_token.dart';

/// A reference to an [Auth] instance.
final authRef = create(Auth.new);

/// The [Auth] instance available in the current zone.
Auth get auth => read(authRef);

/// The JWT issuer field for Google-issued JWTs.
const googleJwtIssuer = 'https://accounts.google.com';

/// Microsoft-issued JWTs are of the form
/// https://login.microsoftonline.com/{tenant-id}/v2.0. We don't care about the
/// tenant ID, so we just match the prefix.
const microsoftJwtIssuerPrefix = 'https://login.microsoftonline.com/';

/// The environment variable that holds the Shorebird CI token.
const shorebirdTokenEnvVar = 'SHOREBIRD_TOKEN';

/// Callback for obtaining access credentials.
typedef ObtainAccessCredentials =
    Future<oauth2.AccessCredentials> Function(
      oauth2.ClientId clientId,
      List<String> scopes,
      http.Client client,
      void Function(String) userPrompt, {
      oauth2.AuthEndpoints authEndpoints,
    });

/// Callback for refreshing access credentials.
typedef RefreshCredentials =
    Future<oauth2.AccessCredentials> Function(
      oauth2.ClientId clientId,
      oauth2.AccessCredentials credentials,
      http.Client client, {
      oauth2.AuthEndpoints authEndpoints,
    });

/// Callback when credentials are refreshed.
typedef OnRefreshCredentials =
    void Function(oauth2.AccessCredentials credentials);

/// A client that automatically refreshes OAuth 2.0 credentials.
class AuthenticatedClient extends http.BaseClient {
  /// Creates a new [AuthenticatedClient] with the given [httpClient] and
  /// [credentials].
  AuthenticatedClient.credentials({
    required http.Client httpClient,
    required oauth2.AccessCredentials credentials,
    OnRefreshCredentials? onRefreshCredentials,
    RefreshCredentials refreshCredentials = oauth2.refreshCredentials,
  }) : this._(
         httpClient: httpClient,
         onRefreshCredentials: onRefreshCredentials,
         credentials: credentials,
         refreshCredentials: refreshCredentials,
       );

  /// Creates a new [AuthenticatedClient] with the given [httpClient] and
  /// [token].
  AuthenticatedClient.token({
    required http.Client httpClient,
    required CiToken token,
    OnRefreshCredentials? onRefreshCredentials,
    RefreshCredentials refreshCredentials = oauth2.refreshCredentials,
  }) : this._(
         httpClient: httpClient,
         token: token,
         onRefreshCredentials: onRefreshCredentials,
         refreshCredentials: refreshCredentials,
       );

  AuthenticatedClient._({
    required http.Client httpClient,
    OnRefreshCredentials? onRefreshCredentials,
    oauth2.AccessCredentials? credentials,
    CiToken? token,
    RefreshCredentials refreshCredentials = oauth2.refreshCredentials,
  }) : _baseClient = httpClient,
       _credentials = credentials,
       _onRefreshCredentials = onRefreshCredentials,
       _refreshCredentials = refreshCredentials,
       _token = token;

  final http.Client _baseClient;
  final OnRefreshCredentials? _onRefreshCredentials;
  final RefreshCredentials _refreshCredentials;
  oauth2.AccessCredentials? _credentials;
  final CiToken? _token;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var credentials = _credentials;

    if (credentials == null) {
      final token = _token!;
      credentials =
          _credentials = await _tryRefreshCredentials(
            token.authProvider.clientId,
            oauth2.AccessCredentials(
              // This isn't relevant for a refresh operation.
              AccessToken('Bearer', '', DateTime.timestamp()),
              token.refreshToken,
              token.authProvider.scopes,
            ),
            _baseClient,
            authEndpoints: token.authProvider.authEndpoints,
          );
      _onRefreshCredentials?.call(credentials);
    }

    if (credentials.accessToken.hasExpired && credentials.idToken != null) {
      final jwt = Jwt.parse(credentials.idToken!);
      final authProvider = jwt.authProvider;

      credentials =
          _credentials = await _tryRefreshCredentials(
            authProvider.clientId,
            credentials,
            _baseClient,
            authEndpoints: authProvider.authEndpoints,
          );
      _onRefreshCredentials?.call(credentials);
    }

    final token = credentials.idToken;
    request.headers['Authorization'] = 'Bearer $token';
    return _baseClient.send(request);
  }

  Future<oauth2.AccessCredentials> _tryRefreshCredentials(
    oauth2.ClientId clientId,
    oauth2.AccessCredentials credentials,
    http.Client client, {
    required oauth2.AuthEndpoints authEndpoints,
  }) async {
    try {
      return await _refreshCredentials(
        clientId,
        credentials,
        client,
        authEndpoints: authEndpoints,
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

/// An OAuth 2.0 authentication provider.
class Auth {
  /// Creates a new [Auth] instance.
  Auth({
    http.Client? httpClient,
    String? credentialsDir,
    ObtainAccessCredentials? obtainAccessCredentials,
    CodePushClientBuilder? buildCodePushClient,
  }) : _httpClient = httpClient ?? _defaultHttpClient,
       _credentialsDir =
           credentialsDir ?? applicationConfigHome(executableName),
       _obtainAccessCredentials =
           obtainAccessCredentials ??
           oauth2.obtainAccessCredentialsViaUserConsent,
       _buildCodePushClient = buildCodePushClient ?? CodePushClient.new {
    _loadCredentials();
  }

  static http.Client get _defaultHttpClient => httpClient;

  final http.Client _httpClient;
  final String _credentialsDir;
  final ObtainAccessCredentials _obtainAccessCredentials;
  final CodePushClientBuilder _buildCodePushClient;
  CiToken? _token;

  /// The path to the credentials file.
  String get credentialsFilePath {
    return p.join(_credentialsDir, 'credentials.json');
  }

  /// The underlying HTTP client.
  http.Client get client {
    if (_credentials == null && _token == null) {
      return _httpClient;
    }

    if (_token != null) {
      return AuthenticatedClient.token(token: _token!, httpClient: _httpClient);
    }

    return AuthenticatedClient.credentials(
      credentials: _credentials!,
      httpClient: _httpClient,
      onRefreshCredentials: _flushCredentials,
    );
  }

  /// Gets a CI token for the current user.
  Future<CiToken> loginCI(
    AuthProvider authProvider, {
    required void Function(String) prompt,
  }) async {
    final client = http.Client();
    try {
      final credentials = await _obtainAccessCredentials(
        authProvider.clientId,
        authProvider.scopes,
        client,
        prompt,
        authEndpoints: authProvider.authEndpoints,
      );

      final codePushClient = _buildCodePushClient(
        httpClient: AuthenticatedClient.credentials(
          credentials: credentials,
          httpClient: _httpClient,
        ),
      );
      final user = await codePushClient.getCurrentUser();
      if (user == null) {
        throw UserNotFoundException(email: credentials.email!);
      }
      if (credentials.refreshToken == null) {
        throw Exception('No refresh token found.');
      }

      return CiToken(
        refreshToken: credentials.refreshToken!,
        authProvider: authProvider,
      );
    } finally {
      client.close();
    }
  }

  /// Logs in the user.
  Future<void> login(
    AuthProvider authProvider, {
    required void Function(String) prompt,
  }) async {
    if (isAuthenticated) {
      // Because isAuthenticated is checks for the presence of either an email
      // or a CI token, and because this method is for logging in without a CI
      // token, we can safely assume that _email is not null.
      throw UserAlreadyLoggedInException(email: _email!);
    }

    final client = http.Client();
    try {
      _credentials = await _obtainAccessCredentials(
        authProvider.clientId,
        authProvider.scopes,
        client,
        prompt,
        authEndpoints: authProvider.authEndpoints,
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

  /// Logs out the user.
  void logout() => _clearCredentials();

  oauth2.AccessCredentials? _credentials;

  String? _email;

  /// The current user's email.
  String? get email => _email;

  /// Whether the user is authenticated.
  bool get isAuthenticated => _email != null || _token != null;

  void _loadCredentials() {
    final envToken = platform.environment[shorebirdTokenEnvVar];
    if (envToken != null) {
      logger.info('$shorebirdTokenEnvVar detected');

      try {
        _token = CiToken.fromBase64(envToken.trim());
      } on FormatException catch (e) {
        logger
          ..err('''
Failed to parse CI token from environment. This likely means that your CI token is incorrectly formatted.

Please regenerate using `shorebird login:ci`, update the $shorebirdTokenEnvVar environment variable, and try again.''')
          ..detail(e.toString());
        rethrow;
      }

      logger.info('$shorebirdTokenEnvVar successfully parsed');
      return;
    }

    final credentialsFile = File(credentialsFilePath);
    if (credentialsFile.existsSync()) {
      try {
        final contents = credentialsFile.readAsStringSync();
        _credentials = oauth2.AccessCredentials.fromJson(
          json.decode(contents) as Map<String, dynamic>,
        );
        _email = _credentials?.email;
      } on Exception {
        // Swallow json decode exceptions.
      }
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

  /// Closes the underlying HTTP client.
  void close() {
    _httpClient.close();
  }
}

/// Extensions on [oauth2.AccessCredentials] for working with JWT claims.
extension JwtClaims on oauth2.AccessCredentials {
  /// Get the email from the JWT claims.
  String? get email {
    final token = idToken;

    if (token == null) return null;

    final Jwt jwt;
    try {
      jwt = Jwt.parse(token);
    } on Exception {
      return null;
    }

    return jwt.claims['email'] as String?;
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

/// Extensions on Jwt for working with OAuth 2.0 providers.
extension OauthAuthProvider on Jwt {
  /// Get the [AuthProvider] from the JWT issuer.
  AuthProvider get authProvider {
    if (payload.iss == googleJwtIssuer) {
      return AuthProvider.google;
    } else if (payload.iss.startsWith(microsoftJwtIssuerPrefix)) {
      return AuthProvider.microsoft;
    }

    throw Exception('Unknown jwt issuer: ${payload.iss}');
  }
}

/// Extension on [AuthProvider] which exposes OAuth 2.0 values.
extension OauthValues on AuthProvider {
  /// The OAuth 2.0 endpoints for the provider.
  oauth2.AuthEndpoints get authEndpoints => switch (this) {
    (AuthProvider.google) => const oauth2.GoogleAuthEndpoints(),
    (AuthProvider.microsoft) => MicrosoftAuthEndpoints(),
  };

  /// The OAuth 2.0 client ID for the provider.
  oauth2.ClientId get clientId {
    switch (this) {
      case AuthProvider.google:
        return oauth2.ClientId(
          /// Shorebird CLI's OAuth 2.0 identifier for GCP,
          '''523302233293-eia5antm0tgvek240t46orctktiabrek.apps.googleusercontent.com''',

          /// Shorebird CLI's OAuth 2.0 secret for GCP.
          ///
          /// This isn't actually meant to be kept secret.
          /// There is no way to properly secure a secret for installed/console applications.
          /// Fortunately the OAuth2 flow used in this case assumes that the app
          /// cannot keep secrets so this particular secret DOES NOT need to be
          /// kept secret. You should however make sure not to re-use the same
          /// secret anywhere secrecy is required.
          ///
          /// For more info see: https://developers.google.com/identity/protocols/oauth2/native-app
          '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',
        );
      case AuthProvider.microsoft:
        return oauth2.ClientId(
          /// Shorebird CLI's OAuth 2.0 identifier for Azure/Entra.
          '4fc38981-4ec4-4bd9-a755-e6ad9a413054',
        );
    }
  }

  /// The OAuth 2.0 scopes for the provider.
  List<String> get scopes => switch (this) {
    (AuthProvider.google) => [
      'openid',
      'https://www.googleapis.com/auth/userinfo.email',
    ],
    (AuthProvider.microsoft) => [
      'openid',
      'email',
      // Required to get refresh tokens.
      'offline_access',
    ],
  };
}
