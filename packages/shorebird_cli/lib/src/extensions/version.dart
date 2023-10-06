import 'package:pub_semver/pub_semver.dart';

extension VersionParsing on Version {
  /// Attempts to parse a [versionString] into a [Version] object. If [strict]
  /// is `false`, and the [versionString] does not contain a patch number, a
  /// patch number of 0 will be added
  static Version? tryParse(String versionString, {bool strict = true}) {
    try {
      return Version.parse(versionString);
    } on FormatException {
      final noPatchNumberRegex = RegExp(r'^\d+\.\d+$');
      if (strict || !noPatchNumberRegex.hasMatch(versionString)) {
        return null;
      }

      // [Version.parse] requires a patch number. If we are not in strict mode,
      // and the version string is of the form "12.0", add a patch number of 0
      // and try again.
      try {
        return Version.parse('$versionString.0');
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }
}
