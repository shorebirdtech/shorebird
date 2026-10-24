import 'package:shorebird_code_push_protocol/src/models/release.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/release_status.dart';

/// Application-level behavior on [Release] that does not fit in the OpenAPI
/// schema.
extension ReleaseExtensions on Release {
  /// Whether the release has been released to [platform], in any status.
  bool hasPlatform(ReleasePlatform platform) => platforms.containsKey(platform);

  /// The release's status on [platform], or null if it has not been released
  /// there.
  ReleaseStatus? statusFor(ReleasePlatform platform) =>
      platforms[platform]?.status;

  /// Whether the release is active on [platform]: its release finished, so
  /// it can be patched and previewed there.
  bool isActiveOn(ReleasePlatform platform) =>
      statusFor(platform) == ReleaseStatus.active;

  /// The platforms the release is active on.
  List<ReleasePlatform> get activePlatforms => [
    for (final MapEntry(key: platform, value: details) in platforms.entries)
      if (details.status == ReleaseStatus.active) platform,
  ];
}
