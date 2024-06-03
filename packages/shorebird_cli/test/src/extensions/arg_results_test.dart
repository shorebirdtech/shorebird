import 'package:args/args.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/release_type.dart';
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

  group('forwardedArgs', () {
    late ArgParser parser;

    setUp(() {
      parser = ArgParser()
        ..addMultiOption(
          CommonArguments.dartDefineArg.name,
          help: CommonArguments.dartDefineArg.description,
        )
        ..addMultiOption(
          CommonArguments.dartDefineFromFileArg.name,
          help: CommonArguments.dartDefineFromFileArg.description,
        )
        ..addMultiOption(
          'platforms',
          allowed: ReleaseType.values.map((e) => e.cliName),
        )
        ..addFlag('verbose', abbr: 'v');
    });

    test('returns an empty list when rest is empty', () {
      final args = <String>[];
      final result = parser.parse(args);
      expect(result.forwardedArgs, isEmpty);
    });

    test('returns an empty list if no args are forwarded', () {
      final args = ['--verbose'];
      final result = parser.parse(args);
      expect(result.forwardedArgs, isEmpty);
    });

    test('forwards args when a platform is specified via rest', () {
      final args = ['android', '--', '--verbose'];
      final result = parser.parse(args);
      expect(result.forwardedArgs, ['--verbose']);
    });

    test('forwards args when a platform is specified via option', () {
      final args = ['--platforms', 'android', '--', '--verbose'];
      final result = parser.parse(args);
      expect(result.forwardedArgs, ['--verbose']);
    });

    test('forwards args when no platforms are specified', () {
      final args = ['--', '--verbose'];
      final result = parser.parse(args);
      expect(result.forwardedArgs, ['--verbose']);
    });

    group('when dart-define args are provided', () {
      test('forwards dart-define args', () {
        final args = [
          'asdf',
          'qwer',
          '--verbose',
          '--dart-define=foo=bar',
          '--dart-define=bar=baz',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(4));
        expect(
          result.forwardedArgs,
          containsAll(
            ['asdf', 'qwer', '--dart-define=foo=bar', '--dart-define=bar=baz'],
          ),
        );
      });
    });

    group('when dart-define-from-file args are provided', () {
      test('forwards dart-define-from-file args', () {
        final args = [
          '--verbose',
          '--dart-define=foo=bar',
          '--dart-define-from-file=bar.json',
          '--',
          '--test',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(3));
        expect(
          result.forwardedArgs,
          containsAll(
            [
              '--dart-define=foo=bar',
              '--dart-define-from-file=bar.json',
              '--test',
            ],
          ),
        );
      });
    });
  });
}
