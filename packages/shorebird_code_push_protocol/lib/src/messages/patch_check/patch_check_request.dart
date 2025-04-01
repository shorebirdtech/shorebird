import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'patch_check_request.g.dart';

/// {@template patch_check_request}
/// The request body for POST /api/v1/patches/check
/// {@endtemplate}
@JsonSerializable()
class PatchCheckRequest {
  /// {@macro patch_check_request}
  const PatchCheckRequest({
    required this.releaseVersion,
    required this.patchNumber,
    required this.patchHash,
    required this.platform,
    required this.arch,
    required this.appId,
    required this.channel,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchCheckRequest]
  factory PatchCheckRequest.fromJson(Map<String, dynamic> json) =>
      _$PatchCheckRequestFromJson(json);

  /// Converts a [PatchCheckRequest] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$PatchCheckRequestToJson(this);

  /// The release version of the app.
  final String releaseVersion;

  /// The highest patch number that the client has downloaded.
  /// If provided, the server will only return patches with a higher patch
  ///   number.
  /// If not provided, the server will provide the latest available patch.
  final int? patchNumber;

  /// The current patch hash of the app.
  final String? patchHash;

  /// The platform of the app.
  final ReleasePlatform platform;

  /// The architecture of the app.
  final String arch;

  /// The ID of the app.
  final String appId;

  /// The channel of the app.
  final String channel;
}
