import 'package:shorebird_code_push_protocol/src/models/release.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform_details.dart';
import 'package:shorebird_code_push_protocol/src/models/release_status.dart';

/// Application-level behavior on [Release] that does not fit in the OpenAPI
/// schema.
extension ReleaseExtensions on Release {
  /// The release on each platform it has been released to.
  ///
  /// This is [Release.platforms], or, from a server that predates it, the
  /// deprecated `platformStatuses` without signing. Read a release's
  /// platforms through this rather than either field.
  Map<ReleasePlatform, ReleasePlatformDetails> get platformDetails =>
      platforms ??
      // A server that predates `platforms` sends only the old map.
      // ignore: deprecated_member_use_from_same_package
      (platformStatuses ?? const {}).map(
        (platform, status) =>
            MapEntry(platform, ReleasePlatformDetails(status: status)),
      );

  /// Whether the release has been released to [platform], in any status.
  bool hasPlatform(ReleasePlatform platform) =>
      platformDetails.containsKey(platform);

  /// The release's status on [platform], or null if it has not been released
  /// there.
  ReleaseStatus? statusFor(ReleasePlatform platform) =>
      platformDetails[platform]?.status;

  /// Whether the release is active on [platform]: its release finished, so
  /// it can be patched and previewed there.
  bool isActiveOn(ReleasePlatform platform) =>
      statusFor(platform) == ReleaseStatus.active;

  /// The platforms the release is active on.
  List<ReleasePlatform> get activePlatforms => [
    for (final MapEntry(key: platform, value: details)
        in platformDetails.entries)
      if (details.status == ReleaseStatus.active) platform,
  ];
}
