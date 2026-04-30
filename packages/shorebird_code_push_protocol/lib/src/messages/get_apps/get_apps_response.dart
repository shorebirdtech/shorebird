// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/app_metadata.dart';

/// {@template get_apps_response}
/// The response body for GET /apps.
/// {@endtemplate}
@immutable
class GetAppsResponse {
  /// {@macro get_apps_response}
  const GetAppsResponse({
    required this.apps,
  });

  /// Converts a `Map<String, dynamic>` to a [GetAppsResponse].
  factory GetAppsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetAppsResponse',
      json,
      () => GetAppsResponse(
        apps: (json['apps'] as List)
            .map<AppMetadata>(
              (e) => AppMetadata.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetAppsResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetAppsResponse.fromJson(json);
  }

  /// The list of apps.
  final List<AppMetadata> apps;

  /// Converts a [GetAppsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'apps': apps.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(apps).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetAppsResponse && listsEqual(apps, other.apps);
  }
}
