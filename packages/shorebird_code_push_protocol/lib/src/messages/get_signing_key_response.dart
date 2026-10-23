import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/signing_key.dart';

/// {@template get_signing_key_response}
/// The response body for GET /apps/{appId}/signing-key and
/// GET /apps/{appId}/releases/{releaseId}/signing-key.
/// {@endtemplate}
@immutable
class GetSigningKeyResponse {
  /// {@macro get_signing_key_response}
  const GetSigningKeyResponse({
    required this.signingKey,
  });

  /// Converts a `Map<String, dynamic>` to a [GetSigningKeyResponse].
  factory GetSigningKeyResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetSigningKeyResponse',
      json,
      () => GetSigningKeyResponse(
        signingKey: SigningKey.fromJson(
          json['signing_key'] as Map<String, dynamic>,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetSigningKeyResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetSigningKeyResponse.fromJson(json);
  }

  /// The public half of a managed patch-signing key. Its private half
  /// is held in Cloud KMS and never leaves it.
  final SigningKey signingKey;

  /// Converts a [GetSigningKeyResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'signing_key': signingKey.toJson(),
    };
  }

  @override
  int get hashCode => signingKey.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetSigningKeyResponse && signingKey == other.signingKey;
  }
}
