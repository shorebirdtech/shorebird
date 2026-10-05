import 'package:equatable/equatable.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The `--scope` spelling of an [ApiKeyScope].
///
/// Command-line spelling is a CLI concern, so it lives here rather than on
/// the protocol enum, which carries only the wire value.
extension ApiKeyScopeFlagName on ApiKeyScope {
  /// The value accepted by `--scope` on the command line.
  String get flagName => switch (this) {
    ApiKeyScope.fullAccess => 'full-access',
    ApiKeyScope.releaseAndPatch => 'release-and-patch',
  };
}

/// {@template api_key_metadata}
/// The non-secret half of an API key: everything the auth service will tell
/// you about a key after it has been created.
///
/// The key itself is returned exactly once, at creation, and is never
/// retrievable afterwards — hence "metadata".
/// {@endtemplate}
class ApiKeyMetadata extends Equatable {
  /// {@macro api_key_metadata}
  const ApiKeyMetadata({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.scope,
  });

  /// Parses an [ApiKeyMetadata] from the auth service's JSON representation.
  factory ApiKeyMetadata.fromJson(Map<String, dynamic> json) {
    final scope = json['scope'];
    return ApiKeyMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastUsedAt: _parseNullableDate(json['last_used_at']),
      expiresAt: _parseNullableDate(json['expires_at']),
      scope: scope is String ? ApiKeyScope.fromWireName(scope) : null,
    );
  }

  /// The key's server-side identifier, used to revoke it.
  final String id;

  /// The name the key was created with.
  final String name;

  /// When the key was created.
  final DateTime createdAt;

  /// When the key was last used to authenticate, or null if never used.
  final DateTime? lastUsedAt;

  /// When the key expires, or null if it never does.
  final DateTime? expiresAt;

  /// The preset this key's permissions correspond to.
  ///
  /// Null when the server reports no scope, or one this CLI does not know:
  /// a key whose permissions match no preset, or a preset added server-side
  /// since this CLI shipped. Displayed as "unknown" rather than guessed.
  final ApiKeyScope? scope;

  @override
  List<Object?> get props => [
    id,
    name,
    createdAt,
    lastUsedAt,
    expiresAt,
    scope,
  ];
}

DateTime? _parseNullableDate(Object? value) =>
    value is String ? DateTime.parse(value) : null;

/// {@template api_key_request_exception}
/// Thrown when the auth service rejects or cannot serve an API key request.
/// {@endtemplate}
class ApiKeyRequestException implements Exception {
  /// {@macro api_key_request_exception}
  const ApiKeyRequestException(this.message);

  /// A description of what went wrong, suitable for showing to the user.
  final String message;

  @override
  String toString() => message;
}

/// {@template api_key_session_required_exception}
/// Thrown when API key management is attempted without an interactive
/// session.
///
/// Key management authenticates with the session's refresh token, which only
/// `shorebird login` produces. A `SHOREBIRD_TOKEN` — whether an API key or a
/// legacy CI token — is not a session and cannot manage keys. That is
/// deliberate: a leaked CI credential able to mint more credentials would
/// defeat revocation.
/// {@endtemplate}
class ApiKeySessionRequiredException implements Exception {
  /// {@macro api_key_session_required_exception}
  const ApiKeySessionRequiredException();

  @override
  String toString() =>
      'API key management requires an interactive login. Run `shorebird '
      'login` on a machine with a browser.';
}

/// {@template api_key_scope_mismatch_exception}
/// Thrown when the server minted a key with a different scope than requested.
///
/// The failure this guards against is a silent widening: a server that does
/// not understand scope-by-name ignores the field and defaults to full
/// access, handing back a broader credential than the caller asked for.
/// {@endtemplate}
class ApiKeyScopeMismatchException implements Exception {
  /// {@macro api_key_scope_mismatch_exception}
  const ApiKeyScopeMismatchException({
    required this.requested,
    required this.granted,
  });

  /// The scope the caller asked for.
  final ApiKeyScope requested;

  /// The scope the server actually granted, or null if it reported none.
  final ApiKeyScope? granted;

  @override
  String toString() =>
      'Requested a ${requested.flagName} key but the server granted '
      '${granted?.flagName ?? 'an unknown scope'}. The key was created — '
      'revoke it with `shorebird account api-keys revoke`.';
}
