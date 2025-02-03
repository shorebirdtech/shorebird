// cspell:ignore asdf, qwer, zxcv
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
        const fileSetDiff = FileSetDiff(
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
        const fileSetDiff = FileSetDiff(
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
      const fileSetDiff = FileSetDiff(
        addedPaths: {'a'},
        changedPaths: {},
        removedPaths: {},
      );
      expect(fileSetDiff.isEmpty, isFalse);
      expect(fileSetDiff.isNotEmpty, isTrue);
    });

    test('supports value based equality comparisons', () {
      // For the sake of testing equality comparisons avoid using const.
      // ignore: prefer_const_constructors
      final fileSetDiffA = FileSetDiff(
        addedPaths: const {'a'},
        changedPaths: const {'b'},
        removedPaths: const {'c'},
      );
      // For the sake of testing equality comparisons avoid using const.
      // ignore: prefer_const_constructors
      final fileSetDiffB = FileSetDiff(
        addedPaths: const {'a'},
        changedPaths: const {'b'},
        removedPaths: const {'c'},
      );
      // For the sake of testing equality comparisons avoid using const.
      // ignore: prefer_const_constructors
      final fileSetDiffC = FileSetDiff(
        addedPaths: const {'c'},
        changedPaths: const {'b'},
        removedPaths: const {'a'},
      );
      expect(fileSetDiffA, equals(fileSetDiffB));
      expect(fileSetDiffA, isNot(equals(fileSetDiffC)));
      expect(fileSetDiffB, isNot(equals(fileSetDiffC)));
    });
  });
}
