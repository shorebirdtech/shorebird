import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template get_gcp_upload_speed_test_url200_response}
/// The upload URL to measure against.
/// {@endtemplate}
@immutable
class GetGcpUploadSpeedTestUrl200Response {
  /// {@macro get_gcp_upload_speed_test_url200_response}
  const GetGcpUploadSpeedTestUrl200Response({
    required this.uploadUrl,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [GetGcpUploadSpeedTestUrl200Response].
  factory GetGcpUploadSpeedTestUrl200Response.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'GetGcpUploadSpeedTestUrl200Response',
      json,
      () => GetGcpUploadSpeedTestUrl200Response(
        uploadUrl: json['upload_url'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetGcpUploadSpeedTestUrl200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetGcpUploadSpeedTestUrl200Response.fromJson(json);
  }

  /// The GCP-signed upload URL.
  final String uploadUrl;

  /// Converts a [GetGcpUploadSpeedTestUrl200Response]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'upload_url': uploadUrl,
    };
  }

  @override
  int get hashCode => uploadUrl.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetGcpUploadSpeedTestUrl200Response &&
        uploadUrl == other.uploadUrl;
  }
}
