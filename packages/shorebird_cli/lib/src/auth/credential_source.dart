import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// A way of authenticating requests to the Shorebird API: an API key, a
/// stored login, and so on.
///
/// A source answers one question, the `Authorization` header value to send
/// with the next request, and owns how it gets there: what it caches, when
/// it refreshes or exchanges a token, and whether it retries. This is the
/// shape of the AWS SDK's credential providers and google-auth-library's
/// credentials.
abstract class CredentialSource {
  /// Creates a [CredentialSource].
  const CredentialSource();

  /// Whether this source has credentials to offer, judged without a network
  /// request: an API key is set, a login is stored, and so on. A source that
  /// is available may still fail in [authorization].
  bool get isAvailable;

  /// Why this source is not available although the environment shows it was
  /// meant to be, such as a CI job missing a variable the source needs, or
  /// null. Reported when no source can authenticate.
  CredentialSourceException? get unavailableReason => null;

  /// The `Authorization` header value for the next request, such as
  /// `Bearer <token>`. Refreshes or exchanges credentials first if they
  /// need it.
  ///
  /// Throws a [CredentialSourceException] when this source cannot provide
  /// credentials after all, so that the next source in a [CredentialChain]
  /// is tried instead.
  Future<String> authorization();

  /// Checks the response to a request sent with this source's
  /// [authorization], before the caller sees it, and throws if this source
  /// treats it as a failure. Most sources accept every response.
  void checkResponse(http.BaseResponse response) {}
}

/// Thrown by a [CredentialSource] that cannot provide credentials. A
/// [CredentialChain] tries the next available source, or, when there is
/// none, reports [message] and [hint] and ends the command with [exitCode].
///
/// Neither [message] nor [hint] may contain a credential.
class CredentialSourceException implements Exception {
  /// Creates a [CredentialSourceException].
  const CredentialSourceException(
    this.message, {
    this.hint,
    this.exitCode = ExitCode.software,
  });

  /// What went wrong.
  final String message;

  /// What the user can do about it, if anything.
  final String? hint;

  /// How the command ends when no other source can authenticate:
  /// [ExitCode.tempFail] for a failure that may not recur.
  final ExitCode exitCode;

  @override
  String toString() => 'CredentialSourceException: $message';
}

/// The source that authenticates a request, and the `Authorization` header
/// value it answered.
typedef ResolvedCredential = ({CredentialSource source, String authorization});

/// [CredentialSource]s in the order they are tried.
///
/// Each request is authenticated by the first available source. A source
/// that throws a [CredentialSourceException] is skipped for the rest of the
/// run, and the next available one is used instead; when there is none, the
/// failure ends the command, reported with the chain's [unavailableReason].
class CredentialChain {
  /// Creates a [CredentialChain] that tries [sources] in order.
  CredentialChain(List<CredentialSource> sources)
    : _sources = List.unmodifiable(sources);

  final List<CredentialSource> _sources;

  /// Sources that threw a [CredentialSourceException] and are not tried
  /// again.
  final Set<CredentialSource> _failed = Set.identity();

  /// The sources this chain tries, in order.
  List<CredentialSource> get sources => _sources;

  /// Whether any source has credentials to offer.
  bool get isAvailable => _sources.any((source) => source.isAvailable);

  /// The [CredentialSource.unavailableReason] of the first source that has
  /// one, or null.
  CredentialSourceException? get unavailableReason {
    for (final source in _sources) {
      if (source.unavailableReason case final reason?) return reason;
    }
    return null;
  }

  /// The first available source that can authenticate the next request, and
  /// the `Authorization` header value it answered.
  Future<ResolvedCredential> resolve() async {
    for (final (index, source) in _sources.indexed) {
      if (!source.isAvailable || _failed.contains(source)) continue;
      try {
        return (source: source, authorization: await source.authorization());
      } on CredentialSourceException catch (e) {
        final hasNext = _sources
            .skip(index + 1)
            .any((next) => next.isAvailable && !_failed.contains(next));
        if (!hasNext) {
          logger.err(e.message);
          if (e.hint case final hint?) logger.info(hint);
          if (unavailableReason case final reason?) {
            logger.info(reason.message);
            if (reason.hint case final hint?) logger.info(hint);
          }
          throw ProcessExit(e.exitCode.code);
        }
        logger.detail('${e.message} Trying the next way to authenticate.');
        _failed.add(source);
      }
    }
    throw StateError('No credential source is available.');
  }
}

/// The HTTP client for authenticated requests to the Shorebird API.
///
/// Sets each request's `Authorization` header to what the [CredentialChain]
/// resolves, sends it through an ordinary HTTP client, which retries as it
/// does any request, and lets the source that answered check the response.
class AuthenticatedClient extends http.BaseClient {
  /// Creates an [AuthenticatedClient] that authenticates requests with
  /// [credentials] and sends them through [httpClient].
  AuthenticatedClient({
    required CredentialChain credentials,
    required http.Client httpClient,
  }) : _credentials = credentials,
       _httpClient = httpClient;

  final CredentialChain _credentials;
  final http.Client _httpClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final (:source, :authorization) = await _credentials.resolve();
    request.headers['Authorization'] = authorization;
    final response = await _httpClient.send(request);
    source.checkResponse(response);
    return response;
  }
}
