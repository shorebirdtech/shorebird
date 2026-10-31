import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/flutter_version_constraints.dart';
import 'package:shorebird_cli/src/json_output.dart';
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

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
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
      platforms: const {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );

    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
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
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          buildTraceSessionRef.overrideWith(
            () => BuildTraceSession(commandStartedAt: DateTime(2023)),
          ),
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
      artifactBuilder = MockArtifactBuilder();
      when(
        () => artifactBuilder.prepareBuildTrace(
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async {});
      when(artifactBuilder.writeBuildTraceSummary).thenReturn(null);
      cache = MockCache();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      releaser = MockReleaser();
      when(() => releaser.minimumFlutterVersion).thenReturn(Version(0, 0, 0));
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['platforms']).thenReturn(['android']);
      when(() => argResults['flutter-version']).thenReturn('latest');
      when(
        () => argResults[CommonArguments.patchSigningArg.name],
      ).thenReturn(true);
      when(() => argResults.wasParsed(any())).thenReturn(true);
      when(
        () => argResults.wasParsed(CommonArguments.publicKeyCmd.name),
      ).thenReturn(false);

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
        () => releaser.uploadSupplementArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => releaser.postReleaseInstructions,
      ).thenReturn(postReleaseInstructions);
      when(() => releaser.releaseType).thenReturn(ReleaseType.android);
      when(() => releaser.useObfuscation).thenReturn(false);
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
      when(() => shorebirdEnv.usesShorebirdCodePushPackage).thenReturn(true);

      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterRevision);
      when(
        () =>
            shorebirdFlutter.installRevision(revision: any(named: 'revision')),
      ).thenAnswer((_) async => {});
      when(
        () => shorebirdFlutter.fetchRemoteRefs(),
      ).thenAnswer((_) async {});
      when(
        () => shorebirdFlutter.resolveFlutterVersion(any()),
      ).thenAnswer((_) async => flutterVersion);

      when(
        () => shorebirdValidator.validateFlavors(
          flavorArg: any(named: 'flavorArg'),
          releasePlatform: any(named: 'releasePlatform'),
        ),
      ).thenAnswer((_) async => {});

      command = ReleaseCommand(resolveReleaser: (_) => releaser)
        ..testArgResults = argResults
        ..testRunner = usageRunner();
    });

    test('has non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    test('accepts a hidden --no-confirm and rejects --confirm', () {
      final parser = ReleaseCommand().argParser;
      expect(parser.options['no-confirm']!.hide, isTrue);
      expect(() => parser.parse(['--no-confirm']), returnsNormally);
      expect(
        () => parser.parse(['--confirm']),
        throwsA(isA<FormatException>()),
      );
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

      test('throws a usage exception naming the flag', () async {
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              '--public-key-path: no file found at /path/to/nonexistent/file.',
            ),
          ),
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
        platforms: const {
          ReleasePlatform.android: ReleasePlatformDetails(
            status: ReleaseStatus.active,
          ),
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
        () => shorebirdValidator.validateFlavors(
          flavorArg: null,
          releasePlatform: ReleasePlatform.android,
        ),
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
        () => releaser.uploadSupplementArtifact(
          appId: appId,
          releaseId: release.id,
        ),
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

      test('exits with an error saying the build failed', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithError(
            message: 'Failed to build release artifacts: Exception: oops',
            exitCode: ExitCode.software,
          ),
        );
      });

      test('passes on an exit that was already reported', () async {
        final exit = ProcessExit(ExitCode.unavailable.code);
        when(() => releaser.buildReleaseArtifacts()).thenThrow(exit);

        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(same(exit)),
        );
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

          test('exits with the fix recommendation as the hint', () async {
            await expectLater(
              () => runWithOverrides(command.run),
              exitsWithError(
                message: 'oops',
                hint: 'fix it',
                exitCode: ExitCode.software,
              ),
            );
          });
        });
      });
    });

    group('--json', () {
      Future<T> runJson<T>(Future<T> Function() body) => runScoped(
        body,
        values: {isJsonModeRef.overrideWith(() => true)},
      );

      setUp(() {
        when(
          () => codePushClientWrapper.maybeGetRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer((_) async => release);
      });

      // The release is already published by the time the refresh runs, so a
      // failure there must not turn a successful run into a failed one --
      // and getRelease, which this used to call, exits the process with a
      // message about publishing patches.
      test(
        'falls back to the release in hand when the refetch fails',
        () async {
          var calls = 0;
          when(
            () => codePushClientWrapper.maybeGetRelease(
              appId: any(named: 'appId'),
              releaseVersion: any(named: 'releaseVersion'),
            ),
          ).thenAnswer((_) async {
            // ensureVersionIsReleasable and getOrCreateRelease each look the
            // version up before the build; the refresh is the one after it.
            if (++calls <= 2) return release;
            throw ProcessExit(ExitCode.software.code);
          });

          final (:exitCode, :json) = await captureJson(
            () => runJson(() => runWithOverrides(command.run)),
          );

          expect(exitCode, equals(ExitCode.success.code));
          expect(json['status'], equals('success'));
          expect(
            (json['data'] as Map<String, dynamic>)['releases'],
            equals([release.toJson()]),
          );
        },
      );

      test('emits the published release, re-fetched after finalize', () async {
        final finalized = Release(
          id: release.id,
          appId: release.appId,
          version: release.version,
          flutterRevision: release.flutterRevision,
          displayName: release.displayName,
          platforms: const {
            ReleasePlatform.android: ReleasePlatformDetails(
              status: ReleaseStatus.active,
            ),
          },
          createdAt: release.createdAt,
          updatedAt: release.updatedAt,
        );
        when(
          () => codePushClientWrapper.maybeGetRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer((_) async => finalized);

        final (:exitCode, :json) = await captureJson(
          () => runJson(() => runWithOverrides(command.run)),
        );

        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], equals('success'));
        expect(
          json['data'],
          equals({
            'app_id': appId,
            'platforms': ['android'],
            'releases': [finalized.toJson()],
          }),
        );
      });

      test('emits nothing but the envelope on stdout', () async {
        // Human progress lines are still logged; the runner routes them to
        // stderr in JSON mode. Here the logger is a mock, so the check is
        // that the command itself writes only the envelope.
        await captureJson(
          () => runJson(() => runWithOverrides(command.run)),
        );
      });

      group('with --dry-run', () {
        setUp(() {
          when(() => argResults['dry-run']).thenReturn(true);
        });

        test('emits what would have been released', () async {
          final captured = <String>[];
          await expectLater(
            captureStdout(
              () => runJson(() => runWithOverrides(command.run)),
              captured: captured,
            ),
            exitsWithCode(ExitCode.success),
          );

          expect(captured, hasLength(1));
          final envelope = jsonDecode(captured.single) as Map<String, dynamic>;
          expect(envelope['status'], equals('success'));
          expect(
            envelope['data'],
            equals({
              'dry_run': true,
              'app_id': appId,
              'platform': 'android',
              'release_version': release.version,
              'flutter_revision': flutterRevision,
            }),
          );
          verifyNever(() => logger.info('No issues detected.'));
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
          () => shorebirdValidator.validateFlavors(
            flavorArg: flavor,
            releasePlatform: ReleasePlatform.android,
          ),
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

      group('when flavor validation fails', () {
        setUp(() {
          when(
            () => shorebirdValidator.validateFlavors(
              flavorArg: any(named: 'flavorArg'),
              releasePlatform: any(named: 'releasePlatform'),
            ),
          ).thenThrow(
            ValidationFailedException(
              message: 'Flavors are not supported on this platform.',
            ),
          );
        });

        test('exits with code 78 (config)', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.config),
          );
        });

        test('carries the flavor failure for the runner to report as '
            'precondition_failed', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            throwsA(
              isA<PreconditionFailedExit>().having(
                (e) => e.failure.message,
                'failure.message',
                'Flavors are not supported on this platform.',
              ),
            ),
          );
        });
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
            platforms: const {},
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

        test(
          'exits with an error naming the existing release Flutter',
          () async {
            await expectLater(
              () => runWithOverrides(command.run),
              exitsWithError(
                message: allOf(
                  startsWith('Release $releaseVersion was built with Flutter'),
                  endsWith(
                    'All platforms of a release must use the same Flutter.',
                  ),
                ),
                hint: startsWith('Re-run with --flutter-version=different,'),
                exitCode: ExitCode.software,
              ),
            );
          },
        );
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

    group('when flutter-version is provided', () {
      const flutterVersion = '3.16.3';
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn(flutterVersion);
      });

      test('fetches remote refs before resolving', () async {
        const revision = '771d07b2cf';
        when(
          () => shorebirdFlutter.resolveFlutterRevision(any()),
        ).thenAnswer((_) async => revision);

        await runWithOverrides(command.run);

        verify(() => shorebirdFlutter.fetchRemoteRefs()).called(1);
      });

      group('when unable to determine flutter revision', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => shorebirdFlutter.resolveFlutterRevision(any()),
          ).thenThrow(exception);
        });

        test('exits with an error saying the revision is unknown', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithError(
              message:
                  'Unable to determine the revision for Flutter '
                  '$flutterVersion: $exception',
              hint: 'Run: shorebird flutter versions list',
              exitCode: ExitCode.software,
            ),
          );
        });
      });

      group('when flutter version is not supported', () {
        setUp(() {
          when(
            () => shorebirdFlutter.resolveFlutterRevision(any()),
          ).thenAnswer((_) async => null);
        });

        test('exits with an error saying the version is unavailable', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithError(
              message: startsWith(
                'Flutter $flutterVersion is not available to Shorebird.',
              ),
              hint: 'Run: shorebird flutter versions list',
              exitCode: ExitCode.software,
            ),
          );
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

    /// Shared expectations for the `--flutter-version` values that ask the
    /// user's toolchain which Flutter version to build with.
    void testFlutterVersionAlias({
      required String arg,
      required String versionCommand,
      required Future<String?> Function() Function() getVersion,
    }) {
      group('when flutter-version is "$arg"', () {
        const reportedVersion = '3.32.4';
        const revision = '771d07b2cf';

        setUp(() {
          when(() => argResults['flutter-version']).thenReturn(arg);
          when(
            () => shorebirdFlutter.resolveFlutterRevision(any()),
          ).thenAnswer((_) async => revision);
        });

        test('builds with the Shorebird revision for the reported '
            'version', () async {
          when(getVersion()).thenAnswer((_) async => reportedVersion);

          await runWithOverrides(command.run);

          // The reported version is looked up like any other version, so we
          // still build with Shorebird's Flutter fork rather than the user's.
          verify(
            () => shorebirdFlutter.resolveFlutterRevision(reportedVersion),
          ).called(1);
          verify(
            () => shorebirdFlutter.installRevision(revision: revision),
          ).called(1);
          verify(
            () => logger.info(
              'Using Flutter $reportedVersion, as reported by '
              '`$versionCommand`.',
            ),
          ).called(1);
        });

        test('only asks for the version once', () async {
          when(getVersion()).thenAnswer((_) async => reportedVersion);

          await runWithOverrides(command.run);

          verify(getVersion()).called(1);
        });

        group('when the version lookup fails', () {
          final exception = Exception('oops');
          setUp(() {
            when(getVersion()).thenThrow(exception);
          });

          test('exits with an error saying the lookup failed', () async {
            await expectLater(
              () => runWithOverrides(command.run),
              exitsWithError(
                message:
                    'Unable to determine the Flutter version from '
                    '`$versionCommand`: $exception',
                hint:
                    'Pass a version with --flutter-version=<version> instead. '
                    'Run: shorebird flutter versions list',
                exitCode: ExitCode.software,
              ),
            );
          });
        });

        group('when the version cannot be parsed', () {
          setUp(() {
            when(getVersion()).thenAnswer((_) async => null);
          });

          test('exits with an error when the version is unparsable', () async {
            await expectLater(
              () => runWithOverrides(command.run),
              exitsWithError(
                message:
                    'Unable to parse a Flutter version from the output of '
                    '`$versionCommand`.',
                hint:
                    'Pass a version with --flutter-version=<version> instead. '
                    'Run: shorebird flutter versions list',
                exitCode: ExitCode.software,
              ),
            );
          });
        });
      });
    }

    testFlutterVersionAlias(
      arg: 'system',
      versionCommand: 'flutter --version',
      getVersion: () => shorebirdFlutter.getSystemVersion,
    );

    testFlutterVersionAlias(
      arg: 'fvm',
      versionCommand: 'fvm',
      getVersion: () => shorebirdFlutter.getFvmVersion,
    );

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

    group('patch_verification', () {
      const brokenEngineRevision = '6eae37c3bd60906cfaa3b026b3271b896a76e46f';
      const goodEngineRevision = '145c457f310dc800caa96f163cfde167df18f0da';

      void setUpYaml(PatchVerification? patchVerification) {
        when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
          ShorebirdYaml(appId: appId, patchVerification: patchVerification),
        );
      }

      group('when install_only is set on an engine where it is broken', () {
        setUp(() {
          setUpYaml(PatchVerification.installOnly);
          when(
            () => shorebirdEnv.shorebirdEngineRevision,
          ).thenReturn(brokenEngineRevision);
        });

        test('refuses the release before building', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            throwsA(
              isA<PreconditionFailedExit>()
                  .having((e) => e.exitCode, 'exitCode', ExitCode.config.code)
                  .having(
                    (e) => e.failure.message,
                    'failure.message',
                    contains('does not check patch signatures'),
                  ),
            ),
          );
          verify(
            () => logger.err(
              any(that: contains('`patch_verification: install_only`')),
            ),
          ).called(1);
          verify(
            () => logger.info(any(that: contains('--flutter-version=3.41.8'))),
          ).called(1);
          verifyNever(() => releaser.buildReleaseArtifacts());
        });
      });

      group('when install_only is set on an engine where it works', () {
        setUp(() {
          setUpYaml(PatchVerification.installOnly);
          when(
            () => shorebirdEnv.shorebirdEngineRevision,
          ).thenReturn(goodEngineRevision);
        });

        test('releases', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));
        });
      });

      group('when strict is set on an engine where install_only is broken', () {
        setUp(() {
          setUpYaml(PatchVerification.strict);
          when(
            () => shorebirdEnv.shorebirdEngineRevision,
          ).thenReturn(brokenEngineRevision);
        });

        test('releases', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));
        });
      });
    });

    group('when no platform argument is provided', () {
      setUp(() {
        when(() => argResults['platforms']).thenReturn(const <String>[]);
        command.testRunner = usageRunner();
      });

      test('throws a usage exception listing the valid platforms', () async {
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              '''
No platform was provided.
Valid platforms: aar, android, ios, ios-framework, linux, macos, windows''',
            ),
          ),
        );
      });
    });

    group('when the platform argument is invalid', () {
      setUp(() {
        when(() => argResults.wasParsed('platforms')).thenReturn(false);
        when(() => argResults.arguments).thenReturn(['list']);
        when(() => argResults.rest).thenReturn(['list']);
        command.testRunner = usageRunner(commands: {});
      });

      test('throws a usage exception without a subcommand hint', () async {
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              '''
Invalid platform: "list".
Valid platforms: aar, android, ios, ios-framework, linux, macos, windows''',
            ),
          ),
        );
      });
    });

    group('when a version is given as a positional', () {
      void stubArgs(List<String> args) {
        when(() => argResults.wasParsed('platforms')).thenReturn(false);
        when(() => argResults.arguments).thenReturn(args);
        when(() => argResults.rest).thenReturn(args);
      }

      setUp(() {
        command.testRunner = usageRunner();
      });

      test('suggests --build-name and --build-number for android', () async {
        stubArgs(['android', '1.0.0+1']);
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              '''
Unexpected argument: "1.0.0+1".
Did you mean --build-name=1.0.0 --build-number=1?''',
            ),
          ),
        );
      });

      test('suggests --build-name alone without a build number', () async {
        stubArgs(['android', '1.0.0']);
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              '''
Unexpected argument: "1.0.0".
Did you mean --build-name=1.0.0?''',
            ),
          ),
        );
      });

      test('suggests --release-version for aar', () async {
        stubArgs(['aar', '1.0.0+1']);
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              '''
Unexpected argument: "1.0.0+1".
Did you mean --release-version=1.0.0+1?''',
            ),
          ),
        );
      });

      test('suggests --release-version for ios-framework', () async {
        stubArgs(['ios-framework', '1.0.0+1']);
        await expectLater(
          runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('--release-version=1.0.0+1'),
            ),
          ),
        );
      });
    });

    group('when a .dart target is given as a positional', () {
      setUp(() {
        when(() => argResults.wasParsed('platforms')).thenReturn(false);
        when(() => argResults.wasParsed('target')).thenReturn(false);
        when(
          () => argResults.arguments,
        ).thenReturn(['android', 'lib/main_prod.dart']);
        when(
          () => argResults.rest,
        ).thenReturn(['android', 'lib/main_prod.dart']);
        command.testRunner = usageRunner();
      });

      test('uses it as the target and says so', () {
        expect(
          runWithOverrides(() => command.target),
          equals('lib/main_prod.dart'),
        );
        verify(
          () => logger.info(
            'Using lib/main_prod.dart as the target '
            '(--target lib/main_prod.dart).',
          ),
        ).called(1);
      });

      test('throws a usage exception when --target is also given', () {
        when(() => argResults.wasParsed('target')).thenReturn(true);
        when(() => argResults['target']).thenReturn('lib/main.dart');
        expect(
          () => runWithOverrides(() => command.target),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              'Both --target lib/main.dart and the positional '
                  'lib/main_prod.dart name a target. Pass only one.',
            ),
          ),
        );
      });
    });

    group('--patch-signing', () {
      test('is on by default', () {
        expect(
          command.argParser.parse([])[CommonArguments.patchSigningArg.name],
          isTrue,
        );
      });

      test('is turned off by --no-patch-signing', () {
        expect(
          command.argParser.parse([
            '--no-patch-signing',
          ])[CommonArguments.patchSigningArg.name],
          isFalse,
        );
      });
    });

    group('printReleaseSummary', () {
      Future<void> printSummary(ReleaseSigningMode mode) => runWithOverrides(
        () => command.printReleaseSummary(
          app: appMetadata,
          releaseVersion: '1.0.0+1',
          flutterVersion: 'deadbeef',
          releasePlatform: ReleasePlatform.android,
          signing: ArtifactSigningRequest(mode: mode),
        ),
      );

      for (final (mode, description) in [
        (ReleaseSigningMode.managed, 'Shorebird-managed key'),
        (ReleaseSigningMode.customer, 'your key'),
      ]) {
        test('describes $mode patch signing', () async {
          await printSummary(mode);

          verify(
            () => logger.info(
              any(
                that: contains(
                  '🔏 Patch Signing: ${lightCyan.wrap(description)}',
                ),
              ),
            ),
          ).called(1);
        });
      }

      test('says patch signing is off for an unsigned release', () async {
        await printSummary(ReleaseSigningMode.unsigned);

        verify(
          () => logger.info(
            any(that: contains('🔏 Patch Signing: ${yellow.wrap('off')}')),
          ),
        ).called(1);
      });
    });

    group('assertArgsAreValid', () {
      test('calls releaser.assertArgsAreValid', () async {
        final releaser = MockReleaser();
        when(() => releaser.minimumFlutterVersion).thenReturn(Version(0, 0, 0));
        when(() => releaser.useObfuscation).thenReturn(false);
        when(releaser.assertArgsAreValid).thenAnswer((_) async => {});
        await runWithOverrides(() => command.assertArgsAreValid(releaser));
        verify(releaser.assertArgsAreValid).called(1);
      });

      group('when patch_verification is set', () {
        late Releaser releaser;

        setUp(() {
          when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
            const ShorebirdYaml(
              appId: appId,
              patchVerification: PatchVerification.strict,
            ),
          );
          when(
            () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
          ).thenReturn(false);
          releaser = MockReleaser();
          when(
            () => releaser.minimumFlutterVersion,
          ).thenReturn(Version(0, 0, 0));
          when(() => releaser.useObfuscation).thenReturn(false);
          when(releaser.assertArgsAreValid).thenAnswer((_) async => {});
        });

        test('warns with --no-patch-signing', () async {
          when(
            () => argResults[CommonArguments.patchSigningArg.name],
          ).thenReturn(false);
          await runWithOverrides(() => command.assertArgsAreValid(releaser));
          verify(
            () => logger.warn(
              'patch_verification is set in shorebird.yaml but '
              '--no-patch-signing builds a release whose patches are '
              'unsigned.\n'
              'patch_verification configuration will have no effect.',
            ),
          ).called(1);
        });

        test('does not warn when patches are signed', () async {
          await runWithOverrides(() => command.assertArgsAreValid(releaser));
          verifyNever(() => logger.warn(any()));
        });
      });

      test('rejects --no-patch-signing with a public key', () async {
        when(
          () => argResults[CommonArguments.patchSigningArg.name],
        ).thenReturn(false);
        when(
          () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
        ).thenReturn(true);
        when(
          () => argResults[CommonArguments.publicKeyArg.name],
        ).thenReturn(null);
        final releaser = MockReleaser();
        await expectLater(
          () => runWithOverrides(() => command.assertArgsAreValid(releaser)),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              '--no-patch-signing builds a release whose patches are '
                  'unsigned, so it cannot be combined with '
                  '--public-key-path or --public-key-cmd.',
            ),
          ),
        );
      });

      test('exits with an error if flutter version is not supported', () async {
        final releaser = MockReleaser();
        when(
          () => releaser.releaseType,
        ).thenReturn(ReleaseType.iosFramework);
        when(releaser.assertArgsAreValid).thenAnswer((_) async => {});
        final laterFlutterVersion = Version(3, 23, 0);
        expect(laterFlutterVersion, greaterThan(flutterVersion));
        when(
          () => releaser.minimumFlutterVersion,
        ).thenReturn(laterFlutterVersion);
        await expectLater(
          () => runWithOverrides(() => command.assertArgsAreValid(releaser)),
          exitsWithError(
            message:
                'At least Flutter $laterFlutterVersion is required to release '
                'with `ios-framework` (see $supportedFlutterVersionsUrl).',
            hint: isNull,
          ),
        );
      });

      test(
        'suggests dropping --flutter-version when it names an old Flutter',
        () async {
          final releaser = MockReleaser();
          when(
            () => releaser.releaseType,
          ).thenReturn(ReleaseType.iosFramework);
          when(releaser.assertArgsAreValid).thenAnswer((_) async => {});
          when(() => argResults['flutter-version']).thenReturn('3.22.0');
          final laterFlutterVersion = Version(3, 23, 0);
          expect(laterFlutterVersion, greaterThan(flutterVersion));
          when(
            () => releaser.minimumFlutterVersion,
          ).thenReturn(laterFlutterVersion);
          await expectLater(
            () => runWithOverrides(() => command.assertArgsAreValid(releaser)),
            exitsWithError(
              message:
                  'At least Flutter $laterFlutterVersion is required to '
                  'release with `ios-framework` '
                  '(see $supportedFlutterVersionsUrl).',
              hint:
                  'Drop --flutter-version to release with the latest supported '
                  'Flutter. Run: shorebird release ios-framework '
                  '--release-version=$releaseVersionExample',
            ),
          );
        },
      );

      group('when obfuscating below the obfuscation map floor', () {
        late MockReleaser releaser;
        final oldFlutterVersion = Version(3, 38, 9);

        setUp(() {
          expect(oldFlutterVersion, lessThan(minimumObfuscationFlutterVersion));
          releaser = MockReleaser();
          when(() => releaser.useObfuscation).thenReturn(true);
          when(
            () => releaser.minimumFlutterVersion,
          ).thenReturn(Version(0, 0, 0));
          when(releaser.assertArgsAreValid).thenAnswer((_) async => {});
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => oldFlutterVersion);
        });

        test('exits for iOS, whose patches link against the release', () async {
          when(() => releaser.releaseType).thenReturn(ReleaseType.ios);
          await expectLater(
            () => runWithOverrides(() => command.assertArgsAreValid(releaser)),
            exitsWithError(
              message:
                  'Obfuscation on iOS requires Flutter '
                  '$minimumObfuscationFlutterVersion or later '
                  '(current: $oldFlutterVersion).',
              hint:
                  'Run: shorebird release ios --obfuscate '
                  '--flutter-version=$minimumObfuscationFlutterVersion',
              exitCode: ExitCode.unavailable,
            ),
          );
        });

        test('allows Android, whose patches are complete snapshots', () async {
          when(() => releaser.releaseType).thenReturn(ReleaseType.android);
          await runWithOverrides(() => command.assertArgsAreValid(releaser));
          verify(releaser.assertArgsAreValid).called(1);
        });

        test('checks the --flutter-version target, not the CLI pin', () async {
          when(() => releaser.releaseType).thenReturn(ReleaseType.ios);
          when(() => argResults['flutter-version']).thenReturn('3.38.9');
          await expectLater(
            () => runWithOverrides(() => command.assertArgsAreValid(releaser)),
            exitsWithCode(ExitCode.unavailable),
          );
          verify(() => shorebirdFlutter.resolveFlutterVersion('3.38.9'));
        });

        test('checks the CLI pin when no --flutter-version is given', () async {
          when(() => releaser.releaseType).thenReturn(ReleaseType.ios);
          await expectLater(
            () => runWithOverrides(() => command.assertArgsAreValid(releaser)),
            exitsWithCode(ExitCode.unavailable),
          );
          verify(
            () => shorebirdFlutter.resolveFlutterVersion(flutterRevision),
          );
        });
      });
    });

    group('finalizeRelease', () {
      group('when a public key is provided', () {
        setUp(() {
          when(
            () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
          ).thenReturn(true);
        });

        test('completes successfully', () async {
          await runWithOverrides(
            () => command.finalizeRelease(
              release: release,
              releaser: releaser,
            ),
          );
          verify(
            () => releaser.updatedReleaseMetadata(
              any(
                that: isA<UpdateReleaseMetadata>().having(
                  (metadata) => metadata.includesPublicKey,
                  'includesPublicKey',
                  isTrue,
                ),
              ),
            ),
          ).called(1);
        });
      });

      group('when no public key is provided', () {
        setUp(() {
          when(
            () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
          ).thenReturn(false);
        });

        test('completes successfully', () async {
          await runWithOverrides(
            () => command.finalizeRelease(
              release: release,
              releaser: releaser,
            ),
          );
          verify(
            () => releaser.updatedReleaseMetadata(
              any(
                that: isA<UpdateReleaseMetadata>().having(
                  (metadata) => metadata.includesPublicKey,
                  'includesPublicKey',
                  isFalse,
                ),
              ),
            ),
          ).called(1);
        });
      });
    });
  });

  test('ReleaseCommand accepts flutter build options without --', () {
    final results = ReleaseCommand().argParser.parse([
      'android',
      '--no-tree-shake-icons',
      '-D',
      'FOO=a,b',
      '-P',
      'key=value',
    ]);
    expect(results.forwardedArgs, [
      '--dart-define=FOO=a,b',
      '--android-project-arg=key=value',
      '--no-tree-shake-icons',
    ]);
  });
}
