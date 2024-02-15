/// Exception thrown when authentication fails.
class AuthenticationException implements Exception {
  final String error;

  /// Human-readable ASCII text providing additional information, used to assist
  /// the client developer in understanding the error that occurred.
  final String? errorDescription;

  /// A URI identifying a human-readable web page with information about the
  /// error, used to provide the client developer with additional information
  /// about the error.
  final String? errorUri;

  AuthenticationException(
    this.error, {
    this.errorDescription,
    this.errorUri,
  });

  @override
  String toString() => 'AuthenticationException: $error';
}
