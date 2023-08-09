import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'record_patch_install_request.g.dart';

/// {@template record_patch_install_request}
/// Request to record a patch install.
/// {@endtemplate}
@JsonSerializable()
class RecordPatchInstallRequest {
  /// {@macro record_patch_install_request}
  RecordPatchInstallRequest({
    required this.clientId,
    required this.appId,
    required this.releaseVersion,
    required this.patchNumber,
    required this.platform,
    required this.arch,
  });

  /// Converts a Map<String, dynamic> to a [RecordPatchInstallRequest]
  factory RecordPatchInstallRequest.fromJson(Map<String, dynamic> json) =>
      _$RecordPatchInstallRequestFromJson(json);

  /// Converts a [RecordPatchInstallRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$RecordPatchInstallRequestToJson(this);

  /// The client id of the device being updated.
  final String clientId;

  /// The id of the app being updated.
  final String appId;

  /// The id of the app being updated.
  final String releaseVersion;

  /// The patch number being installed.
  final int patchNumber;

  /// The platform of the device being updated.
  final ReleasePlatform platform;

  /// The architecture of the device being updated.
  final String arch;
}
