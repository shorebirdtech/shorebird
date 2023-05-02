import 'package:json_annotation/json_annotation.dart';

part 'shorebird_yaml.g.dart';

/// {@template shorebird_yaml}
/// A Shorebird configuration file which contains metadata about the app.
/// {@endtemplate}
@JsonSerializable(
  anyMap: true,
  disallowUnrecognizedKeys: true,
  createToJson: false,
)
class ShorebirdYaml {
  /// {@macro shorebird_yaml}
  const ShorebirdYaml({required this.appId, this.baseUrl});

  factory ShorebirdYaml.fromJson(Map<dynamic, dynamic> json) =>
      _$ShorebirdYamlFromJson(json);

  @JsonKey(fromJson: AppId.fromJson)
  final AppId appId;
  final String? baseUrl;
}

/// {@template app_id}
/// The unique identifier for the app. Can be a single string or a map of
/// flavor names to ids for multi-flavor apps.
/// {@endtemplate}
class AppId {
  const AppId({this.value, this.values});

  factory AppId.fromJson(dynamic json) {
    if (json is String) return AppId(value: json);
    return AppId(values: (json as Map).cast<String, String>());
  }

  final String? value;
  final Map<String, String>? values;
}
