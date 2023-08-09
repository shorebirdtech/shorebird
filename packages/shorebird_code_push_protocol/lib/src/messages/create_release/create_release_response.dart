import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'create_release_response.g.dart';

/// {@template create_release_response}
/// The response body for POST /api/v1/apps/<appId>/releases
/// {@endtemplate}
@JsonSerializable()
class CreateReleaseResponse {
  /// {@macro create_release_response}
  const CreateReleaseResponse({
    required this.release,
  });

  /// Converts a Map<String, dynamic> to a [CreateReleaseResponse]
  factory CreateReleaseResponse.fromJson(Map<String, dynamic> json) =>
      _$CreateReleaseResponseFromJson(json);

  /// Converts a [CreateReleaseResponse] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreateReleaseResponseToJson(this);

  /// The newly-created release.
  final Release release;
}
