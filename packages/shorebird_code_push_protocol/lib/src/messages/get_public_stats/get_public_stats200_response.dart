import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/public_stat.dart';

@immutable
class GetPublicStats200Response {
  const GetPublicStats200Response({
    this.patchInstalls,
  });

  /// Converts a `Map<String, dynamic>` to a [GetPublicStats200Response].
  factory GetPublicStats200Response.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetPublicStats200Response',
      json,
      () => GetPublicStats200Response(
        patchInstalls: PublicStat.maybeFromJson(
          json['patch_installs'] as Map<String, dynamic>?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetPublicStats200Response? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetPublicStats200Response.fromJson(json);
  }

  /// The latest value of one public stat.
  final PublicStat? patchInstalls;

  /// Converts a [GetPublicStats200Response] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patch_installs': ?patchInstalls?.toJson(),
    };
  }

  @override
  int get hashCode => patchInstalls.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetPublicStats200Response &&
        patchInstalls == other.patchInstalls;
  }
}
