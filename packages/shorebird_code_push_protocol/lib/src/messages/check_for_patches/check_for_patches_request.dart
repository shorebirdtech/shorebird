import 'package:json_annotation/json_annotation.dart';

part 'check_for_patches_request.g.dart';

/// {@template check_for_patches_request}
/// The request body for POST /api/v1/patches/check
/// {@endtemplate}
@JsonSerializable()
class CheckForPatchesRequest {
  /// {@macro check_for_patches_request}
  const CheckForPatchesRequest({
    required this.releaseVersion,
    required this.patchNumber,
    required this.patchHash,
    required this.platform,
    required this.arch,
    required this.appId,
    required this.channel,
  });

  /// Converts a Map<String, dynamic> to a [CheckForPatchesRequest]
  factory CheckForPatchesRequest.fromJson(Map<String, dynamic> json) =>
      _$CheckForPatchesRequestFromJson(json);

  /// Converts a [CheckForPatchesRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CheckForPatchesRequestToJson(this);

  /// The release version of the app.
  final String releaseVersion;

  /// The current patch number of the app.
  final int? patchNumber;

  /// The current patch hash of the app.
  final String? patchHash;

  /// The platform of the app.
  final String platform;

  /// The architecture of the app.
  final String arch;

  /// The ID of the app.
  final String appId;

  /// The channel of the app.
  final String channel;
}
