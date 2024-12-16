// cspell:ignore qwer
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
        ..addOption(
          CommonArguments.buildNameArg.name,
          help: CommonArguments.buildNameArg.description,
        )
        ..addOption(
          CommonArguments.buildNumberArg.name,
          help: CommonArguments.buildNumberArg.description,
        )
        ..addOption(
          CommonArguments.splitDebugInfoArg.name,
          help: CommonArguments.splitDebugInfoArg.description,
        )
        ..addOption(
          CommonArguments.exportMethodArg.name,
          help: CommonArguments.exportMethodArg.description,
        )
        ..addOption(
          CommonArguments.exportOptionsPlistArg.name,
          help: CommonArguments.exportOptionsPlistArg.description,
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

    group('when build-name and build-number are provided', () {
      test('forwards build-name and build-number', () {
        final args = [
          '--verbose',
          '--',
          '--build-name=1.2.3',
          '--build-number=4',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(2));
        expect(
          result.forwardedArgs,
          containsAll(
            [
              '--build-name=1.2.3',
              '--build-number=4',
            ],
          ),
        );
      });
    });

    group('when build-name and build-number are before the --', () {
      test('forwards build-name and build-number', () {
        final args = [
          '--verbose',
          '--build-name=1.2.3',
          '--build-number=4',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(2));
        expect(
          result.forwardedArgs,
          containsAll(
            [
              '--build-name=1.2.3',
              '--build-number=4',
            ],
          ),
        );
      });
    });

    group('when split-debug-info is provided before the --', () {
      test('forwards it', () {
        final args = [
          '--verbose',
          '--split-debug-info=build/symbols',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(1));
        expect(
          result.forwardedArgs,
          contains('--split-debug-info=build/symbols'),
        );
      });
    });

    group('when split-debug-info is provided after the --', () {
      test('forwards it', () {
        final args = [
          '--verbose',
          '--',
          '--split-debug-info=build/symbols',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(1));
        expect(
          result.forwardedArgs,
          contains('--split-debug-info=build/symbols'),
        );
      });
    });

    group('when export method is provided before the --', () {
      test('forwards it', () {
        final args = [
          '--verbose',
          '--export-method=development',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(1));
        expect(
          result.forwardedArgs,
          contains('--export-method=development'),
        );
      });
    });

    group('when export method is provided after the --', () {
      test('forwards it', () {
        final args = [
          '--verbose',
          '--',
          '--export-method=development',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(1));
        expect(
          result.forwardedArgs,
          contains('--export-method=development'),
        );
      });
    });

    group('when export options plist is provided before the --', () {
      test('forwards it', () {
        final args = [
          '--verbose',
          '--export-options-plist=build/ExportOptions.plist',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(1));
        expect(
          result.forwardedArgs,
          contains('--export-options-plist=build/ExportOptions.plist'),
        );
      });
    });

    group('when export options plist is provided after the --', () {
      test('forwards it', () {
        final args = [
          '--verbose',
          '--',
          '--export-options-plist=build/ExportOptions.plist',
        ];
        final result = parser.parse(args);
        expect(result.forwardedArgs, hasLength(1));
        expect(
          result.forwardedArgs,
          contains('--export-options-plist=build/ExportOptions.plist'),
        );
      });
    });
  });
}
