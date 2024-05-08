import 'package:args/args.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

void main() {
  group(ReleaseType, () {
    test('cliName', () {
      expect(ReleaseType.android.cliName, 'android');
      expect(ReleaseType.ios.cliName, 'ios');
      expect(ReleaseType.iosFramework.cliName, 'ios-framework');
      expect(ReleaseType.aar.cliName, 'aar');
    });

    test('releasePlatform', () {
      expect(ReleaseType.android.releasePlatform, ReleasePlatform.android);
      expect(ReleaseType.ios.releasePlatform, ReleasePlatform.ios);
      expect(ReleaseType.iosFramework.releasePlatform, ReleasePlatform.ios);
      expect(ReleaseType.aar.releasePlatform, ReleasePlatform.android);
    });

    group('releaseTypes', () {
      late ArgParser parser;
      setUp(() {
        parser = ArgParser()
          ..addMultiOption(
            'platform',
            allowed: ReleaseType.values.map((e) => e.cliName),
          );
      });

      group('when the platform argument is provided', () {
        test('parses the release types', () {
          expect(
            parser.parse(['--platform', 'android']).releaseTypes.toList(),
            [ReleaseType.android],
          );
          expect(
            parser.parse(['--platform', 'ios']).releaseTypes.toList(),
            [ReleaseType.ios],
          );
          expect(
            parser.parse(['--platform', 'ios-framework']).releaseTypes.toList(),
            [ReleaseType.iosFramework],
          );
          expect(
            parser.parse(['--platform', 'aar']).releaseTypes.toList(),
            [ReleaseType.aar],
          );
        });

        group('when the platform is provided as a raw arg', () {
          test('throws an ArgumentError if the platform is invalid', () {
            expect(
              () => parser.parse(['foo']).releaseTypes.toList(),
              throwsArgumentError,
            );
          });

          test('parses the release types', () {
            expect(
              parser.parse(['android', 'foo']).releaseTypes.toList(),
              [ReleaseType.android],
            );
            expect(
              parser.parse(['ios', 'foo']).releaseTypes.toList(),
              [ReleaseType.ios],
            );
            expect(
              parser.parse(['ios-framework', 'foo']).releaseTypes.toList(),
              [ReleaseType.iosFramework],
            );
            expect(
              parser.parse(['aar', 'foo']).releaseTypes.toList(),
              [ReleaseType.aar],
            );
          });
        });
      });
    });
  });
}
