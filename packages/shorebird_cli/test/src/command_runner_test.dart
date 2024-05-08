import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/logger.dart' hide logger;
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdCliCommandRunner, () {
    const shorebirdEngineRevision = 'test-engine-revision';
    const flutterRevision = 'test-flutter-revision';
    const flutterVersion = '1.2.3';

    late ShorebirdLogger logger;
    late Platform platform;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdVersion shorebirdVersion;
    late ShorebirdCliCommandRunner commandRunner;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdVersionRef.overrideWith(() => shorebirdVersion),
        },
      );
    }

    setUp(() {
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdVersion = MockShorebirdVersion();
      when(() => logger.level).thenReturn(Level.info);
      final logFile = MockFile();
      when(() => logger.logFile).thenReturn(logFile);
      when(() => logFile.absolute).thenReturn(logFile);
      when(() => logFile.path).thenReturn('test.log');
      when(
        () => shorebirdEnv.shorebirdEngineRevision,
      ).thenReturn(shorebirdEngineRevision);
      when(() => platform.isWindows).thenReturn(false);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => flutterVersion);
      when(() => shorebirdVersion.isLatest()).thenAnswer((_) async => true);
      commandRunner = runWithOverrides(ShorebirdCliCommandRunner.new);
    });

    test('handles FormatException', () async {
      const exception = FormatException('oops!');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await runWithOverrides(
        () => commandRunner.run(['--version']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info(commandRunner.usage)).called(1);
    });

    test('handles UsageException', () async {
      final exception = UsageException('oops!', 'exception usage');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await runWithOverrides(
        () => commandRunner.run(['--version']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    test('handles missing option error', () async {
      final exception = UsageException(
        'Could not find an option named "foo".',
        'exception usage',
      );
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await runWithOverrides(
        () => commandRunner.run(['--version']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(
        () => logger.err(
          '''
To proxy an option to the flutter command, use the -- --<option> syntax.

Example:

${lightCyan.wrap('shorebird release android -- --no-pub lib/main.dart')}''',
        ),
      ).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    test('handles missing option error on Windows', () async {
      when(() => platform.isWindows).thenReturn(true);
      final exception = UsageException(
        'Could not find an option named "foo".',
        'exception usage',
      );
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await runWithOverrides(
        () => commandRunner.run(['--version']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(
        () => logger.err(
          '''
To proxy an option to the flutter command, use the '--' --<option> syntax.

Example:

${lightCyan.wrap("shorebird release android '--' --no-pub lib/main.dart")}''',
        ),
      ).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    group('--version', () {
      test('outputs current version info', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['--version']),
        );
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            '''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter $flutterVersion • revision $flutterRevision
Engine • revision $shorebirdEngineRevision''',
          ),
        ).called(1);
      });

      test('gracefully handles case when flutter version cannot be determined',
          () async {
        when(() => shorebirdFlutter.getVersionString()).thenThrow('error');
        final result = await runWithOverrides(
          () => commandRunner.run(['--version']),
        );
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            '''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter • revision $flutterRevision
Engine • revision $shorebirdEngineRevision''',
          ),
        ).called(1);
        verify(
          () => logger.detail('Unable to determine Flutter version.\nerror'),
        ).called(1);
      });

      test('gracefully handles case when latest version cannot be determined',
          () async {
        when(() => shorebirdVersion.isLatest()).thenThrow('error');
        final result = await runWithOverrides(
          () => commandRunner.run(['--version']),
        );
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            '''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter $flutterVersion • revision $flutterRevision
Engine • revision $shorebirdEngineRevision''',
          ),
        ).called(1);
        verify(
          () => logger.detail('Unable to check for updates.\nerror'),
        ).called(1);
      });

      test('logs update message when update is available', () async {
        when(() => shorebirdVersion.isLatest()).thenAnswer((_) async => false);
        final result = await runWithOverrides(
          () => commandRunner.run(['--version']),
        );
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info('''
A new version of shorebird is available!
Run ${lightCyan.wrap('shorebird upgrade')} to upgrade.'''),
        ).called(1);
      });
    });

    group('--verbose', () {
      test('enables verbose logging', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['--verbose']),
        );
        expect(result, equals(ExitCode.success.code));
      });
    });

    group('local engine', () {
      group('when all local engine args are provided', () {
        test('creates engine config with arguments', () async {
          final result = await runWithOverrides(
            () => commandRunner.run([
              '--local-engine',
              'foo',
              '--local-engine-src-path',
              'bar',
              '--local-engine-host',
              'baz',
            ]),
          );
          expect(result, equals(ExitCode.success.code));
        });
      });

      group('when no local engine args are provided', () {
        test('uses empty engine config', () async {
          final result = await runWithOverrides(
            () => commandRunner.run([]),
          );
          expect(result, equals(ExitCode.success.code));
        });
      });

      group('when some local engine args are provided', () {
        test('throws ArgumentException', () async {
          await expectLater(
            () async => runWithOverrides(
              () => commandRunner.run(['--local-engine', 'foo']),
            ),
            throwsArgumentError,
          );
        });
      });
    });

    group('on command failure', () {
      test('logs a stack trace using detail', () async {
        // This will fail due to the release android command missing scoped
        // dependencies.
        // Note: the --verbose flag is here for illustrative purposes only.
        // Because logger is a mock, setting the log level in code does
        // nothing.
        await runWithOverrides(
          () => commandRunner.run(['release', 'android', '--verbose']),
        );
        verify(() => logger.detail(any(that: contains('#0')))).called(1);
      });

      group('when running with --verbose', () {
        setUp(() {
          when(() => logger.level).thenReturn(Level.verbose);
        });

        test('does not suggest running with --verbose', () async {
          // This will fail due to the release android command missing scoped
          // dependencies.
          // Note: the --verbose flag is here for illustrative purposes only.
          // Because logger is a mock, setting the log level in code does
          // nothing.
          await runWithOverrides(
            () => commandRunner.run(['release', 'android', '--verbose']),
          );
          verifyNever(() => logger.info(any(that: contains('--verbose'))));
        });
      });

      group('when running without --verbose', () {
        test('suggests using --verbose flag', () async {
          // This will fail due to the release android command missing scoped
          // dependencies.
          await runWithOverrides(
            () => commandRunner.run(['release', 'android']),
          );
          verify(() => logger.info(any(that: contains('--verbose')))).called(1);
        });
      });
    });

    group('completion', () {
      test('fast tracks completion', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['completion']),
        );
        expect(result, equals(ExitCode.success.code));
      });
    });
  });
}
