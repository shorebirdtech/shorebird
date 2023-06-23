import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  group(FileSetDiff, () {
    group('fromPathHashes', () {
      test('detects added, changed, and removed files', () {
        final oldPathHashes = {
          'a': 'asdf',
          'b': 'qwer',
        };
        final newPathHashes = {
          'a': 'qwer',
          'c': 'zxcv',
        };

        final fileSetDiff = FileSetDiff.fromPathHashes(
          oldPathHashes: oldPathHashes,
          newPathHashes: newPathHashes,
        );
        expect(fileSetDiff.addedPaths, {'c'});
        expect(fileSetDiff.changedPaths, {'a'});
        expect(fileSetDiff.removedPaths, {'b'});
      });
    });

    group('prettyString', () {
      test('returns a string with added, changed, and removed files', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {'a', 'b'},
          changedPaths: {'c'},
          removedPaths: {'d'},
        );
        expect(
          fileSetDiff.prettyString,
          '''
    Added files:
        a
        b
    Changed files:
        c
    Removed files:
        d''',
        );
      });

      test('does not include empty path sets', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {'a', 'b'},
          changedPaths: {},
          removedPaths: {},
        );
        expect(
          fileSetDiff.prettyString,
          '''
    Added files:
        a
        b''',
        );
      });
    });

    test('isEmpty is true if all path sets are empty', () {
      final fileSetDiff = FileSetDiff.empty();
      expect(fileSetDiff.isEmpty, isTrue);
      expect(fileSetDiff.isNotEmpty, isFalse);
    });

    test('isEmpty is false if any path sets are not empty', () {
      final fileSetDiff = FileSetDiff(
        addedPaths: {'a'},
        changedPaths: {},
        removedPaths: {},
      );
      expect(fileSetDiff.isEmpty, isFalse);
      expect(fileSetDiff.isNotEmpty, isTrue);
    });
  });
}
