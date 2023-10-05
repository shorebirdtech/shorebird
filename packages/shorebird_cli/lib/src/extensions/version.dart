import 'package:pub_semver/pub_semver.dart';

extension VersionParsing on Version {
  /// Attempts to parse a [versionString] into a [Version] object. If [strict]
  /// is `false`, and the [versionString] does not contain a patch number, a
  /// patch number of 0 will be added
  static Version? tryParse(String versionString, {bool strict = true}) {
    try {
      return Version.parse(versionString);
    } on FormatException {
      if (strict) {
        return null;
      }

      var updatedVersionString = versionString;
      // [Version.parse] requires a patch number. If we are not in strict mode,
      // and the version string is of the form "12.0", add a patch number of 0
      // and try again.
      final noPatchNumberRegex = RegExp(r'^\d+\.\d+$');
      if (noPatchNumberRegex.hasMatch(versionString)) {
        updatedVersionString += '.0';
      }

      try {
        return Version.parse(updatedVersionString);
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }
}
