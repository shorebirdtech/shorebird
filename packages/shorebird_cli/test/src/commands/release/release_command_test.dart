import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(ReleaseCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersionString = '3.22.0';
    final flutterVersion = Version(3, 22, 0);
    const releaseVersion = '1.2.3+1';
    const postReleaseInstructions = 'Make a patch!';
    const artifactDisplayName = 'Amiga app';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final release = Release(
      id: 0,
      appId: appId,
      version: releaseVersion,
      flutterRevision: flutterRevision,
      flutterVersion: flutterVersionString,
      displayName: '1.2.3+1',
      platformStatuses: const {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );

    late ArgResults argResults;
    late Cache cache;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late ShorebirdLogger logger;
    late Progress progress;
    late Releaser releaser;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;

    late ReleaseCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(release);
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(UpdateReleaseMetadata.forTest());
    });

    setUp(() {
      argResults = MockArgResults();
      cache = MockCache();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      releaser = MockReleaser();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['platforms']).thenReturn(['android']);
      when(() => argResults['flutter-version']).thenReturn('latest');
      when(() => argResults.wasParsed(any())).thenReturn(true);

      when(cache.updateAll).thenAnswer((_) async => {});

      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
          metadata: any(named: 'metadata'),
        ),
      ).thenAnswer((_) async {});

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);

      when(() => releaser.artifactDisplayName).thenReturn(artifactDisplayName);
      when(() => releaser.assertPreconditions()).thenAnswer((_) async => {});
      when(() => releaser.assertArgsAreValid()).thenAnswer((_) async => {});
      when(
        () => releaser.buildReleaseArtifacts(),
      ).thenAnswer((_) async => File(''));
      when(
        () => releaser.getReleaseVersion(
          releaseArtifactRoot: any(named: 'releaseArtifactRoot'),
        ),
      ).thenAnswer((_) async => releaseVersion);
      when(
        () => releaser.uploadReleaseArtifacts(
          release: any(named: 'release'),
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => releaser.postReleaseInstructions,
      ).thenReturn(postReleaseInstructions);
      when(() => releaser.releaseType).thenReturn(ReleaseType.android);
      when(
        () => releaser.updatedReleaseMetadata(any()),
      ).thenAnswer((_) async => UpdateReleaseMetadata.forTest());

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdEnv.copyWith(
          flutterRevisionOverride: any(named: 'flutterRevisionOverride'),
        ),
      ).thenAnswer((invocation) {
        when(() => shorebirdEnv.flutterRevision).thenReturn(
          invocation.namedArguments[#flutterRevisionOverride] as String,
        );
        return shorebirdEnv;
      });
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);

      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterRevision);
      when(
        () =>
            shorebirdFlutter.installRevision(revision: any(named: 'revision')),
      ).thenAnswer((_) async => {});
      when(
        () => shorebirdFlutter.resolveFlutterVersion(any()),
      ).thenAnswer((_) async => flutterVersion);

      when(
        () => shorebirdValidator.validateFlavors(
          flavorArg: any(named: 'flavorArg'),
        ),
      ).thenAnswer((_) async => {});

      command = ReleaseCommand(resolveReleaser: (_) => releaser)
        ..testArgResults = argResults;
    });

    test('has non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    group('getReleaser', () {
      test('maps the correct platform to the releaser', () async {
        expect(command.getReleaser(ReleaseType.aar), isA<AarReleaser>());
        expect(
          command.getReleaser(ReleaseType.android),
          isA<AndroidReleaser>(),
        );
        expect(command.getReleaser(ReleaseType.ios), isA<IosReleaser>());
        expect(
          command.getReleaser(ReleaseType.iosFramework),
          isA<IosFrameworkReleaser>(),
        );
        expect(command.getReleaser(ReleaseType.linux), isA<LinuxReleaser>());
        expect(command.getReleaser(ReleaseType.macos), isA<MacosReleaser>());
        expect(
          command.getReleaser(ReleaseType.windows),
          isA<WindowsReleaser>(),
        );
      });
    });

    group('when public key path is provided but no key exists', () {
      setUp(() {
        when(
          () => argResults[CommonArguments.publicKeyArg.name],
        ).thenReturn('/path/to/nonexistent/file');
      });

      test('exits with usage code', () async {
        await expectLater(
          runWithOverrides(command.run),
          exitsWithCode(ExitCode.usage),
        );

        verifyNever(
          () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
        );
      });
    });

    group('when --build-name is provided and existing release exists', () {
      final existingRelease = Release(
        id: 0,
        appId: appId,
        version: releaseVersion,
        flutterRevision: flutterRevision,
        flutterVersion: flutterVersionString,
        displayName: '1.2.3+1',
        platformStatuses: const {
          ReleasePlatform.android: ReleaseStatus.active,
        },
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );
      setUp(() {
        when(
          () => argResults[CommonArguments.buildNameArg.name],
        ).thenReturn('1.2.3');
        when(
          () => argResults[CommonArguments.buildNumberArg.name],
        ).thenReturn('1');

        when(
          () => codePushClientWrapper.maybeGetRelease(
            appId: appId,
            releaseVersion: releaseVersion,
          ),
        ).thenAnswer((_) async => existingRelease);

        when(
          () => codePushClientWrapper.ensureReleaseIsNotActive(
            release: existingRelease,
            platform: ReleasePlatform.android,
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('fails fast instead of building', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.software),
        );
        verify(
          () => codePushClientWrapper.ensureReleaseIsNotActive(
            release: existingRelease,
            platform: ReleasePlatform.android,
          ),
        ).called(1);
        verifyNever(() => releaser.buildReleaseArtifacts());
      });
    });

    test('executes commands in order, completes successfully', () async {
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.success.code));

      verifyInOrder([
        releaser.assertPreconditions,
        releaser.assertArgsAreValid,
        () => shorebirdValidator.validateFlavors(flavorArg: null),
        cache.updateAll,
        () => codePushClientWrapper.getApp(appId: appId),
        () => logger.info(
          'Building $artifactDisplayName with Flutter $flutterRevision',
        ),
        () => releaser.buildReleaseArtifacts(),
        () => releaser.getReleaseVersion(
          releaseArtifactRoot: any(named: 'releaseArtifactRoot'),
        ),
        () => releaser.uploadReleaseArtifacts(release: release, appId: appId),
        () => logger.success('''

✅ Published Release ${release.version}!'''),
        () => logger.info(postReleaseInstructions),
        () => logger.info(
          '''To create a patch for this release, run ${lightCyan.wrap('shorebird patch --platforms=android --release-version=${release.version}')}''',
        ),
      ]);
    });

    group('when build fails', () {
      setUp(() {
        when(
          () => releaser.buildReleaseArtifacts(),
        ).thenThrow(Exception('oops'));
      });

      test('exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.software),
        );
        verify(
          () =>
              logger.err('Failed to build release artifacts: Exception: oops'),
        ).called(1);
      });

      group('when failure is an ArtifactBuildException', () {
        late ArtifactBuildException exception;

        setUp(() {
          exception = MockArtifactBuildException();
          when(() => exception.message).thenReturn('oops');
          when(() => releaser.buildReleaseArtifacts()).thenThrow(exception);
        });

        group('when a fix recommendation is provided', () {
          setUp(() {
            when(() => exception.fixRecommendation).thenReturn('fix it');
          });

          test('logs fix recommendation at the info level', () async {
            await expectLater(
              () => runWithOverrides(command.run),
              exitsWithCode(ExitCode.software),
            );
            verify(() => logger.info('fix it')).called(1);
          });
        });
      });
    });

    group('when dry-run is specified', () {
      setUp(() {
        when(() => argResults['dry-run']).thenReturn(true);
      });

      test('does not publish release', () async {
        await expectLater(
          runWithOverrides(command.run),
          exitsWithCode(ExitCode.success),
        );

        verify(() => logger.info('No issues detected.')).called(1);

        verifyNever(() => logger.confirm(any()));
        verifyNever(
          () => codePushClientWrapper.createRelease(
            appId: appId,
            version: any(named: 'version'),
            flutterRevision: any(named: 'flutterRevision'),
            platform: any(named: 'platform'),
          ),
        );
      });
    });

    group('when --no-confirm is specified', () {
      setUp(() {
        when(() => argResults['no-confirm']).thenReturn(true);
      });

      test('does not prompt for confirmation', () async {
        await runWithOverrides(command.run);
        verifyNever(() => logger.confirm(any()));
      });
    });

    group('when flavor and target are provided', () {
      const flavor = 'test-flavor';
      const target = 'test-target';

      setUp(() {
        when(() => argResults['flavor']).thenReturn(flavor);
        when(() => argResults['target']).thenReturn(target);
      });

      test('executes commands in order, completes successfully', () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));

        verifyInOrder([
          releaser.assertPreconditions,
          releaser.assertArgsAreValid,
          () => shorebirdValidator.validateFlavors(flavorArg: flavor),
          cache.updateAll,
          () => codePushClientWrapper.getApp(appId: appId),
          () => logger.info(
            'Building $artifactDisplayName with Flutter $flutterRevision',
          ),
          () => releaser.buildReleaseArtifacts(),
          () => releaser.getReleaseVersion(
            releaseArtifactRoot: any(named: 'releaseArtifactRoot'),
          ),
          () => releaser.uploadReleaseArtifacts(release: release, appId: appId),
          () => logger.success('''

✅ Published Release ${release.version}!'''),
          () => logger.info(postReleaseInstructions),
          () => logger.info(
            '''To create a patch for this release, run ${lightCyan.wrap('shorebird patch --platforms=android --flavor=$flavor --target=$target --release-version=${release.version}')}''',
          ),
        ]);
      });
    });

    group('when there is an existing release with the same version', () {
      late Release existingRelease;
      setUp(() {
        existingRelease = release;
        when(
          () => codePushClientWrapper.maybeGetRelease(
            appId: appId,
            releaseVersion: releaseVersion,
          ),
        ).thenAnswer((_) async => existingRelease);
      });

      group('when the release uses a different version of Flutter', () {
        setUp(() {
          existingRelease = Release(
            id: 0,
            appId: appId,
            version: releaseVersion,
            flutterRevision: 'different',
            flutterVersion: '3.12.1',
            displayName: '1.2.3+1',
            platformStatuses: const {},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          );

          when(
            () => shorebirdFlutter.getVersionForRevision(
              flutterRevision: flutterRevision,
            ),
          ).thenAnswer((_) async => flutterVersionString);

          when(
            () => shorebirdFlutter.formatVersion(
              revision: flutterRevision,
              version: flutterVersionString,
            ),
          ).thenReturn('3.12.1');
          when(
            () => shorebirdFlutter.formatVersion(
              revision: existingRelease.flutterRevision,
              version: existingRelease.flutterVersion,
            ),
          ).thenReturn('3.12.1');
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );
        });
      });

      group('when the release uses the same version of Flutter', () {
        test('completes successfully', () async {
          expect(
            await runWithOverrides(command.run),
            equals(ExitCode.success.code),
          );
          verify(
            () => codePushClientWrapper.ensureReleaseIsNotActive(
              release: any(named: 'release'),
              platform: ReleasePlatform.android,
            ),
          ).called(1);
        });
      });
    });

    group('when the user does not confirm the release', () {
      setUp(() {
        when(() => logger.confirm(any())).thenReturn(false);
      });

      test('exits with code 0', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.success),
        );
        verify(() => logger.info('Aborting.')).called(1);
      });
    });

    group('when flutter-version is provided', () {
      const flutterVersion = '3.16.3';
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn(flutterVersion);
      });

      group('when unable to determine flutter revision', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => shorebirdFlutter.resolveFlutterRevision(any()),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err('''
Unable to determine revision for Flutter version: $flutterVersion.
$exception'''),
          ).called(1);
        });
      });

      group('when flutter version is not supported', () {
        setUp(() {
          when(
            () => shorebirdFlutter.resolveFlutterRevision(any()),
          ).thenAnswer((_) async => null);
        });

        test('exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err(
              any(that: contains('Version $flutterVersion not found.')),
            ),
          ).called(1);
        });
      });

      group('when flutter version is supported', () {
        const revision = '771d07b2cf';
        setUp(() {
          when(
            () => shorebirdFlutter.resolveFlutterRevision(any()),
          ).thenAnswer((_) async => revision);
        });

        test('uses specified flutter version to build '
            'and reverts to original flutter version', () async {
          when(() => releaser.buildReleaseArtifacts()).thenAnswer((_) async {
            // Ensure we're using the correct flutter version.
            expect(shorebirdEnv.flutterRevision, equals(revision));
            return File('');
          });

          await runWithOverrides(command.run);

          verify(
            () => shorebirdFlutter.installRevision(revision: revision),
          ).called(1);
        });

        group('when flutter version install fails', () {
          setUp(() {
            when(
              () => shorebirdFlutter.installRevision(
                revision: any(named: 'revision'),
              ),
            ).thenThrow(Exception('oops'));
          });

          test('exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(command.run),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => shorebirdFlutter.installRevision(revision: revision),
            ).called(1);
          });
        });
      });
    });

    group('when a patch signing public key is provided', () {
      const keyName = 'test-key-path.pem';
      group('when the key exists', () {
        setUp(() {
          final file = File(
            p.join(Directory.systemTemp.createTempSync().path, keyName),
          )..writeAsStringSync('KEY');
          when(
            () => argResults[CommonArguments.publicKeyArg.name],
          ).thenReturn(file.path);
        });

        test('completes successfully', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));
        });
      });
    });

    group('when no platform argument is provided', () {
      setUp(() {
        when(() => argResults['platforms']).thenReturn(const <String>[]);
      });

      test('fails and log the correct message', () async {
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.usage.code));

        verify(
          () => logger.err(
            '''No platforms were provided. Use the --platforms argument to provide one or more platforms''',
          ),
        ).called(1);
      });
    });

    group('assertArgsAreValid', () {
      test('calls releaser.assertArgsAreValid', () async {
        final releaser = MockReleaser();
        when(releaser.assertArgsAreValid).thenAnswer((_) async => {});
        await runWithOverrides(() => command.assertArgsAreValid(releaser));
        verify(releaser.assertArgsAreValid).called(1);
      });

      test('exits with code 64 if flutter version is not supported', () async {
        final releaser = MockReleaser();
        const releaseType = ReleaseType.android;
        when(() => releaser.releaseType).thenReturn(releaseType);
        when(releaser.assertArgsAreValid).thenAnswer((_) async => {});
        final laterFlutterVersion = Version(3, 23, 0);
        expect(laterFlutterVersion, greaterThan(flutterVersion));
        when(
          () => releaser.minimumFlutterVersion,
        ).thenReturn(laterFlutterVersion);
        await expectLater(
          () => runWithOverrides(() => command.assertArgsAreValid(releaser)),
          exitsWithCode(ExitCode.usage),
        );
        verify(
          () => logger.err('''
At least Flutter $laterFlutterVersion is required to release with `${releaseType.name}`.
For more information see: ${supportedFlutterVersionsUrl.toLink()}'''),
        ).called(1);
      });
    });
  });
}
