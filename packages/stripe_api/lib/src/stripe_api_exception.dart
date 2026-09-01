import 'dart:convert';

import 'package:http/http.dart' as http;

/// {@template stripe_api_exception}
/// An exception thrown when a request to the Stripe API returns a non-success
/// response.
///
/// Carries the HTTP [statusCode] of the failed response so callers can
/// distinguish, for example, a missing resource (`404`) from rate limiting
/// (`429`). When the response body is a Stripe error object, the
/// machine-readable [code] (e.g. `resource_missing`, `rate_limit`) is also
/// surfaced.
///
/// See https://docs.stripe.com/api/errors.
/// {@endtemplate}
class StripeApiException implements Exception {
  /// {@macro stripe_api_exception}
  StripeApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  /// Builds a [StripeApiException] from a failed [response].
  ///
  /// [message] is a human-readable description supplied by the caller and is
  /// preserved verbatim. The Stripe error [code] is parsed from the response
  /// body when it is a JSON error object.
  ///
  /// Never throws: a non-JSON or unexpected body (e.g. an HTML gateway error)
  /// simply leaves [code] null.
  factory StripeApiException.fromResponse(
    http.Response response, {
    required String message,
  }) {
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['code'] is String) {
          code = error['code'] as String;
        }
      }
    } on Object catch (_) {
      // Non-JSON or unexpected body; the status code is still meaningful.
    }
    return StripeApiException(
      statusCode: response.statusCode,
      message: message,
      code: code,
    );
  }

  /// The HTTP status code of the failed response.
  final int statusCode;

  /// The Stripe machine-readable error code (e.g. `resource_missing`), when the
  /// response body was a Stripe error object; otherwise null.
  final String? code;

  /// A human-readable description of the failure.
  final String message;

  @override
  String toString() =>
      'StripeApiException($statusCode${code == null ? '' : ', $code'}): '
      '$message';
}
