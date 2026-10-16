// cspell:words EPIPE PIPESTATUS
import 'dart:io';

import 'package:path/path.dart' as p;
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

  group('the shorebird entrypoint', testOn: '!windows', () {
    // Runs bin/shorebird.dart with one stream piped into `true`, which exits
    // before the CLI writes, and returns the CLI's exit status (bash's
    // PIPESTATUS) and what it printed to stderr when stdout is the closed
    // stream.
    Future<({int status, String otherOutput})> runIntoClosedPipe({
      required List<String> args,
      required bool stderrClosed,
    }) async {
      final entrypoint = packagePath(p.join('bin', 'shorebird.dart'));
      final command = [
        Platform.resolvedExecutable,
        entrypoint,
        ...args,
      ].map((arg) => "'$arg'").join(' ');
      final redirect = stderrClosed ? '2>&1 1>/dev/null' : '';
      final result = await Process.run('bash', [
        '-c',
        '$command $redirect | true; echo "status=\${PIPESTATUS[0]}"',
      ]);
      final match = RegExp(r'status=(\d+)').firstMatch(result.stdout as String);
      return (
        status: int.parse(match!.group(1)!),
        otherOutput: result.stderr as String,
      );
    }

    test(
      'exits $brokenPipeExitCode when the stdout reader is gone',
      () async {
        final result = await runIntoClosedPipe(
          args: ['--help'],
          stderrClosed: false,
        );
        expect(result.status, equals(brokenPipeExitCode));
        expect(result.otherOutput, isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'exits $brokenPipeExitCode when the stderr reader is gone',
      () async {
        final result = await runIntoClosedPipe(
          args: ['not-a-command'],
          stderrClosed: true,
        );
        expect(result.status, equals(brokenPipeExitCode));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

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
