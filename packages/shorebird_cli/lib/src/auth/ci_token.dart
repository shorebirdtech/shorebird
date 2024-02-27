import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

part 'ci_token.g.dart';

/// {@template ci_token}
/// A CI token.
/// {@endtemplate}
@JsonSerializable()
class CiToken {
  /// {@macro ci_token}
  const CiToken({required this.refreshToken, required this.authProvider});

  /// Creates a [CiToken] from a base64 encoded string.
  factory CiToken.fromBase64(String base64) {
    return CiToken.fromJson(
      jsonDecode(utf8.decode(base64Decode(base64))) as Map<String, dynamic>,
    );
  }

  /// Encodes the [CiToken] to a base64 string.
  String toBase64() => base64Encode(utf8.encode(jsonEncode(toJson())));

  /// Creates a [CiToken] from a JSON object.
  static CiToken fromJson(Map<String, dynamic> json) => _$CiTokenFromJson(json);

  /// Converts the [CiToken] to a JSON object.
  Map<String, dynamic> toJson() => _$CiTokenToJson(this);

  /// The token used to obtain a JWT.
  final String refreshToken;

  /// The authentication provider used to obtain the token.
  final AuthProvider authProvider;
}
