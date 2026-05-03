import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template patch_check_request}
/// The request body for POST /patches/check.
/// {@endtemplate}
@immutable
class PatchCheckRequest {
  /// {@macro patch_check_request}
  const PatchCheckRequest({
    required this.releaseVersion,
    required this.platform,
    required this.arch,
    required this.appId,
    required this.channel,
    this.patchNumber,
    this.patchHash,
    this.clientId,
    this.currentPatchNumber,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchCheckRequest].
  factory PatchCheckRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchCheckRequest',
      json,
      () => PatchCheckRequest(
        releaseVersion: json['release_version'] as String,
        patchNumber: json['patch_number'] as int?,
        patchHash: json['patch_hash'] as String?,
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        arch: json['arch'] as String,
        appId: json['app_id'] as String,
        channel: json['channel'] as String,
        clientId: json['client_id'] as String?,
        currentPatchNumber: json['current_patch_number'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchCheckRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchCheckRequest.fromJson(json);
  }

  /// The release version of the app.
  final String releaseVersion;

  /// The highest patch number the client has already downloaded.
  /// If provided, the server only returns patches with a higher
  /// number. If omitted, the server returns the latest available.
  final int? patchNumber;

  /// The current patch hash of the app.
  final String? patchHash;

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform platform;

  /// The architecture of the app.
  final String arch;

  /// The ID of the app.
  final String appId;

  /// The channel of the app.
  final String channel;

  /// Unique device ID for the install, generated on device and
  /// unique per app. Optional for backward compatibility.
  final String? clientId;

  /// The number of the patch currently running on the device, if any.
  ///
  /// Supersedes [patchNumber] for newer updater clients. Unlike
  /// [patchNumber], this does not affect the server's response;
  /// [patchNumber] is retained for compatibility with legacy clients that
  /// rely on the server's short-circuit path.
  final int? currentPatchNumber;

  /// Converts a [PatchCheckRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'release_version': releaseVersion,
      'patch_number': patchNumber,
      'patch_hash': patchHash,
      'platform': platform.toJson(),
      'arch': arch,
      'app_id': appId,
      'channel': channel,
      'client_id': clientId,
      'current_patch_number': currentPatchNumber,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    releaseVersion,
    patchNumber,
    patchHash,
    platform,
    arch,
    appId,
    channel,
    clientId,
    currentPatchNumber,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchCheckRequest &&
        releaseVersion == other.releaseVersion &&
        patchNumber == other.patchNumber &&
        patchHash == other.patchHash &&
        platform == other.platform &&
        arch == other.arch &&
        appId == other.appId &&
        channel == other.channel &&
        clientId == other.clientId &&
        currentPatchNumber == other.currentPatchNumber;
  }
}
