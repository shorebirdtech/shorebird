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
  /// deprecated `platformStatuses` without signing. Read platforms through
  /// this rather than either field.
  List<ReleasePlatformDetails> get platformDetails =>
      platforms ??
      [
        for (final MapEntry(key: platform, value: status)
            // A server that predates `platforms` sends only the old map.
            // ignore: deprecated_member_use_from_same_package
            in (platformStatuses ?? const {}).entries)
          ReleasePlatformDetails(platform: platform, status: status),
      ];

  /// The release's status on [platform], or null if it has not been released
  /// there.
  ReleaseStatus? statusFor(ReleasePlatform platform) {
    for (final details in platformDetails) {
      if (details.platform == platform) return details.status;
    }
    return null;
  }
}
