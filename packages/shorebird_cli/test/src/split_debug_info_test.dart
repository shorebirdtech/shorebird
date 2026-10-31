import 'package:shorebird_cli/src/split_debug_info.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();
  group('splitDebugInfoDirectory', () {
    test('returns null when no --split-debug-info is passed', () {
      expect(splitDebugInfoDirectory(['--verbose']), isNull);
    });

    test('reads --split-debug-info=<dir>', () {
      expect(
        splitDebugInfoDirectory(['--split-debug-info=symbols']),
        'symbols',
      );
    });

    test('reads --split-debug-info <dir>', () {
      expect(
        splitDebugInfoDirectory(['--split-debug-info', 'symbols']),
        'symbols',
      );
    });

    test('returns the last one passed', () {
      expect(
        splitDebugInfoDirectory([
          '--split-debug-info=first',
          '--split-debug-info',
          'last',
        ]),
        'last',
      );
    });

    test('ignores a trailing --split-debug-info with no value', () {
      expect(splitDebugInfoDirectory(['--split-debug-info']), isNull);
    });
  });
}
