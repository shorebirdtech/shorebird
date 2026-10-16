// cspell:words EPIPE
import 'dart:io';

import 'package:shorebird_cli/src/broken_pipe.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  FileSystemException fileError(int errorCode) => FileSystemException(
    'writeFrom failed',
    '',
    OSError('Broken pipe', errorCode),
  );

  group('isBrokenPipe', () {
    test('is true for EPIPE from a file write', () {
      expect(isBrokenPipe(fileError(32)), isTrue);
    });

    test('is true for EPIPE from a socket', () {
      expect(
        isBrokenPipe(
          const SocketException('write', osError: OSError('Broken pipe', 32)),
        ),
        isTrue,
      );
    });

    test("is true for Windows' broken pipe errors", () {
      expect(isBrokenPipe(fileError(109)), isTrue);
      expect(isBrokenPipe(fileError(232)), isTrue);
    });

    test('is false for other OS errors', () {
      expect(isBrokenPipe(fileError(28)), isFalse);
    });

    test('is false without an OS error', () {
      expect(isBrokenPipe(const FileSystemException('nope')), isFalse);
      expect(isBrokenPipe(Exception('nope')), isFalse);
    });
  });
}
