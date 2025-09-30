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
      values: {
        windowsRef.overrideWith(Windows.new),
      },
    );
  }

  group('Windows', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('throws when no .exe files exist', () {
      expect(
        () => runWithOverrides(() => windows.windowsAppExe(tempDir)),
        throwsA(isA<Exception>()),
      );
    });

    test('prefers exact match with projectName', () {
      final crashpad = File(p.join(tempDir.path, 'crashpad_handler.exe'))
        ..createSync();
      final app = File(p.join(tempDir.path, 'myapp.exe'))..createSync();

      final selected = runWithOverrides(
        () => windows.windowsAppExe(tempDir, projectName: 'myapp'),
      );
      expect(selected.path, equals(app.path));

      // Ensure another executable exists but is not chosen due to projectName.
      expect(crashpad.existsSync(), isTrue);
    });

    test('prefers contains match when exact not present', () {
      final app = File(p.join(tempDir.path, 'cool_game.exe'))..createSync();
      final other = File(p.join(tempDir.path, 'runner.exe'))..createSync();

      final selected = runWithOverrides(
        () => windows.windowsAppExe(tempDir, projectName: 'cool'),
      );
      expect(selected.path, equals(app.path));
      expect(other.existsSync(), isTrue);
    });

    test('returns first exe when projectName is null', () {
      final a = File(p.join(tempDir.path, 'a.exe'))..createSync();
      final b = File(p.join(tempDir.path, 'b.exe'))..createSync();

      final selected = runWithOverrides(() => windows.windowsAppExe(tempDir));
      // No projectName provided, returns first exe without matching logic.
      expect(selected.path == a.path || selected.path == b.path, isTrue);
    });

    test('falls back when only these exes are present', () {
      final cp1 = File(p.join(tempDir.path, 'crashpad_handler.exe'))
        ..createSync();
      final cp2 = File(p.join(tempDir.path, 'crashpad_wer.exe'))..createSync();

      final selected = runScoped(
        () => windows.windowsAppExe(tempDir),
        values: {windowsRef.overrideWith(Windows.new)},
      );
      // When only these executables exist, returns one of them (fallback).
      expect(
        selected.path == cp1.path || selected.path == cp2.path,
        isTrue,
      );
    });

    test('falls back to first exe when projectName does not match', () {
      final crashpad = File(p.join(tempDir.path, 'crashpad_handler.exe'))
        ..createSync();
      final runner = File(p.join(tempDir.path, 'runner.exe'))..createSync();

      final selected = runWithOverrides(
        () => windows.windowsAppExe(tempDir, projectName: 'myapp'),
      );
      // projectName provided but no exe matches, falls back to first exe.
      expect(
        selected.path == crashpad.path || selected.path == runner.path,
        isTrue,
      );
    });
  });
}
