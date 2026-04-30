import 'dart:io';

import 'package:cli_io/cli_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockStdout extends Mock implements Stdout {}

void main() {
  group('Progress', () {
    late Stdout stdout;

    setUp(() {
      stdout = _MockStdout();
      when(() => stdout.supportsAnsiEscapes).thenReturn(true);
      when(() => stdout.hasTerminal).thenReturn(true);
      when(() => stdout.terminalColumns).thenReturn(80);
    });

    Progress make(String message, {Level level = Level.info}) =>
        Progress(message: message, stdout: stdout, level: level);

    test('writes a static line and no animation when not a terminal', () {
      when(() => stdout.hasTerminal).thenReturn(false);
      overrideAnsiOutput(
        enabled: false,
        body: () => make('working').cancel(),
      );
      verify(() => stdout.write(any<String>())).called(greaterThan(0));
    });

    test('complete writes a checkmark and elapsed time', () {
      overrideAnsiOutput(
        enabled: true,
        body: () => make('working').complete('done'),
      );
      final calls = verify(() => stdout.write(captureAny<String>())).captured;
      final final_ = calls.last as String;
      expect(final_, contains('✓'));
      expect(final_, contains('done'));
      expect(final_, endsWith('\n'));
    });

    test('fail writes an X mark', () {
      overrideAnsiOutput(
        enabled: true,
        body: () => make('working').fail('oops'),
      );
      final calls = verify(() => stdout.write(captureAny<String>())).captured;
      final final_ = calls.last as String;
      expect(final_, contains('✗'));
      expect(final_, contains('oops'));
    });

    test('cancel clears the line', () {
      overrideAnsiOutput(
        enabled: true,
        body: () => make('working').cancel(),
      );
      final calls = verify(() => stdout.write(captureAny<String>())).captured;
      final final_ = calls.last as String;
      expect(final_, contains('\x1b[2K'));
    });

    test('is silent when level is above info', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          make('quiet', level: Level.warning).complete();
        },
      );
      verifyNever(() => stdout.write(any<String>()));
    });

    test('update changes the message used by complete', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          make('initial')
            ..update('updated')
            ..complete();
        },
      );
      final calls = verify(() => stdout.write(captureAny<String>())).captured;
      final final_ = calls.last as String;
      expect(final_, contains('updated'));
    });
  });
}
