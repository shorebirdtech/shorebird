import 'package:args/args.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:test/test.dart';

void main() {
  group('OptionFinder', () {
    late ArgParser argParser;

    setUp(() {
      argParser = ArgParser()
        ..addOption('foo')
        ..addOption('bar');
    });

    group('findOption', () {
      group('when option is passed directly', () {
        test('returns value', () {
          final args = ['--foo=value'];
          final argResults = argParser.parse(args);
          expect(argResults.findOption('foo'), equals('value'));
        });
      });

      group('when option is in rest', () {
        test('returns value', () {
          final args = ['--bar=baz', '--', '--foo=value'];
          final argResults = argParser.parse(args);
          expect(argResults.findOption('foo'), equals('value'));
        });
      });

      group('when option is missing', () {
        test('returns null', () {
          final args = ['--bar=value'];
          final argResults = argParser.parse(args);
          expect(argResults.findOption('foo'), isNull);
        });
      });
    });
  });
}
