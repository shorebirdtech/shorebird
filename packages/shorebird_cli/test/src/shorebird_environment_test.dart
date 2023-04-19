import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:test/test.dart';

class _MockPlatform extends Mock implements Platform {}

void main() {
  group('ShorebirdEnvironment', () {
    late Platform platform;
    late Directory shorebirdRoot;
    late Uri platformScript;

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      platformScript = Uri.file(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'shorebird.snapshot'),
      );
      platform = _MockPlatform();
      ShorebirdEnvironment.platform = platform;

      when(() => platform.script).thenReturn(platformScript);
    });

    group('flutterRevision', () {
      test('returns correct revision', () {
        const revision = 'test-revision';
        File(p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);
        expect(ShorebirdEnvironment.flutterRevision, equals(revision));
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
        expect(ShorebirdEnvironment.shorebirdEngineRevision, equals(revision));
      });
    });
  });
}
