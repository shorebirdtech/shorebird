import 'dart:io';

import 'package:cli_io/cli_io.dart';
import 'package:cli_io/src/ansi.dart' show darkGray;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockStdout extends Mock implements Stdout {}

class _MockStdin extends Mock implements Stdin {}

void main() {
  group('Logger', () {
    late Stdout stdout;
    late Stdout stderr;
    late Stdin stdin;

    setUp(() {
      stdout = _MockStdout();
      stderr = _MockStdout();
      stdin = _MockStdin();
      when(() => stdout.supportsAnsiEscapes).thenReturn(true);
      when(() => stdout.hasTerminal).thenReturn(true);
      when(() => stdout.terminalColumns).thenReturn(80);
    });

    void runZoned(void Function() body) => IOOverrides.runZoned(
      body,
      stdout: () => stdout,
      stderr: () => stderr,
      stdin: () => stdin,
    );

    group('level', () {
      test('defaults to Level.info and is mutable', () {
        final logger = Logger();
        expect(logger.level, equals(Level.info));
        logger.level = Level.verbose;
        expect(logger.level, equals(Level.verbose));
      });
    });

    group('info', () {
      test('writes message to stdout', () {
        runZoned(() {
          Logger().info('hello');
          verify(() => stdout.writeln('hello')).called(1);
        });
      });

      test('is suppressed when level is above info', () {
        runZoned(() {
          Logger(level: Level.warning).info('hello');
          verifyNever(() => stdout.writeln(any<String?>()));
        });
      });

      test('uses caller-provided style when given', () {
        runZoned(() {
          Logger().info('hello', style: (m) => '[$m]');
          verify(() => stdout.writeln('[hello]')).called(1);
        });
      });
    });

    group('err', () {
      test('writes light-red message to stderr', () {
        runZoned(() {
          Logger().err('boom');
          final expected = lightRed.wrap('boom');
          verify(() => stderr.writeln(expected)).called(1);
        });
      });

      test('still emits at Level.error', () {
        runZoned(() {
          Logger(level: Level.error).err('boom');
          verify(() => stderr.writeln(any<String?>())).called(1);
        });
      });

      test('is suppressed at Level.critical', () {
        runZoned(() {
          Logger(level: Level.critical).err('boom');
          verifyNever(() => stderr.writeln(any<String?>()));
        });
      });
    });

    group('warn', () {
      test('writes [WARN] tag and styles yellow+bold', () {
        runZoned(() {
          Logger().warn('careful');
          final expected = yellow.wrap(styleBold.wrap('[WARN] careful'));
          verify(() => stderr.writeln(expected)).called(1);
        });
      });

      test('omits the tag when tag is empty', () {
        runZoned(() {
          Logger().warn('careful', tag: '');
          final expected = yellow.wrap(styleBold.wrap('careful'));
          verify(() => stderr.writeln(expected)).called(1);
        });
      });
    });

    group('detail', () {
      test('is suppressed by default at Level.info', () {
        runZoned(() {
          Logger().detail('verbose stuff');
          verifyNever(() => stdout.writeln(any<String?>()));
        });
      });

      test('writes dark-gray message at Level.debug', () {
        runZoned(() {
          Logger(level: Level.debug).detail('verbose stuff');
          final expected = darkGray.wrap('verbose stuff');
          verify(() => stdout.writeln(expected)).called(1);
        });
      });
    });

    group('success', () {
      test('writes light-green message to stdout', () {
        runZoned(() {
          Logger().success('yay');
          final expected = lightGreen.wrap('yay');
          verify(() => stdout.writeln(expected)).called(1);
        });
      });
    });

    group('progress', () {
      test('returns a Progress that writes to stdout', () {
        runZoned(() {
          Logger().progress('working').cancel();
          verify(() => stdout.write(any<String>())).called(greaterThan(0));
        });
      });

      test('is silent when level is above info', () {
        runZoned(() {
          Logger(level: Level.warning).progress('quiet').complete();
          verifyNever(() => stdout.write(any<String>()));
        });
      });
    });

    group('confirm', () {
      test('returns the default when input is empty', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('');
          expect(
            Logger().confirm('Continue?', defaultValue: true),
            isTrue,
          );
        });
      });

      test('parses common yes responses', () {
        for (final yes in ['y', 'Y', 'yes', 'YES', 'Yep', 'yup']) {
          runZoned(() {
            when(() => stdin.readLineSync()).thenReturn(yes);
            expect(
              Logger().confirm('Continue?'),
              isTrue,
              reason: 'expected "$yes" to parse as yes',
            );
          });
        }
      });

      test('parses common no responses', () {
        for (final no in ['n', 'N', 'no', 'NO', 'nope']) {
          runZoned(() {
            when(() => stdin.readLineSync()).thenReturn(no);
            expect(
              Logger().confirm('Continue?', defaultValue: true),
              isFalse,
              reason: 'expected "$no" to parse as no',
            );
          });
        }
      });

      test('falls back to default for unrecognized input', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('maybe');
          expect(
            Logger().confirm('Continue?', defaultValue: true),
            isTrue,
          );
        });
      });

      test('returns the default when stdin throws FormatException', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenThrow(const FormatException());
          expect(
            Logger().confirm('Continue?', defaultValue: true),
            isTrue,
          );
        });
      });
    });

    group('prompt', () {
      test('returns trimmed input', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('  hello  ');
          expect(Logger().prompt('Name?'), equals('hello'));
        });
      });

      test('returns the default when input is empty', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('');
          expect(
            Logger().prompt('Name?', defaultValue: 'world'),
            equals('world'),
          );
        });
      });

      test('throws when stdout has no terminal', () {
        when(() => stdout.hasTerminal).thenReturn(false);
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('hello');
          expect(
            () => Logger().prompt('Name?'),
            throwsA(isA<StateError>()),
          );
        });
      });
    });

    group('chooseOne', () {
      test('returns the choice for a valid number', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('2');
          expect(
            Logger().chooseOne('Pick one', choices: ['a', 'b', 'c']),
            equals('b'),
          );
        });
      });

      test('returns default when input is empty and a default is provided', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('');
          expect(
            Logger().chooseOne(
              'Pick one',
              choices: ['a', 'b', 'c'],
              defaultValue: 'c',
            ),
            equals('c'),
          );
        });
      });

      test('re-prompts on invalid input', () {
        final responses = ['9', 'banana', '1'];
        var calls = 0;
        runZoned(() {
          when(
            () => stdin.readLineSync(),
          ).thenAnswer((_) => responses[calls++]);
          expect(
            Logger().chooseOne('Pick one', choices: ['a', 'b']),
            equals('a'),
          );
        });
        expect(calls, equals(3));
      });

      test('uses display when rendering choices', () {
        runZoned(() {
          when(() => stdin.readLineSync()).thenReturn('1');
          final result = Logger().chooseOne<int>(
            'Pick one',
            choices: const [10, 20],
            display: (v) => 'value=$v',
          );
          expect(result, equals(10));
          verify(() => stdout.writeln('  1) value=10')).called(1);
        });
      });

      test('throws ArgumentError when choices is empty', () {
        runZoned(() {
          expect(
            () => Logger().chooseOne<String>('Pick one', choices: const []),
            throwsA(isA<ArgumentError>()),
          );
        });
      });
    });
  });
}
