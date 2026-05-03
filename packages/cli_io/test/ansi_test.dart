// cspell:words mhello — emerges from concatenating SGR `\x1B[31m` with `hello`
// in test expectations, which cspell tokenizes as a single identifier.

import 'package:cli_io/cli_io.dart';
import 'package:test/test.dart';

void main() {
  group('AnsiCode', () {
    test('wrap returns the input unchanged when ANSI is disabled', () {
      overrideAnsiOutput(
        enabled: false,
        body: () {
          expect(red.wrap('hello'), equals('hello'));
        },
      );
    });

    test('wrap emits SGR open/close sequences when ANSI is enabled', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          expect(red.wrap('hello'), equals('\x1B[31mhello\x1B[39m'));
          expect(styleBold.wrap('hi'), equals('\x1B[1mhi\x1B[22m'));
        },
      );
    });

    test('wrap returns null/empty input unchanged', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          expect(red.wrap(null), isNull);
          expect(red.wrap(''), equals(''));
        },
      );
    });

    test('forScript forces emission even when ANSI is disabled', () {
      overrideAnsiOutput(
        enabled: false,
        body: () {
          expect(red.wrap('x', forScript: true), equals('\x1B[31mx\x1B[39m'));
        },
      );
    });

    test('chained wraps produce nested escape sequences', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          expect(
            red.wrap(styleBold.wrap('x')),
            equals('\x1B[31m\x1B[1mx\x1B[22m\x1B[39m'),
          );
        },
      );
    });
  });

  group('overrideAnsiOutput', () {
    test('restores the previous override after body completes', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          expect(ansiOutputEnabled, isTrue);
          overrideAnsiOutput(
            enabled: false,
            body: () => expect(ansiOutputEnabled, isFalse),
          );
          expect(ansiOutputEnabled, isTrue);
        },
      );
    });
  });
}
