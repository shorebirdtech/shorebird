// cspell:words myapp crashpad
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/platform/windows.dart';
import 'package:test/test.dart';

void main() {
  group(Windows, () {
    late Windows windows;

    setUp(() {
      windows = Windows();
    });

    group('findExecutable', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync();
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      group('when no .exe files exist', () {
        test('throws an exception', () {
          expect(
            () => windows.findExecutable(
              releaseDirectory: tempDir,
              projectName: 'myapp',
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                startsWith('Exception: No executables found in'),
              ),
            ),
          );
        });
      });

      group('when an exe with the same name as the project exists', () {
        test('returns that exe', () {
          final app = File(p.join(tempDir.path, 'myapp.exe'))..createSync();
          final crashpad = File(p.join(tempDir.path, 'crashpad_handler.exe'))
            ..createSync();

          final selected = windows.findExecutable(
            releaseDirectory: tempDir,
            projectName: 'myapp',
          );
          expect(selected.path, equals(app.path));
          expect(crashpad.existsSync(), isTrue);
        });
      });

      group('when no exact match is found', () {
        test('returns most recently modified exe', () {
          final app = File(p.join(tempDir.path, 'runner.exe'))..createSync();
          final otherExe = File(p.join(tempDir.path, 'cool_game.exe'))
            ..createSync()
            ..setLastModifiedSync(
              DateTime.now().subtract(const Duration(seconds: 1)),
            );

          final selected = windows.findExecutable(
            releaseDirectory: tempDir,
            projectName: 'some project',
          );
          expect(selected.path, equals(app.path));
          expect(otherExe.existsSync(), isTrue);
        });
      });
    });
  });
}
