import 'package:cli_io/cli_io.dart';
import 'package:test/test.dart';

void main() {
  group('link', () {
    final uri = Uri.parse('https://shorebird.dev');

    test('falls back to markdown when ANSI is disabled', () {
      overrideAnsiOutput(
        enabled: false,
        body: () {
          expect(
            link(uri: uri, message: 'Shorebird'),
            equals('[Shorebird](https://shorebird.dev)'),
          );
          expect(link(uri: uri), equals('https://shorebird.dev'));
        },
      );
    });

    test('emits OSC-8 hyperlink escape when ANSI is enabled', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          final result = link(uri: uri, message: 'Shorebird');
          expect(result, startsWith('\x1B]8;;https://shorebird.dev\x1B\\'));
          expect(result, contains('Shorebird'));
          expect(result, endsWith('\x1B]8;;\x1B\\'));
        },
      );
    });

    test('uses the URI as link text when message is omitted', () {
      overrideAnsiOutput(
        enabled: true,
        body: () {
          final result = link(uri: uri);
          expect(result, contains('https://shorebird.dev'));
        },
      );
    });
  });
}
