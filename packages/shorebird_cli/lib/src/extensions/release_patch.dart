import 'package:collection/collection.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Reads a [ReleasePatch]'s platform from servers old and new.
extension ReleasePatchPlatform on ReleasePatch {
  /// The platform the patch was built for: [ReleasePatch.platform], or for
  /// a patch created before the server recorded it, its artifacts' platform.
  /// Null when neither says.
  ReleasePlatform? get resolvedPlatform =>
      platform ?? artifacts.firstOrNull?.platform;
}
