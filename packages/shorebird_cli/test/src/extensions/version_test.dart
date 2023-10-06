import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/extensions/version.dart';
import 'package:test/test.dart';

void main() {
  group('NonStrictParsing', () {
    group('with strict mode enabled', () {
      test('returns a version if the string is a valid semver version', () {
        expect(VersionParsing.tryParse('1.2.3'), Version(1, 2, 3));
      });

      test('returns null if string is of the format major.minor', () {
        expect(VersionParsing.tryParse('1.2'), isNull);
      });

      test('returns null if string is in an invalid format', () {
        expect(VersionParsing.tryParse('asdf'), isNull);
      });
    });

    group('without strict mode enabled', () {
      test('returns a version if the string is a valid semver version', () {
        expect(
          VersionParsing.tryParse('1.2.3', strict: false),
          Version(1, 2, 3),
        );
      });

      test('returns a version if string is of the format major.minor', () {
        expect(VersionParsing.tryParse('1.2', strict: false), Version(1, 2, 0));
      });

      test('returns null if string is in an invalid format', () {
        expect(VersionParsing.tryParse('asdf', strict: false), isNull);
      });
    });
  });
}
