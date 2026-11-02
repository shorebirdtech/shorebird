import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/credential_source.dart';
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart' as shorebird_oauth;
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';

/// The `grant_type` of an OAuth 2.0 token exchange (RFC 8693 section 2.1).
const tokenExchangeGrantType =
    'urn:ietf:params:oauth:grant-type:token-exchange';

/// The `subject_token_type` naming an OIDC ID token (RFC 8693 section 3).
const idTokenType = 'urn:ietf:params:oauth:token-type:id_token';

/// The id of the Shorebird project whose trust rules an OIDC sign-in is
/// matched against, as the console shows it.
const shorebirdProjectIdEnvVar = 'SHOREBIRD_PROJECT_ID';

/// The RFC 8693 `audience` naming the Shorebird project with [projectId].
String projectAudience(String projectId) => 'urn:shorebird:project:$projectId';

/// How long before its expiry an access token is exchanged for a new one,
/// so that a request is never sent with a token about to expire.
const accessTokenRefreshMargin = Duration(seconds: 60);

/// How long to wait before each retry of an exchange that failed for a
/// reason that may not recur, as `package:http`'s `RetryClient` waits.
const exchangeRetryDelays = [
  Duration(milliseconds: 500),
  Duration(milliseconds: 750),
  Duration(milliseconds: 1125),
];

/// Supplies the OIDC ID token a CI provider issues for the current job, to
/// be exchanged for a Shorebird access token. One implementation per
/// provider, as google-auth-library's external account credentials take a
/// subject token supplier.
abstract interface class SubjectTokenSupplier {
  /// The CI provider, as messages name it: `GitHub Actions`.
  String get name;

  /// A new ID token for the Shorebird auth service. Called once per
  /// exchange attempt, since the auth service accepts each ID token only
  /// once.
  ///
  /// Throws a [CredentialSourceException] when the provider does not issue
  /// one. Its message must not contain a token.
  Future<String> subjectToken();
}

/// A Shorebird access token and when it expires.
typedef _AccessToken = ({String value, DateTime expiresAt});

/// Authenticates as the service account a Shorebird trust rule maps a CI
/// job to, by exchanging the OIDC ID token the CI provider issues for it.
///
/// The exchange names the project whose trust rules are matched as its
/// `audience` (RFC 8693 section 2.1), so the source has no credentials to
/// offer without a project id; see [unavailableReason].
///
/// Before the first request, and again once the current access token is
/// within [accessTokenRefreshMargin] of expiring, gets an ID token from
/// [SubjectTokenSupplier] and exchanges it at the auth service's token
/// endpoint (RFC 8693) for a short-lived Shorebird access token. Concurrent
/// requests share one exchange.
///
/// The auth service accepts an ID token only once, so an exchange is never
/// sent twice: it goes through a client that does not retry on its own, and
/// after a network failure or a 5xx this source starts over with a new ID
/// token, up to [exchangeRetryDelays] times. An OAuth error is not retried.
///
/// Fails with a [CredentialSourceException] that names the auth service's
/// `error` and `error_description` when it refuses the exchange.
class OidcCredentialSource extends CredentialSource {
  /// Creates an [OidcCredentialSource] that exchanges ID tokens from
  /// [subjectTokenSupplier] at the auth service at [authBaseUrl], for the
  /// project whose id is [projectId], the value of
  /// [shorebirdProjectIdEnvVar].
  ///
  /// The source is not available when [projectId] is null or, once trimmed,
  /// is not a project id.
  ///
  /// Exchanges are sent through [exchangeClient], which must not retry
  /// requests itself: a retry would present an ID token again.
  OidcCredentialSource({
    required SubjectTokenSupplier subjectTokenSupplier,
    required String? projectId,
    required Uri authBaseUrl,
    required http.Client exchangeClient,
    Future<void> Function(Duration) sleep = _delay,
  }) : _supplier = subjectTokenSupplier,
       _projectId = _parseProjectId(projectId),
       _authBaseUrl = authBaseUrl,
       _exchangeClient = exchangeClient,
       _sleep = sleep,
       unavailableReason = _projectIdProblem(
         projectId,
         provider: subjectTokenSupplier.name,
       );

  /// Why [projectId] cannot be used to sign in with [provider] OIDC, or null
  /// when it can.
  static CredentialSourceException? _projectIdProblem(
    String? projectId, {
    required String provider,
  }) {
    final String message;
    if (projectId == null || projectId.trim().isEmpty) {
      message =
          'Signing in with $provider OIDC requires $shorebirdProjectIdEnvVar.';
    } else if (_parseProjectId(projectId) == null) {
      message =
          '$shorebirdProjectIdEnvVar is not a Shorebird project id, so this '
          'job cannot sign in with $provider OIDC.';
    } else {
      return null;
    }
    return CredentialSourceException(
      message,
      hint:
          'Set $shorebirdProjectIdEnvVar to the id of your project shown at '
          '${ShorebirdWebConsole.baseUri}, or set $shorebirdTokenEnvVar to a '
          'Shorebird API key.',
    );
  }

  static final _projectIdPattern = RegExp(r'^[0-9]+$');

