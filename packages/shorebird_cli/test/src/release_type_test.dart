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
      expect(ReleaseType.windows.cliName, 'windows');
    });

    test('releasePlatform', () {
      expect(ReleaseType.android.releasePlatform, ReleasePlatform.android);
      expect(ReleaseType.ios.releasePlatform, ReleasePlatform.ios);
      expect(ReleaseType.iosFramework.releasePlatform, ReleasePlatform.ios);
      expect(ReleaseType.aar.releasePlatform, ReleasePlatform.android);
      expect(ReleaseType.windows.releasePlatform, ReleasePlatform.windows);
    });

    group('releaseTypes', () {
      late ArgParser parser;
      setUp(() {
        parser = ArgParser()
          ..addMultiOption(
            'platforms',
            allowed: ReleaseType.values.map((e) => e.cliName),
          );
      });

      group('when nothing is provided', () {
        test('parses and return empty', () {
          expect(parser.parse([]).releaseTypes.toList(), isEmpty);
        });
      });

      group('when the platforms argument is provided', () {
        test('parses the release types', () {
          expect(
            parser.parse(['--platforms', 'android']).releaseTypes.toList(),
            [ReleaseType.android],
          );
          expect(parser.parse(['--platforms', 'ios']).releaseTypes.toList(), [
            ReleaseType.ios,
          ]);
          expect(
            parser
                .parse(['--platforms', 'ios-framework'])
                .releaseTypes
                .toList(),
            [ReleaseType.iosFramework],
          );
          expect(parser.parse(['--platforms', 'aar']).releaseTypes.toList(), [
            ReleaseType.aar,
          ]);
        });
      });

      group('when the platform is provided as a raw arg', () {
        test('throws if the platform is invalid, listing valid platforms', () {
          expect(
            () => parser.parse(['rollback']).releaseTypes.toList(),
            throwsA(
              isA<PlatformArgumentException>().having(
                (e) => e.message,
                'message',
                '''
Invalid platform: "rollback".
Valid platforms: aar, android, ios, ios-framework, linux, macos, windows''',
              ),
            ),
          );
        });

        test('parses the release types', () {
          expect(parser.parse(['android']).releaseTypes.toList(), [
            ReleaseType.android,
          ]);
          expect(parser.parse(['ios']).releaseTypes.toList(), [
            ReleaseType.ios,
          ]);
          expect(parser.parse(['ios-framework']).releaseTypes.toList(), [
            ReleaseType.iosFramework,
          ]);
          expect(parser.parse(['aar']).releaseTypes.toList(), [
            ReleaseType.aar,
          ]);
        });

        test('accepts options before the platform', () {
          parser.addOption('release-version');
          expect(
            parser
                .parse(['--release-version=1.0.0+1', 'android'])
                .releaseTypes
                .toList(),
            [ReleaseType.android],
          );
        });

        test('ignores arguments after --', () {
          expect(
            parser
                .parse(['android', '--', '--no-pub', 'lib/main.dart'])
                .releaseTypes
                .toList(),
            [ReleaseType.android],
          );
        });

        test('throws on a second positional that looks like a version', () {
          expect(
            () => parser.parse(['android', '1.0.0+1']).releaseTypes.toList(),
            throwsA(
              isA<PlatformArgumentException>().having(
                (e) => e.message,
                'message',
                '''
Unexpected argument: "1.0.0+1".
Did you mean --release-version=1.0.0+1?''',
              ),
            ),
          );
        });

        test('throws on a second platform, suggesting --platforms', () {
          expect(
            () => parser.parse(['android', 'ios']).releaseTypes.toList(),
            throwsA(
              isA<PlatformArgumentException>().having(
                (e) => e.message,
                'message',
                '''
Unexpected argument: "ios".
Did you mean --platforms=android,ios?''',
              ),
            ),
          );
        });

        test('throws on any other second positional', () {
          expect(
            () => parser
                .parse(['android', 'lib/main.dart'])
                .releaseTypes
                .toList(),
            throwsA(
              isA<PlatformArgumentException>().having(
                (e) => e.message,
                'message',
                '''
Unexpected argument: "lib/main.dart".
Arguments for Flutter go after --.''',
              ),
            ),
          );
        });
      });

      test('PlatformArgumentException.toString is the message', () {
        expect(
          const PlatformArgumentException('nope').toString(),
          equals('nope'),
        );
      });
    });
  });
}
