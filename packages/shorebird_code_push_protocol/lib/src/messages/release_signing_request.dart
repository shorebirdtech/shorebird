import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_signing_mode.dart';

/// {@template release_signing_request}
/// How the CLI signed a release's binaries. A managed release names the
/// key GET /apps/{appId}/signing-key returned (key_id). A customer
/// release sends its public key (public_key_pem), which the server
/// stores; never anything private. An unsigned release sends neither.
/// {@endtemplate}
@immutable
class ReleaseSigningRequest {
  /// {@macro release_signing_request}
  const ReleaseSigningRequest({
    required this.mode,
    this.keyId,
    this.publicKeyPem,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleaseSigningRequest].
  factory ReleaseSigningRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleaseSigningRequest',
      json,
      () => ReleaseSigningRequest(
        mode: ReleaseSigningMode.fromJson(json['mode'] as String),
        keyId: json['key_id'] as int?,
        publicKeyPem: json['public_key_pem'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleaseSigningRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleaseSigningRequest.fromJson(json);
  }

  /// How a release's binaries were signed for patch signing.
  final ReleaseSigningMode mode;

  /// The managed key the CLI embedded. Required when mode is managed,
  /// and refused otherwise.
  final int? keyId;

  /// The customer's public key the CLI embedded, PEM encoded
  /// (SubjectPublicKeyInfo). Required when mode is customer, and
  /// refused otherwise.
  final String? publicKeyPem;

  /// Converts a [ReleaseSigningRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.toJson(),
      'key_id': ?keyId,
      'public_key_pem': ?publicKeyPem,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    mode,
    keyId,
    publicKeyPem,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReleaseSigningRequest &&
        mode == other.mode &&
        keyId == other.keyId &&
        publicKeyPem == other.publicKeyPem;
  }
}
