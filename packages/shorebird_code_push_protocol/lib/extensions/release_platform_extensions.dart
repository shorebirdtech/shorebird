import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// Application-level behavior on [ReleasePlatform] that does not fit in
/// the OpenAPI schema.
extension ReleasePlatformExtensions on ReleasePlatform {
  /// A display name suitable for human-facing UI (e.g. `"iOS"`, `"macOS"`).
  String get displayName => switch (this) {
    ReleasePlatform.android => 'Android',
    ReleasePlatform.ios => 'iOS',
    ReleasePlatform.linux => 'Linux',
    ReleasePlatform.macos => 'macOS',
    ReleasePlatform.windows => 'Windows',
  };

  /// Whether this platform supports Flutter build flavors.
  bool get supportsFlavors => const {
    ReleasePlatform.android,
    ReleasePlatform.ios,
    ReleasePlatform.macos,
  }.contains(this);
}
