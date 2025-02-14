import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/checksum_checker.dart';
import 'package:test/test.dart';

void main() {
  group('ChecksumChecker', () {
    late File testFile;
    const checksum =
        'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';

    setUp(() {
      testFile = File(p.join(Directory.systemTemp.path, 'test_file'))
        ..writeAsStringSync('hello world');
    });

    R runWithOverrides<R>(R Function() body) {
      return runScoped(() => body(), values: {checksumCheckerRef});
    }

    group('checkFile', () {
      group('when the hash match', () {
        test('return true', () {
          final result = runWithOverrides(
            () => checksumChecker.checkFile(testFile, checksum),
          );
          expect(result, isTrue);
        });
      });

      group("when the hash doesn't match", () {
        test('return false', () {
          final result = runWithOverrides(
            () => checksumChecker.checkFile(testFile, 'wrong'),
          );
          expect(result, isFalse);
        });
      });
    });
  });
}
