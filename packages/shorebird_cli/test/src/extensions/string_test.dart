import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:test/test.dart';

void main() {
  group('IsNullOrEmpty', () {
    group('when string is null', () {
      test('returns true', () {
        expect(null.isNullOrEmpty, true);
      });
    });

    group('when string is empty', () {
      test('returns true', () {
        expect(''.isNullOrEmpty, true);
      });
    });

    group('when string is not empty', () {
      test('returns false', () {
        expect('test'.isNullOrEmpty, false);
      });
    });
  });

  group('AnsiEscapes', () {
    test('removes ansi escape codes from string', () {
      expect(
        styleUnderlined.wrap(
          '''This ${red.wrap('is')} ${styleBlink.wrap('a')} ${lightCyan.wrap('test')}''',
        )!.removeAnsiEscapes(),
        equals('This is a test'),
      );
    });

    test('replaces ansi escape links with markdown links', () {
      expect(
        link(uri: Uri.parse('https://brickhub.dev/policy')).removeAnsiEscapes(),
        equals('[https://brickhub.dev/policy](https://brickhub.dev/policy)'),
      );

      expect(
        link(uri: Uri.parse('http://example.com'), message: 'Example')
            .removeAnsiEscapes(),
        equals('[Example](http://example.com)'),
      );
    });

    test('returns string unchanged if no ansi escape codes are present', () {
      expect('test'.removeAnsiEscapes(), equals('test'));
    });
  });

  group('IsUpperCase', () {
    test('returns true if a string contains only uppercase characters', () {
      expect('TEST'.isUpperCase(), isTrue);
      expect('test'.isUpperCase(), isFalse);
      expect('Test'.isUpperCase(), isFalse);
    });
  });
}
