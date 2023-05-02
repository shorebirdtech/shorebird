import 'package:json_annotation/json_annotation.dart';

part 'shorebird_yaml.g.dart';

@JsonSerializable(
  anyMap: true,
  disallowUnrecognizedKeys: true,
  createToJson: false,
)
class ShorebirdYaml {
  const ShorebirdYaml({required this.appId, this.baseUrl});

  factory ShorebirdYaml.fromJson(Map<dynamic, dynamic> json) =>
      _$ShorebirdYamlFromJson(json);

  @JsonKey(fromJson: AppId.fromJson)
  final AppId appId;
  final String? baseUrl;
}

class AppId {
  const AppId({this.value, this.values});

  factory AppId.fromJson(dynamic json) {
    if (json is String) return AppId(value: json);
    return AppId(values: (json as Map).cast<String, String>());
  }

  final String? value;
  final Map<String, String>? values;
}
