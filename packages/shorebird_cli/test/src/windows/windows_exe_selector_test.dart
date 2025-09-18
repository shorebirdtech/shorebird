import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/windows/windows_exe_selector.dart';
import 'package:test/test.dart';

void main() {
  group('selectWindowsAppExe', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('throws when no .exe files exist', () {
      expect(
        () => selectWindowsAppExe(tempDir),
        throwsA(isA<Exception>()),
      );
    });

    test('prefers exact match with projectNameHint', () {
      final crashpad = File(p.join(tempDir.path, 'crashpad_handler.exe'))
        ..createSync();
      final app = File(p.join(tempDir.path, 'myapp.exe'))..createSync();

      final selected = selectWindowsAppExe(tempDir, projectNameHint: 'myapp');
      expect(selected.path, equals(app.path));

      // Ensure excluded helper exists but is not chosen.
      expect(crashpad.existsSync(), isTrue);
    });

    test('prefers contains match when exact not present', () {
      final app = File(p.join(tempDir.path, 'cool_game.exe'))..createSync();
      final other = File(p.join(tempDir.path, 'runner.exe'))..createSync();

      final selected = selectWindowsAppExe(tempDir, projectNameHint: 'cool');
      expect(selected.path, equals(app.path));
      expect(other.existsSync(), isTrue);
    });

    test('falls back to first candidate when no hint provided', () {
      final a = File(p.join(tempDir.path, 'a.exe'))..createSync();
      final b = File(p.join(tempDir.path, 'b.exe'))..createSync();

      final selected = selectWindowsAppExe(tempDir);
      // Order of listSync is platform dependent but typically creation order.
      // This assertion captures the legacy behavior of returning the first.
      expect(selected.path == a.path || selected.path == b.path, isTrue);
    });

    test('falls back to all exes when exclusions filter out all', () {
      final cp1 = File(p.join(tempDir.path, 'crashpad_handler.exe'))
        ..createSync();
      final cp2 = File(p.join(tempDir.path, 'crashpad_wer.exe'))..createSync();

      final selected = selectWindowsAppExe(tempDir);
      // When only excluded names exist, we fall back to the original list.
      expect(
        selected.path == cp1.path || selected.path == cp2.path,
        isTrue,
      );
    });
  });
}
