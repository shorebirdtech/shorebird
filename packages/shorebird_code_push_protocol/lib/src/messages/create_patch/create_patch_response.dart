import 'package:json_annotation/json_annotation.dart';

part 'create_patch_response.g.dart';

/// {@template create_patch_response}
/// The response body for `POST /api/v1/patches`
/// {@endtemplate}
@JsonSerializable()
class CreatePatchResponse {
  /// {@macro create_patch_response}
  const CreatePatchResponse({required this.id, required this.number});

  /// Converts a Map<String, dynamic> to a [CreatePatchResponse]
  factory CreatePatchResponse.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchResponseFromJson(json);

  /// Converts a [CreatePatchResponse] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreatePatchResponseToJson(this);

  /// The unique patch identifier.
  final int id;

  /// The patch number.
  /// A larger number equates to a newer patch.
  final int number;
}
