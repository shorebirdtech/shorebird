import 'package:json_annotation/json_annotation.dart';

part 'create_patch_install_request.g.dart';

/// {@template create_patch_install_request}
/// Request to create a patch install.
/// {@endtemplate}
@JsonSerializable()
class CreatePatchInstallRequest {
  /// {@macro create_patch_install_request}
  CreatePatchInstallRequest({required this.clientId});

  /// Converts a Map<String, dynamic> to a [CreatePatchInstallRequest]
  factory CreatePatchInstallRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchInstallRequestFromJson(json);

  /// Converts a [CreatePatchInstallRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreatePatchInstallRequestToJson(this);

  /// The client id of the device being updated.
  final String clientId;
}