  static String? _parseProjectId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || !_projectIdPattern.hasMatch(trimmed)) return null;
    return trimmed;
  }

  final SubjectTokenSupplier _supplier;
  final String? _projectId;
  final Uri _authBaseUrl;
  final http.Client _exchangeClient;
  final Future<void> Function(Duration) _sleep;

  _AccessToken? _accessToken;
  Future<_AccessToken>? _pendingExchange;

  /// The CI provider this source signs in with, as messages name it.
  String get providerName => _supplier.name;

  /// When the access token from the last exchange expires, or null before
  /// the first exchange.
  DateTime? get accessTokenExpiresAt => _accessToken?.expiresAt;

  /// A source is created only for a job its provider issues ID tokens to,
  /// so it is available whenever it has a project id.
  @override
  bool get isAvailable => _projectId != null;

  /// Why there is no project id, when there is none.
  @override
  final CredentialSourceException? unavailableReason;

  @override
  Future<String> authorization() async {
    final current = _accessToken;
    if (current != null &&
        clock.now().isBefore(
          current.expiresAt.subtract(accessTokenRefreshMargin),
        )) {
      return 'Bearer ${current.value}';
    }

    final pending = _pendingExchange ??= _exchange();
    try {
      final token = await pending;
      _accessToken = token;
      return 'Bearer ${token.value}';
    } finally {
      if (identical(_pendingExchange, pending)) _pendingExchange = null;
    }
  }

  /// Gets an ID token and exchanges it, starting over with a new ID token
  /// after a network failure or a 5xx from the auth service, up to
  /// [exchangeRetryDelays] times.
  Future<_AccessToken> _exchange() async {
    for (var attempt = 0; ; attempt++) {
      logger.detail('[oidc] Requesting a ${_supplier.name} OIDC token');
      final idToken = await _supplier.subjectToken();
      logger.detail('[oidc] Exchanging it for a Shorebird access token');
      try {
        final token = await _exchangeIdToken(idToken);
        logger.detail('[oidc] Access token expires at ${token.expiresAt}');
        return token;
      } on _TransientExchangeFailure catch (failure) {
        if (attempt >= exchangeRetryDelays.length) throw failure.exception;
        logger.detail(
          '[oidc] ${failure.exception.message} Retrying with a new '
          '${_supplier.name} OIDC token.',
        );
        await _sleep(exchangeRetryDelays[attempt]);
      }
    }
  }

  /// Exchanges [idToken] at the auth service's token endpoint for a Shorebird
  /// access token.
  Future<_AccessToken> _exchangeIdToken(String idToken) async {
    final provider = _supplier.name;
    final projectId = _projectId!;
    final requestedAt = clock.now();
    final http.Response response;
    try {
      response = await _exchangeClient.post(
        shorebird_oauth.tokenEndpointFor(_authBaseUrl),
        body: {
          'grant_type': tokenExchangeGrantType,
          'subject_token_type': idTokenType,
          'subject_token': idToken,
          'audience': projectAudience(projectId),
        },
      );
    } on Exception catch (e, s) {
      final exception = CredentialSourceException(
        'Could not reach the Shorebird auth service to sign in with '
        '$provider OIDC: $e',
      );
      if (isRetryableException(e, s)) {
        throw _TransientExchangeFailure(exception);
      }
      throw exception;
    }

    if (isRetryableResponse(response)) {
      throw _TransientExchangeFailure(
        CredentialSourceException(
          'The Shorebird auth service could not sign in with $provider '
          'OIDC (${response.statusCode}).',
        ),
      );
    }

    final json = _decodeJsonObject(response.body);
    if (response.statusCode != HttpStatus.ok) {
      final error = json?['error'];
      if (error is String) {
        final description = json?['error_description'];
        final reason = [
          error,
          if (description is String) ': $description',
        ].join();
        throw CredentialSourceException(
          'The Shorebird auth service refused to sign in with $provider '
          'OIDC ($reason).',
          hint:
              'Check that a $provider trust rule in project $projectId at '
              '${ShorebirdWebConsole.baseUri} matches this job.',
        );
      }
      throw CredentialSourceException(
        'The Shorebird auth service could not sign in with $provider '
        'OIDC (${response.statusCode}).',
      );
    }

    if (json case {
      'access_token': final String accessToken,
      'token_type': final String tokenType,
      'expires_in': final int expiresIn,
    } when tokenType.toLowerCase() == 'bearer' && accessToken.isNotEmpty) {
      return (
        value: accessToken,
        expiresAt: requestedAt.add(Duration(seconds: expiresIn)),
      );
    }
    throw const CredentialSourceException(
      'The Shorebird auth service sent an unexpected token response.',
    );
  }
}

Future<void> _delay(Duration duration) => Future<void>.delayed(duration);

/// An exchange that failed for a reason that may not recur: no answer, or a
/// 5xx.
class _TransientExchangeFailure implements Exception {
  const _TransientExchangeFailure(this.exception);

  final CredentialSourceException exception;
}

Map<String, dynamic>? _decodeJsonObject(String body) {
  try {
    final json = jsonDecode(body);
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}
