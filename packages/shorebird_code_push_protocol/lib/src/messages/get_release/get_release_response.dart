import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_release_response.g.dart';

/// {@template get_release_response}
/// The response body for GET /api/v1/apps/:id/releases/:releaseId
/// {@endtemplate}
@JsonSerializable()
class GetReleaseResponse {
  /// {@macro get_release_response}
  const GetReleaseResponse({required this.release});

  /// Converts a `Map<String, dynamic>` to a [GetReleaseResponse].
  factory GetReleaseResponse.fromJson(Map<String, dynamic> json) =>
      _$GetReleaseResponseFromJson(json);

  /// Converts a [GetReleaseResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() => _$GetReleaseResponseToJson(this);

  /// The requested release.
  final Release release;
}
