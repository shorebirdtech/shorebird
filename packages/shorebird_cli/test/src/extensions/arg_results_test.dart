import 'package:args/args.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:test/test.dart';

void main() {
  group('OptionFinder', () {
    late ArgParser argParser;

    setUp(() {
      argParser = ArgParser()
        ..addOption('foo', abbr: 'f')
        ..addOption('bar');
    });

    group('findOption', () {
      group('when option is passed directly', () {
        test('returns value', () {
          final args = ['--foo=value'];
          final argResults = argParser.parse(args);
          expect(
            argResults.findOption('foo', argParser: argParser),
            equals('value'),
          );
        });
      });

      group('when option is missing', () {
        test('returns null', () {
          final args = ['--bar=value'];
          final argResults = argParser.parse(args);
          expect(
            argResults.findOption('foo', argParser: argParser),
            isNull,
          );
        });
      });

      group('when option is in rest', () {
        group('when option is passed with full name and equals', () {
          test('returns value', () {
            final args = ['--', '--foo=value'];
            final argResults = argParser.parse(args);
            expect(
              argResults.findOption('foo', argParser: argParser),
              equals('value'),
            );
          });
        });

        group('when option is passed with full name and space', () {
          test('returns value', () {
            final args = ['--', '--foo', 'value', '--bar', 'value2'];
            final argResults = argParser.parse(args);
            expect(
              argResults.findOption('foo', argParser: argParser),
              equals('value'),
            );
          });
        });

        group('when option is passed with abbreviation and equals', () {
          test('returns value', () {
            final args = ['--', '-f=value'];
            final argResults = argParser.parse(args);
            expect(
              argResults.findOption('foo', argParser: argParser),
              equals('value'),
            );
          });
        });

        group('when option is passed with abbreviation and space', () {
          test('returns value', () {
            final args = ['--', '-f', 'value'];
            final argResults = argParser.parse(args);
            expect(
              argResults.findOption('foo', argParser: argParser),
              equals('value'),
            );
          });
        });
      });
    });
  });
}
