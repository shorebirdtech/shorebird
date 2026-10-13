import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/release/assert_release_version_provided.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group('assertReleaseVersionProvided', () {
    late ArgResults argResults;
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      logger = MockShorebirdLogger();
      when(() => argResults.wasParsed('release-version')).thenReturn(false);
    });

    test('returns normally when --release-version was provided', () {
      when(() => argResults.wasParsed('release-version')).thenReturn(true);

      expect(
        () => runWithOverrides(
          () => assertReleaseVersionProvided(
            argResults: argResults,
            hostAppLabel: 'Android',
            exampleCommand:
                'shorebird release aar '
                '--release-version=$releaseVersionExample',
          ),
        ),
        returnsNormally,
      );
      verifyNever(() => logger.err(any()));
    });

    test('exits with code 64 and logs host-app guidance when missing', () {
      const exampleCommand =
          'shorebird release aar --release-version=$releaseVersionExample';

      expect(
        () => runWithOverrides(
          () => assertReleaseVersionProvided(
            argResults: argResults,
            hostAppLabel: 'Android',
            exampleCommand: exampleCommand,
          ),
        ),
        exitsWithCode(ExitCode.usage),
      );
      verify(
        () => logger.err('''
Missing required argument: --release-version.

Pass the version of the Android app that embeds this module
(e.g. $releaseVersionExample).

Example:
  ${lightCyan.wrap(exampleCommand)}
'''),
      ).called(1);
    });

    test('example command uses release cliName, not platform name', () {
      const aarExample =
          'shorebird release aar --release-version=$releaseVersionExample';
      const iosFrameworkExample =
          'shorebird release ios-framework '
          '--release-version=$releaseVersionExample';

      expect(aarExample, contains('release aar'));
      expect(aarExample, isNot(contains('release android')));
      expect(iosFrameworkExample, contains('release ios-framework'));
      expect(iosFrameworkExample, isNot(contains('release ios ')));
      expect(aarExample, contains('--release-version=$releaseVersionExample'));
    });
  });
}
