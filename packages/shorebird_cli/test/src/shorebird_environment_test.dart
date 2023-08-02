import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

class _MockPlatform extends Mock implements Platform {}

void main() {
  group('shorebirdEnv', () {
    late Platform platform;
    late Directory shorebirdRoot;
    late Uri platformScript;
    late ShorebirdEnv shorebirdEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
        },
      );
    }

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      platformScript = Uri.file(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'shorebird.snapshot'),
      );
      platform = _MockPlatform();
      shorebirdEnv = runWithOverrides(ShorebirdEnv.new);

      when(() => platform.environment).thenReturn(const {});
      when(() => platform.script).thenReturn(platformScript);
    });

    group('flutterRevision', () {
      test('returns correct revision', () {
        const revision = 'test-revision';
        File(p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);
        expect(
          runWithOverrides(() => shorebirdEnv.flutterRevision),
          equals(revision),
        );
      });

      test('trims revision file content', () {
        const revision = '''

test-revision

\r\n
''';
        File(p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);

        expect(
          runWithOverrides(() => shorebirdEnv.flutterRevision),
          'test-revision',
        );
      });
    });

    group('shorebirdEngineRevision', () {
      test('returns correct revision', () {
        const revision = 'test-revision';
        File(
          p.join(
            shorebirdRoot.path,
            'bin',
            'cache',
            'flutter',
            'bin',
            'internal',
            'engine.version',
          ),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);
        expect(
          runWithOverrides(() => shorebirdEnv.shorebirdEngineRevision),
          equals(revision),
        );
      });
    });

    group('hostedUrl', () {
      test('returns hosted url from env if available', () {
        when(() => platform.environment).thenReturn({
          'SHOREBIRD_HOSTED_URL': 'https://example.com',
        });
        expect(
          runWithOverrides(() => shorebirdEnv.hostedUri),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('falls back to shorebird.yaml', () {
        final directory = Directory.systemTemp.createTempSync();
        File(p.join(directory.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: test-id
base_url: https://example.com''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.hostedUri),
            getCurrentDirectory: () => directory,
          ),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('returns null when there is no env override or shorebird.yaml', () {
        expect(runWithOverrides(() => shorebirdEnv.hostedUri), isNull);
      });
    });
  });
}
