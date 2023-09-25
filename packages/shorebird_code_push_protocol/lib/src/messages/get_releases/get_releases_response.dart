import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_releases_response.g.dart';

/// {@template get_releases_response}
/// The response body for GET /api/v1/apps/:id/releases
/// {@endtemplate}
@JsonSerializable()
class GetReleasesResponse {
  /// {@macro get_releases_response}
  const GetReleasesResponse({required this.releases});

  /// Converts a Map<String, dynamic> to a [GetReleasesResponse].
  factory GetReleasesResponse.fromJson(Map<String, dynamic> json) =>
      _$GetReleasesResponseFromJson(json);

  /// Converts a [GetReleasesResponse] to a Map<String, dynamic>.
  Json toJson() => _$GetReleasesResponseToJson(this);

  /// The list of releases for the app.
  final List<Release> releases;
}
