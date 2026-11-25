import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(FlutterPrecacheCommand, () {
    const pinnedRevision = 'pinned1234567890';
    const requestedRevision = 'requested1234567890';

    late ArgResults argResults;
    late Cache cache;
    late ShorebirdEnv targetEnv;
    late List<String> cacheUpdateRevisions;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late FlutterPrecacheCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      cache = MockCache();
      targetEnv = MockShorebirdEnv();
      cacheUpdateRevisions = [];
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      command = runWithOverrides(FlutterPrecacheCommand.new)
        ..testArgResults = argResults;

      when(() => argResults['flutter-version']).thenReturn(null);
      when(() => shorebirdEnv.flutterRevision).thenReturn(pinnedRevision);
      when(
        () => shorebirdEnv.copyWith(
          flutterRevisionOverride: any(named: 'flutterRevisionOverride'),
        ),
      ).thenAnswer((invocation) {
        final revision =
            invocation.namedArguments[#flutterRevisionOverride] as String;
        when(() => targetEnv.flutterRevision).thenReturn(revision);
        return targetEnv;
      });
      when(() => cache.updateAll()).thenAnswer((_) async {
        cacheUpdateRevisions.add(read(shorebirdEnvRef).flutterRevision);
      });
      when(
        () =>
            shorebirdFlutter.installRevision(revision: any(named: 'revision')),
      ).thenAnswer((_) async {});
      when(
        () => shorebirdFlutter.getVersionForRevision(
          flutterRevision: any(named: 'flutterRevision'),
        ),
      ).thenAnswer((_) async => '3.38.5');
      when(() => shorebirdFlutter.fetchRemoteRefs()).thenAnswer((_) async {});
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenAnswer((_) async => requestedRevision);
    });

    test('has correct name and description', () {
      expect(command.name, equals('precache'));
      expect(
        command.description,
        equals(
          'Install a Flutter version and its build artifacts without building.',
        ),
      );
    });

    group('when --flutter-version is omitted', () {
      test('installs the pinned revision without fetching refs', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(ExitCode.success.code)),
        );
        verify(
          () => shorebirdFlutter.installRevision(revision: pinnedRevision),
        ).called(1);
        verifyNever(() => shorebirdFlutter.fetchRemoteRefs());
        expect(cacheUpdateRevisions, equals([pinnedRevision]));
        verify(
          () => logger.info(
            '✅ Flutter 3.38.5 is installed and ready to build with.',
          ),
        ).called(1);
      });
    });

    group('when --flutter-version is latest', () {
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn('latest');
      });

      test('installs the pinned revision', () async {
        await runWithOverrides(command.run);
        verify(
          () => shorebirdFlutter.installRevision(revision: pinnedRevision),
        ).called(1);
      });
    });

    group('when --flutter-version names a version', () {
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn('3.38.5');
      });

      test('fetches refs and installs the resolved revision', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(ExitCode.success.code)),
        );
        verifyInOrder([
          () => shorebirdFlutter.fetchRemoteRefs(),
          () => shorebirdFlutter.resolveFlutterRevision('3.38.5'),
          () => shorebirdFlutter.installRevision(revision: requestedRevision),
        ]);
      });

      test('updates the Shorebird cache for the requested only', () async {
        await runWithOverrides(command.run);
        expect(cacheUpdateRevisions, equals([requestedRevision]));
      });

      test('throws a CommandError when the version is unknown', () async {
        when(
          () => shorebirdFlutter.resolveFlutterRevision(any()),
        ).thenAnswer((_) async => null);
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<CommandError>().having(
              (e) => e.message,
              'message',
              startsWith('Flutter 3.38.5 is not available to Shorebird.'),
            ),
          ),
        );
        verifyNever(
          () => shorebirdFlutter.installRevision(
            revision: any(named: 'revision'),
          ),
        );
      });

      test('throws a CommandError when resolving fails', () async {
        when(
          () => shorebirdFlutter.resolveFlutterRevision(any()),
        ).thenThrow(Exception('git failed'));
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<CommandError>().having(
              (e) => e.message,
              'message',
              contains('Unable to determine the revision for Flutter 3.38.5'),
            ),
          ),
        );
      });
    });

    for (final alias in ['system', 'fvm']) {
      test('refuses --flutter-version=$alias', () async {
        when(() => argResults['flutter-version']).thenReturn(alias);
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<CommandError>().having(
              (e) => e.message,
              'message',
              contains('--flutter-version=$alias is not supported'),
            ),
          ),
        );
        verifyNever(() => shorebirdFlutter.resolveFlutterRevision(any()));
      });
    }

    test('exits with software error when the install fails', () async {
      when(
        () =>
            shorebirdFlutter.installRevision(revision: any(named: 'revision')),
      ).thenThrow(Exception('clone failed'));
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );
      verifyNever(() => cache.updateAll());
    });

    test('names the revision when its version is unknown', () async {
      when(
        () => shorebirdFlutter.getVersionForRevision(
          flutterRevision: any(named: 'flutterRevision'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => shorebirdFlutter.shortRevisionString(pinnedRevision),
      ).thenReturn('pinned1234');
      await runWithOverrides(command.run);
      verify(
        () => logger.info(
          '✅ Flutter pinned1234 is installed and ready to build with.',
        ),
      ).called(1);
    });
  });
}
