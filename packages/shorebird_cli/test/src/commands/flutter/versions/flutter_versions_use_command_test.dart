import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

import '../../../mocks.dart';

void main() {
  group(FlutterVersionsUseCommand, () {
    late ArgResults argResults;
    late Progress progress;
    late ShorebirdLogger logger;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdEnv shorebirdEnv;
    late FlutterVersionsUseCommand command;
    late Directory testDirectory;
    late File versionFile;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      progress = MockProgress();
      logger = MockShorebirdLogger();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdEnv = MockShorebirdEnv();
      testDirectory = Directory.systemTemp.createTempSync();
      versionFile = File(
        p.join(testDirectory.path, 'bin', 'internal', 'flutter.version'),
      );

      when(() => shorebirdEnv.shorebirdRoot).thenReturn(testDirectory);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => argResults.rest).thenReturn([]);

      command = runWithOverrides(FlutterVersionsUseCommand.new)
        ..testArgResults = argResults;
    });

    tearDown(() {
      testDirectory.deleteSync(recursive: true);
    });

    test('has correct name, description and invocation', () {
      expect(command.name, equals('use'));
      expect(
        command.description,
        equals('Set the global Flutter version used by Shorebird.'),
      );
      expect(
        command.invocation,
        equals('shorebird flutter versions use <version>'),
      );
    });

    test('exits with usage code when no version specified', () async {
      when(() => argResults.rest).thenReturn([]);

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.usage.code)),
      );
      verifyInOrder([
        () => logger.err('Please specify a Flutter version.'),
        () => logger.info('Usage: shorebird flutter versions use <version>'),
        () => logger.info(''),
        () => logger.info('Available versions can be listed with:'),
        () => logger.info('  shorebird flutter versions list'),
      ]);
    });

    test('exits with software code when version cannot be resolved', () async {
      when(() => argResults.rest).thenReturn(['1.0.0']);
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenAnswer((_) async => null);

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );

      verifyInOrder([
        () => logger.progress('Resolving Flutter version'),
        () => shorebirdFlutter.resolveFlutterRevision('1.0.0'),
        () => progress.fail('Version 1.0.0 not found'),
        () => logger.info(''),
        () => logger.info('Available versions can be listed with:'),
        () => logger.info('  shorebird flutter versions list'),
      ]);
    });

    test('exits with success when version is already active', () async {
      const version = '3.16.0';
      const revision = 'abc123';

      when(() => argResults.rest).thenReturn([version]);
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenAnswer((_) async => revision);
      when(
        () => shorebirdFlutter.getVersionForRevision(flutterRevision: revision),
      ).thenAnswer((_) async => version);
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => version);

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );

      verify(
        () => logger.info('Flutter $version is already the active version.'),
      ).called(1);
    });

    test('successfully sets new Flutter version', () async {
      const requestedVersion = '3.16.0';
      const revision = 'abc123';
      const currentVersion = '3.15.0';

      when(() => argResults.rest).thenReturn([requestedVersion]);
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenAnswer((_) async => revision);
      when(
        () => shorebirdFlutter.getVersionForRevision(flutterRevision: revision),
      ).thenAnswer((_) async => requestedVersion);
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => currentVersion);
      when(
        () => shorebirdFlutter.installRevision(revision: revision),
      ).thenAnswer((_) async {});

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );

      expect(versionFile.existsSync(), isTrue);
      expect(versionFile.readAsStringSync(), equals(revision));

      verifyInOrder([
        () => logger.progress('Resolving Flutter version'),
        () => progress.complete(),
        () => logger.progress('Setting Flutter version to $requestedVersion'),
        () => shorebirdFlutter.installRevision(revision: revision),
        () => progress.complete(),
        () => logger.info(''),
        () => logger.success('Flutter version set to $requestedVersion'),
        () => logger.info(''),
        () => logger.info('To verify the change, run:'),
        () => logger.info('  ${lightCyan.wrap('shorebird flutter --version')}'),
      ]);
    });

    test('exits with software code when installation fails', () async {
      const requestedVersion = '3.16.0';
      const revision = 'abc123';
      const error = 'Installation failed';

      when(() => argResults.rest).thenReturn([requestedVersion]);
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenAnswer((_) async => revision);
      when(
        () => shorebirdFlutter.getVersionForRevision(flutterRevision: revision),
      ).thenAnswer((_) async => requestedVersion);
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => null);
      when(
        () => shorebirdFlutter.installRevision(revision: revision),
      ).thenThrow(Exception(error));

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );

      verifyInOrder([
        () => logger.progress('Setting Flutter version to $requestedVersion'),
        () => shorebirdFlutter.installRevision(revision: revision),
        () => progress.fail('Failed to set Flutter version'),
        () => logger.err('Exception: $error'),
      ]);
    });

    test('works with git revision instead of version number', () async {
      const revision = 'abc123def456';
      const version = '3.16.0';

      when(() => argResults.rest).thenReturn([revision]);
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenAnswer((_) async => revision);
      when(
        () => shorebirdFlutter.getVersionForRevision(flutterRevision: revision),
      ).thenAnswer((_) async => version);
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => null);
      when(
        () => shorebirdFlutter.installRevision(revision: revision),
      ).thenAnswer((_) async {});

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );

      expect(versionFile.readAsStringSync(), equals(revision));
      verify(() => logger.success('Flutter version set to $version')).called(1);
    });

    test('handles resolveFlutterRevision errors gracefully', () async {
      const requestedVersion = '3.16.0';
      const error = 'Network error';

      when(() => argResults.rest).thenReturn([requestedVersion]);
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenThrow(Exception(error));

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );

      verifyInOrder([
        () => logger.progress('Resolving Flutter version'),
        () => progress.fail('Failed to resolve Flutter version'),
        () => logger.err('Exception: $error'),
      ]);
    });
  });
}
