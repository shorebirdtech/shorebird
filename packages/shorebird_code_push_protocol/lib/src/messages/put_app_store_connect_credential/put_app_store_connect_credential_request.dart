import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/api_exception.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

@immutable
class PutAppStoreConnectCredentialRequest {
  PutAppStoreConnectCredentialRequest({
    required this.issuerId,
    required this.keyId,
    required this.privateKey,
  }) {
    keyId.validate(pattern: r'^[A-Z0-9]{10}$');
    privateKey.validate(maxLength: 4096);
  }

  /// Converts a `Map<String, dynamic>` to a
  /// [PutAppStoreConnectCredentialRequest].
  factory PutAppStoreConnectCredentialRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'PutAppStoreConnectCredentialRequest',
      json,
      () => PutAppStoreConnectCredentialRequest(
        issuerId: json['issuer_id'] as String,
        keyId: json['key_id'] as String,
        privateKey: json['private_key'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PutAppStoreConnectCredentialRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return PutAppStoreConnectCredentialRequest.fromJson(json);
  }

  /// The issuer id App Store Connect shows above its team keys.
  final String issuerId;

  /// The key id App Store Connect shows beside the key.
  final String keyId;

  /// The contents of the `.p8` file App Store Connect downloaded: a
  /// PEM P-256 private key beginning `-----BEGIN PRIVATE KEY-----`.
  final String privateKey;

  /// Converts a [PutAppStoreConnectCredentialRequest]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'issuer_id': issuerId,
      'key_id': keyId,
      'private_key': privateKey,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    issuerId,
    keyId,
    privateKey,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PutAppStoreConnectCredentialRequest &&
        issuerId == other.issuerId &&
        keyId == other.keyId &&
        privateKey == other.privateKey;
  }
}
