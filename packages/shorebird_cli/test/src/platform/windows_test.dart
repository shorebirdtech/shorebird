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
      const projectName = 'my_app';
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync();
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      group('when no executables exist', () {
        test('throws an exception', () {
          expect(
            () => runWithOverrides(
              () => windows.findExecutable(
                releaseDirectory: tempDir,
                projectName: projectName,
              ),
            ),
            throwsA(isA<Exception>()),
          );
        });
      });

      group('when an exact match exists', () {
        late File app;

        setUp(() {
          app = File(p.join(tempDir.path, '$projectName.exe'))..createSync();
          File(p.join(tempDir.path, 'other.exe')).createSync();
        });

        test('returns it', () {
          final executable = runWithOverrides(
            () => windows.findExecutable(
              releaseDirectory: tempDir,
              projectName: projectName,
            ),
          );
          expect(executable.path, equals(app.path));
        });
      });

      group('when an exact match does not exist', () {
        late File app;

        setUp(() async {
          File(p.join(tempDir.path, 'other.exe')).createSync();
          // Ensure my_app is created after other.
          await Future<void>.delayed(const Duration(seconds: 1));
          app = File(p.join(tempDir.path, '$projectName.exe'))..createSync();
        });

        test('returns most recently modified executable', () {
          final selected = runWithOverrides(
            () => windows.findExecutable(
              releaseDirectory: tempDir,
              projectName: 'runner',
            ),
          );
          expect(selected.path, equals(app.path));
        });
      });
    });
  });
}
