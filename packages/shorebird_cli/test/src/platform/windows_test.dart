// cspell:words myapp crashpad
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/platform/windows.dart';
import 'package:test/test.dart';

void main() {
  R runWithOverrides<R>(R Function() body) {
    return runScoped(
      body,
      values: {windowsRef.overrideWith(Windows.new)},
    );
  }

  group(Windows, () {
    group('findExecutable', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync();
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('throws when no .exe files exist', () {
        expect(
          () => runWithOverrides(
            () => windows.findExecutable(
              releaseDirectory: tempDir,
              projectName: 'myapp',
            ),
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('returns exact match when found', () {
        final app = File(p.join(tempDir.path, 'myapp.exe'))..createSync();
        final crashpad = File(p.join(tempDir.path, 'crashpad_handler.exe'))
          ..createSync();

        final selected = runWithOverrides(
          () => windows.findExecutable(
            releaseDirectory: tempDir,
            projectName: 'myapp',
          ),
        );
        expect(selected.path, equals(app.path));
        expect(crashpad.existsSync(), isTrue);
      });

      test('returns most recently modified if exact match is not found', () {
        final other = File(p.join(tempDir.path, 'runner.exe'))..createSync();
        final app = File(p.join(tempDir.path, 'cool_game.exe'))..createSync();

        final selected = runWithOverrides(
          () => windows.findExecutable(
            releaseDirectory: tempDir,
            projectName: 'cool',
          ),
        );
        expect(selected.path, equals(app.path));
        expect(other.existsSync(), isTrue);
      });
    });
  });
}
