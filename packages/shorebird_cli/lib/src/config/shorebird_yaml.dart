import 'package:json_annotation/json_annotation.dart';

part 'shorebird_yaml.g.dart';

@JsonSerializable(
  anyMap: true,
  disallowUnrecognizedKeys: true,
  createToJson: false,
)
class ShorebirdYaml {
  const ShorebirdYaml({required this.appId});

  factory ShorebirdYaml.fromJson(Map<dynamic, dynamic> json) =>
      _$ShorebirdYamlFromJson(json);

  final String appId;
}
