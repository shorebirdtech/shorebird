import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_apps_response.g.dart';

/// {@template get_apps_response}
/// The response body for GET /api/v1/apps
/// {@endtemplate}
@JsonSerializable()
class GetAppsResponse {
  /// {@macro get_apps_response}
  const GetAppsResponse({required this.apps});

  /// Converts a Map<String, dynamic> to a [GetAppsResponse].
  factory GetAppsResponse.fromJson(Map<String, dynamic> json) =>
      _$GetAppsResponseFromJson(json);

  /// Converts a [GetAppsResponse] to a Map<String, dynamic>.
  Json toJson() => _$GetAppsResponseToJson(this);

  /// The list of apps.
  final List<AppMetadata> apps;
}
