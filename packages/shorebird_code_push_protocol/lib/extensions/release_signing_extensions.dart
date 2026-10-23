import 'package:shorebird_code_push_protocol/src/models/release_signing.dart';
import 'package:shorebird_code_push_protocol/src/models/release_signing_mode.dart';

/// Application-level behavior on [ReleaseSigning] that does not fit in the
/// OpenAPI schema.
extension ReleaseSigningExtensions on ReleaseSigning {
  /// [mode] as a [ReleaseSigningMode], or null when it is a mode this client
  /// doesn't know. The schema sends the mode as a string so that a mode
  /// added later reads as unknown here instead of failing the whole
  /// release's parse.
  ReleaseSigningMode? get signingMode {
    for (final value in ReleaseSigningMode.values) {
      if (value.value == mode) return value;
    }
    return null;
  }
}
