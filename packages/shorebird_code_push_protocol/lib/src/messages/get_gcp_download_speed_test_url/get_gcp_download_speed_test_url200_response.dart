// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template get_gcp_download_speed_test_url200_response}
/// The download URL to measure against.
/// {@endtemplate}
@immutable
class GetGcpDownloadSpeedTestUrl200Response {
  /// {@macro get_gcp_download_speed_test_url200_response}
  const GetGcpDownloadSpeedTestUrl200Response({
    required this.downloadUrl,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [GetGcpDownloadSpeedTestUrl200Response].
  factory GetGcpDownloadSpeedTestUrl200Response.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'GetGcpDownloadSpeedTestUrl200Response',
      json,
      () => GetGcpDownloadSpeedTestUrl200Response(
        downloadUrl: json['download_url'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetGcpDownloadSpeedTestUrl200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetGcpDownloadSpeedTestUrl200Response.fromJson(json);
  }

  /// The GCP-signed download URL.
  final String downloadUrl;

  /// Converts a [GetGcpDownloadSpeedTestUrl200Response]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'download_url': downloadUrl,
    };
  }

  @override
  int get hashCode => downloadUrl.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetGcpDownloadSpeedTestUrl200Response &&
        downloadUrl == other.downloadUrl;
  }
}
