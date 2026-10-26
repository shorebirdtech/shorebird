import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/credential_source.dart';
import 'package:shorebird_cli/src/auth/oidc_credential_source.dart';

/// Set by GitHub Actions to `true` in every workflow run.
const githubActionsEnvVar = 'GITHUB_ACTIONS';

/// The URL a GitHub Actions job requests an OIDC ID token from. GitHub sets
/// it only for jobs granted `permissions: id-token: write`.
const actionsIdTokenRequestUrlEnvVar = 'ACTIONS_ID_TOKEN_REQUEST_URL';

/// The bearer token that authorizes a request to
/// [actionsIdTokenRequestUrlEnvVar]. Set alongside it.
const actionsIdTokenRequestTokenEnvVar = 'ACTIONS_ID_TOKEN_REQUEST_TOKEN';

/// Requests the OIDC ID token GitHub Actions issues a job granted
/// `permissions: id-token: write`, with the Shorebird auth service as its
/// `audience`.
class GitHubActionsSubjectTokenSupplier implements SubjectTokenSupplier {
  /// Creates a [GitHubActionsSubjectTokenSupplier] that requests ID tokens
  /// for [audience] from [requestUrl], authorized by [requestToken], through
  /// [httpClient].
  GitHubActionsSubjectTokenSupplier({
    required Uri requestUrl,
    required String requestToken,
    required Uri audience,
    required http.Client httpClient,
  }) : _requestUrl = requestUrl,
       _requestToken = requestToken,
       _audience = audience,
       _httpClient = httpClient;

  /// The supplier for the ID token request GitHub set in [environment], or
  /// null when this is not a GitHub Actions job granted
  /// `permissions: id-token: write`.
  static GitHubActionsSubjectTokenSupplier? fromEnvironment(
    Map<String, String> environment, {
    required Uri audience,
    required http.Client httpClient,
  }) {
    final url = environment[actionsIdTokenRequestUrlEnvVar];
    final token = environment[actionsIdTokenRequestTokenEnvVar];
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;
    return GitHubActionsSubjectTokenSupplier(
      requestUrl: parsed,
      requestToken: token,
      audience: audience,
      httpClient: httpClient,
    );
  }

  final Uri _requestUrl;
  final String _requestToken;
  final Uri _audience;
  final http.Client _httpClient;

  @override
  String get name => 'GitHub Actions';

  @override
  Future<String> subjectToken() async {
    final audience = Uri.encodeQueryComponent(_audience.toString());
    final url = Uri.parse(
      '$_requestUrl${_requestUrl.hasQuery ? '&' : '?'}audience=$audience',
    );

    // A request GitHub answers with a new ID token each time, so the
    // client's retries never present one twice.
    final http.Response response;
    try {
      response = await _httpClient.get(
        url,
        headers: {
          'Authorization': 'bearer $_requestToken',
          'Accept': 'application/json',
        },
      );
    } on Exception catch (e) {
      throw CredentialSourceException(
        'Could not request an OIDC token from GitHub Actions: $e',
      );
    }

    // GitHub's own failure, which a job's permissions don't cause.
    if (response.statusCode >= HttpStatus.internalServerError) {
      throw CredentialSourceException(
        'GitHub Actions failed to issue an OIDC token '
        '(${response.statusCode}).',
        hint:
            "This is an error on GitHub's side. Re-run the job, or set "
            '$shorebirdTokenEnvVar to a Shorebird API key.',
      );
    }

    // A job without `permissions: id-token: write` never gets here: GitHub
    // doesn't set the request URL, so no request is made. A refusal most
    // likely means GitHub rejected the request token, such as an expired one.
    if (response.statusCode != HttpStatus.ok) {
      throw CredentialSourceException(
        'GitHub Actions refused to issue an OIDC token '
        '(${response.statusCode}).',
        hint:
            "GitHub rejected the job's ID token request, which can happen "
            'when its $actionsIdTokenRequestTokenEnvVar has expired. Re-run '
            'the job, or set $shorebirdTokenEnvVar to a Shorebird API key.',
      );
    }

    final value = _valueFrom(response.body);
    if (value == null) {
      throw const CredentialSourceException(
        'GitHub Actions sent an unexpected OIDC token response.',
      );
    }
    return value;
  }
}

String? _valueFrom(String body) {
  try {
    if (jsonDecode(body) case {
      'value': final String value,
    } when value.isNotEmpty) {
      return value;
    }
  } on FormatException {
    // Not JSON.
  }
  return null;
}
