import 'package:json_annotation/json_annotation.dart';

part 'create_app_request.g.dart';

/// {@template create_app_request}
/// The request body for POST /api/v1/apps
/// {@endtemplate}
@JsonSerializable()
class CreateAppRequest {
  /// {@macro create_app_request}
  const CreateAppRequest({required this.displayName});

  /// Converts a Map<String, dynamic> to a [CreateAppRequest]
  factory CreateAppRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateAppRequestFromJson(json);

  /// Converts a [CreateAppRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreateAppRequestToJson(this);

  /// The display name of the app.
  final String displayName;
}
