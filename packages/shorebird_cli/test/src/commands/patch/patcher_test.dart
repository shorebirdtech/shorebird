import 'dart:io';

import 'package:archive/archive.dart' show ArchiveException;
import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/rollout_schedule.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/symbols/sbsymbols.dart';
import 'package:shorebird_cli/src/symbols/symbol_extractor.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(Patcher, () {
    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(DeploymentTrack.stable);
      registerFallbackValue(FakeFile());
      registerFallbackValue(FakeDirectory());
      registerFallbackValue(SymbolImage.release);
      registerFallbackValue(SymbolsFormat.sbsymbols);
    });

    group('linkPercentage', () {
      test('defaults to null', () {
        expect(
          _TestPatcher(
            argParser: MockArgParser(),
            argResults: MockArgResults(),
            flavor: null,
            target: null,
          ).linkPercentage,
          isNull,
        );
      });
    });

    group('lowLinkPercentageWarning', () {
      test('truncates the percentage and links to the performance docs', () {
        final warning = Patcher.lowLinkPercentageWarning(12.345678901234567);
        expect(warning, contains('share 12.3% of Dart code'));
        expect(warning, contains(linkPercentageUrl));
      });

      test('does not round a value just under 20% up to 20.0%', () {
        final warning = Patcher.lowLinkPercentageWarning(19.97);
        expect(warning, contains('share 19.9% of Dart code'));
      });
    });

    group('formatLinkPercentage', () {
      test('shows one decimal place, truncated', () {
        expect(Patcher.formatLinkPercentage(62.1337), equals('62.1'));
        expect(Patcher.formatLinkPercentage(19.97), equals('19.9'));
        expect(Patcher.formatLinkPercentage(19.9), equals('19.9'));
        expect(Patcher.formatLinkPercentage(20), equals('20.0'));
      });
    });

    group('supplementaryReleaseArtifactArch', () {
      test('defaults to null', () {
        expect(
          _TestPatcher(
            argParser: MockArgParser(),
            argResults: MockArgResults(),
            flavor: null,
            target: null,
          ).supplementaryReleaseArtifactArch,
          isNull,
        );
      });
    });

    group('obfuscationGenSnapshotArgs', () {
      late ArgResults argResults;
      late _TestPatcher patcher;

      setUp(() {
        argResults = MockArgResults();
        when(
          () => argResults.wasParsed(CommonArguments.splitDebugInfoArg.name),
        ).thenReturn(true);
        when(
          () => argResults[CommonArguments.splitDebugInfoArg.name],
        ).thenReturn('symbols');
        patcher = _TestPatcher(
          argParser: MockArgParser(),
          argResults: argResults,
          flavor: null,
          target: null,
        );
      });

      test('is empty when not obfuscating', () {
        expect(patcher.obfuscationGenSnapshotArgs, isEmpty);
      });

      test('loads the obfuscation map when one is set', () {
        patcher
          ..obfuscate = true
          ..obfuscationMapPath = 'map.json';
        expect(
          patcher.obfuscationGenSnapshotArgs,
          equals([
            '--obfuscate',
            '--load-obfuscation-map=map.json',
          ]),
        );
      });

      test('obfuscates without a map when none is set', () {
        patcher.obfuscate = true;
        expect(
          patcher.obfuscationGenSnapshotArgs,
          equals(['--obfuscate']),
        );
      });
    });

    group('ddMaxBytes', () {
      late ArgResults argResults;
      late _TestPatcher patcher;

      setUp(() {
        argResults = MockArgResults();
        patcher = _TestPatcher(
          argParser: MockArgParser(),
          argResults: argResults,
          flavor: null,
          target: null,
        );
      });

      test('is null when --dd-max-bytes is not given', () {
        expect(patcher.ddMaxBytes, isNull);
      });

      test('is the --dd-max-bytes value', () {
        when(
          () => argResults[CommonArguments.ddMaxBytesArg.name],
        ).thenReturn('4096');
        expect(patcher.ddMaxBytes, equals(4096));
      });

      test('passes 0 through so the linker disables DD', () {
        when(
          () => argResults[CommonArguments.ddMaxBytesArg.name],
        ).thenReturn('0');
        expect(patcher.ddMaxBytes, equals(0));
      });
    });

    group('assertArgsAreValid', () {
      test('has no validations by default', () {
        expect(
          _TestPatcher(
            argParser: MockArgParser(),
            argResults: MockArgResults(),
            flavor: null,
            target: null,
          ).assertArgsAreValid,
          returnsNormally,
        );
      });
    });

    group('buildNameAndNumberArgsFromReleaseVersion', () {
      late ArgResults argResults;
      setUp(() {
        argResults = MockArgResults();
        when(() => argResults.options).thenReturn([]);
      });

      group('when releaseVersion is not specified', () {
        test('returns an empty list', () {
          expect(
            _TestPatcher(
              argParser: MockArgParser(),
              argResults: MockArgResults(),
              flavor: null,
              target: null,
            ).buildNameAndNumberArgsFromReleaseVersion(null),
            isEmpty,
          );
        });
      });

      group('when an invalid --release-version is specified', () {
        test('returns an empty list', () {
          expect(
            _TestPatcher(
              argParser: MockArgParser(),
              argResults: argResults,
              flavor: null,
              target: null,
            ).buildNameAndNumberArgsFromReleaseVersion('invalid'),
            isEmpty,
          );
        });
      });

      group('when a valid --release-version is specified', () {
        group('when --build-name is specified', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['--build-name=foo']);
          });

          test('returns an empty list', () {
            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              isEmpty,
            );
          });
        });

        group('when --build-number is specified', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['--build-number=42']);
          });

          test('returns an empty list', () {
            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              isEmpty,
            );
          });
        });

        group('when neither --build-name nor --build-number are specified', () {
          test('returns --build-name and --build-number', () {
            when(() => argResults.rest).thenReturn([]);

            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              equals(['--build-name=1.2.3', '--build-number=4']),
            );
          });
        });

        group('when build-name and build-number were parsed as options', () {
          setUp(() {
            when(
              () => argResults.wasParsed(CommonArguments.buildNameArg.name),
            ).thenReturn(true);
            when(
              () => argResults.wasParsed(CommonArguments.buildNumberArg.name),
            ).thenReturn(true);
            when(() => argResults.options).thenReturn([
              'release-version',
              'build-name',
              'build-number',
              'platforms',
            ]);
          });

          test('returns an empty list', () {
            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              isEmpty,
            );
          });
        });
      });
    });

    group('uploadPatchArtifacts', () {
      test('calls codePushClientWrapper.publishPatch '
          'with correct args', () async {
        final args = MockArgResults();
        final patcher = _TestPatcher(
          argParser: MockArgParser(),
          argResults: args,
          flavor: null,
          target: null,
          releaseType: ReleaseType.android,
        );
        const appId = 'test_app_id';
        const releaseId = 42;
        const metadata = <String, String>{};
        const artifacts = <Arch, PatchArtifactBundle>{};
        const track = DeploymentTrack.stable;
        final codePushClientWrapper = MockCodePushClientWrapper();
        when(
          () => codePushClientWrapper.publishPatch(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            metadata: any(named: 'metadata'),
            platform: any(named: 'platform'),
            track: any(named: 'track'),
            patchArtifactBundles: any(named: 'patchArtifactBundles'),
            rolloutPercentage: any(named: 'rolloutPercentage'),
          ),
        ).thenAnswer((_) async => const CreatePatchResponse(id: 1, number: 1));
        await runScoped(
          () async {
            await patcher.uploadPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              metadata: metadata,
              artifacts: artifacts,
              track: track,
              rolloutPercentage: 10,
            );
          },
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          },
        );
        verify(
          () => codePushClientWrapper.publishPatch(
            appId: appId,
            releaseId: releaseId,
            metadata: metadata,
            platform: ReleaseType.android.releasePlatform,
            track: track,
            patchArtifactBundles: artifacts,
            rolloutPercentage: 10,
          ),
        ).called(1);
      });

      test('passes the rollout schedule through', () async {
        final patcher = _TestPatcher(
          argParser: MockArgParser(),
          argResults: MockArgResults(),
          flavor: null,
          target: null,
          releaseType: ReleaseType.android,
        );
        const schedule = RolloutSchedule(
          steps: [
            RolloutStep(percentage: 1, durationMinutes: 240),
            RolloutStep(percentage: 100),
          ],
          pauseWeekends: true,
          timezone: 'America/New_York',
        );
        final codePushClientWrapper = MockCodePushClientWrapper();
        when(
          () => codePushClientWrapper.publishPatch(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            metadata: any(named: 'metadata'),
            platform: any(named: 'platform'),
            track: any(named: 'track'),
            patchArtifactBundles: any(named: 'patchArtifactBundles'),
            rolloutPercentage: any(named: 'rolloutPercentage'),
            rolloutSchedule: any(named: 'rolloutSchedule'),
          ),
        ).thenAnswer((_) async => const CreatePatchResponse(id: 1, number: 1));

        await runScoped(
          () => patcher.uploadPatchArtifacts(
            appId: 'test_app_id',
            releaseId: 42,
            metadata: const <String, String>{},
            artifacts: const <Arch, PatchArtifactBundle>{},
            track: DeploymentTrack.stable,
            rolloutSchedule: schedule,
          ),
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          },
        );

        verify(
          () => codePushClientWrapper.publishPatch(
            appId: 'test_app_id',
            releaseId: 42,
            metadata: const <String, String>{},
            platform: ReleaseType.android.releasePlatform,
            track: DeploymentTrack.stable,
            patchArtifactBundles: const <Arch, PatchArtifactBundle>{},
            rolloutSchedule: schedule,
          ),
        ).called(1);
      });
    });

    group('uploadSymbolArtifacts', () {
      const appId = 'test_app_id';
      const patchId = 7;

      late ArgResults argResults;
      late CodePushClientWrapper codePushClientWrapper;
      late Directory projectRoot;
      late ShorebirdEnv shorebirdEnv;
      late ShorebirdLogger logger;
      late SymbolExtractor symbolExtractor;
      late _TestPatcher patcher;

      R runWithOverrides<R>(R Function() body) => runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          symbolExtractorRef.overrideWith(() => symbolExtractor),
        },
      );

      File debugInfo([String name = 'app.test-arm64.symbols']) =>
          File(p.join(projectRoot.path, 'symbols', name))
            ..createSync(recursive: true)
            ..writeAsStringSync('debug info');

      setUp(() {
        argResults = MockArgResults();
        codePushClientWrapper = MockCodePushClientWrapper();
        projectRoot = Directory.systemTemp.createTempSync();
        shorebirdEnv = MockShorebirdEnv();
        logger = MockShorebirdLogger();
        symbolExtractor = MockSymbolExtractor();

        when(
          () => argResults.wasParsed(CommonArguments.splitDebugInfoArg.name),
        ).thenReturn(true);
        when(
          () => argResults[CommonArguments.splitDebugInfoArg.name],
        ).thenReturn('symbols');
        when(
          () => shorebirdEnv.getShorebirdProjectRoot(),
        ).thenReturn(projectRoot);
        when(
          () => symbolExtractor.writeIndex(
            debugInfo: any(named: 'debugInfo'),
            output: any(named: 'output'),
            image: any(named: 'image'),
          ),
        ).thenAnswer((invocation) {
          final output =
              invocation.namedArguments[const Symbol('output')] as File
                ..createSync(recursive: true)
                ..writeAsStringSync('an index');
          return output;
        });
        when(
          () => codePushClientWrapper.createPatchSymbols(
            appId: any(named: 'appId'),
            patchId: any(named: 'patchId'),
            platform: any(named: 'platform'),
            arch: any(named: 'arch'),
            format: any(named: 'format'),
            symbols: any(named: 'symbols'),
          ),
        ).thenAnswer((_) async {});

        patcher = _TestPatcher(
          argParser: ArgParser(),
          argResults: argResults,
          flavor: null,
          target: null,
          releaseType: ReleaseType.ios,
        )..crashReportingEnabled = true;
      });

      test(
        'extracts the index for built architectures and uploads only sbsymbols',
        () async {
          final symbols = debugInfo();
          debugInfo('app.test-x64.symbols');

          await runWithOverrides(
            () => patcher.uploadSymbolArtifacts(
              appId: appId,
              patchId: patchId,
              architectures: const [Arch.arm64],
            ),
          );

          verify(
            () => symbolExtractor.writeIndex(
              debugInfo: any(
                named: 'debugInfo',
                that: isA<File>().having((f) => f.path, 'path', symbols.path),
              ),
              output: any(
                named: 'output',
                that: isA<File>().having(
                  (f) => f.path,
                  'path',
                  p.setExtension(symbols.path, '.sbsymbols'),
                ),
              ),
              image: SymbolImage.vmcode,
            ),
          ).called(1);
          verify(
            () => codePushClientWrapper.createPatchSymbols(
              appId: appId,
              patchId: patchId,
              platform: ReleasePlatform.ios,
              arch: 'aarch64',
              format: SymbolsFormat.sbsymbols,
              symbols: any(named: 'symbols'),
            ),
          ).called(1);
          verifyNever(
            () => codePushClientWrapper.createPatchSymbols(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              platform: any(named: 'platform'),
              arch: 'x86_64',
              format: any(named: 'format'),
              symbols: any(named: 'symbols'),
            ),
          );
        },
      );

      test(
        'extracts and uploads nothing when crash reporting is off',
        () async {
          patcher.crashReportingEnabled = false;
          debugInfo();

          await runWithOverrides(
            () => patcher.uploadSymbolArtifacts(
              appId: appId,
              patchId: patchId,
              architectures: const [Arch.arm64],
            ),
          );

          verifyNever(
            () => symbolExtractor.writeIndex(
              debugInfo: any(named: 'debugInfo'),
              output: any(named: 'output'),
              image: any(named: 'image'),
            ),
          );
          verifyNever(
            () => codePushClientWrapper.createPatchSymbols(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              platform: any(named: 'platform'),
              arch: any(named: 'arch'),
              format: any(named: 'format'),
              symbols: any(named: 'symbols'),
            ),
          );
        },
      );

      group('when there is no index to extract', () {
        setUp(() {
          when(
            () => symbolExtractor.writeIndex(
              debugInfo: any(named: 'debugInfo'),
              output: any(named: 'output'),
              image: any(named: 'image'),
            ),
          ).thenReturn(null);
        });

        test('uploads nothing and says so at --verbose', () async {
          debugInfo();

          await runWithOverrides(
            () => patcher.uploadSymbolArtifacts(
              appId: appId,
              patchId: patchId,
              architectures: const [Arch.arm64],
            ),
          );

          verifyNever(
            () => codePushClientWrapper.createPatchSymbols(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              platform: any(named: 'platform'),
              arch: any(named: 'arch'),
              format: any(named: 'format'),
              symbols: any(named: 'symbols'),
            ),
          );
          verify(
            () => logger.detail(
              any(that: contains('No symbol index extracted from')),
            ),
          ).called(1);
        });
      });

      group('when the build wrote no symbols', () {
        test('uploads nothing when split-debug-info was not passed', () async {
          when(
            () => argResults.wasParsed(CommonArguments.splitDebugInfoArg.name),
          ).thenReturn(false);
          when(() => argResults.rest).thenReturn([]);

          await runWithOverrides(
            () => patcher.uploadSymbolArtifacts(
              appId: appId,
              patchId: patchId,
              architectures: const [Arch.arm64],
            ),
          );

          verifyNever(
            () => codePushClientWrapper.createPatchSymbols(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              platform: any(named: 'platform'),
              arch: any(named: 'arch'),
              format: any(named: 'format'),
              symbols: any(named: 'symbols'),
            ),
          );
        });

        test(
          'defaults debugInfoFileNames to empty and skips unnamed archs',
          () {
            patcher.testDebugInfoFileNames = null;
            expect(patcher.debugInfoFileNames, isEmpty);
            expect(
              runWithOverrides(
                () => patcher.debugInfoFiles(architectures: const [Arch.arm32]),
              ),
              isEmpty,
            );
          },
        );
      });
    });

    group('createDiffBundle', () {
      late ArtifactManager artifactManager;
      late Progress progress;
      late Directory tempDir;
      late File patchArtifact;
      late File diffFile;
      late _TestPatcher patcher;

      setUp(() {
        artifactManager = MockArtifactManager();
        progress = MockProgress();
        tempDir = Directory.systemTemp.createTempSync();
        patchArtifact = File(p.join(tempDir.path, 'libapp.so'))
          ..writeAsStringSync('patch');
        diffFile = File(p.join(tempDir.path, 'diff.patch'))
          ..writeAsStringSync('diff!');
        // No signing options passed, so signHash signs nothing.
        final argParser = ArgParser()
          ..addOption(CommonArguments.publicKeyArg.name)
          ..addOption(CommonArguments.privateKeyArg.name)
          ..addOption(CommonArguments.publicKeyCmd.name)
          ..addOption(CommonArguments.signCmd.name);
        patcher = _TestPatcher(
          argParser: argParser,
          argResults: argParser.parse([]),
          flavor: null,
          target: null,
        );
      });

      tearDown(() => tempDir.deleteSync(recursive: true));

      Future<PatchArtifactBundle> runWithOverrides(
        Future<PatchArtifactBundle> Function() body,
      ) {
        return runScoped(
          body,
          values: {artifactManagerRef.overrideWith(() => artifactManager)},
        );
      }

      test('diffs against the release and describes the patch', () async {
        when(
          () => artifactManager.createDiff(
            releaseArtifactPath: any(named: 'releaseArtifactPath'),
            patchArtifactPath: any(named: 'patchArtifactPath'),
          ),
        ).thenAnswer((_) async => diffFile.path);

        final bundle = await runWithOverrides(
          () => patcher.createDiffBundle(
            arch: Arch.arm64,
            releaseArtifactPath: 'release.so',
            patchArtifactPath: patchArtifact.path,
            progress: progress,
            podfileLockHash: 'podfile-lock-hash',
          ),
        );

        verify(
          () => artifactManager.createDiff(
            releaseArtifactPath: 'release.so',
            patchArtifactPath: patchArtifact.path,
          ),
        ).called(1);
        expect(bundle.arch, equals(Arch.arm64.arch));
        expect(bundle.path, equals(diffFile.path));
        // The hash is of the full patch artifact, not of the diff.
        expect(
          bundle.hash,
          equals(
            // sha256 of 'patch'
            'a4895eb44afc336fecbba6e520cd67e178dace0276655d102fceffa8e5f70570',
          ),
        );
        expect(bundle.size, equals(diffFile.lengthSync()));
        expect(bundle.hashSignature, isNull);
        expect(bundle.podfileLockHash, equals('podfile-lock-hash'));
        verifyNever(() => progress.fail(any()));
      });

      test('fails progress and exits when the diff fails', () async {
        when(
          () => artifactManager.createDiff(
            releaseArtifactPath: any(named: 'releaseArtifactPath'),
            patchArtifactPath: any(named: 'patchArtifactPath'),
          ),
        ).thenThrow(Exception('diff failed'));

        await expectLater(
          () => runWithOverrides(
            () => patcher.createDiffBundle(
              arch: Arch.x86_64,
              releaseArtifactPath: 'release.so',
              patchArtifactPath: patchArtifact.path,
              progress: progress,
            ),
          ),
          exitsWithError(
            message: 'Failed to create the patch diff: Exception: diff failed',
            exitCode: ExitCode.software,
          ),
        );
        verify(() => progress.fail()).called(1);
      });
    });

    group('damagedReleaseArtifactHint', () {
      test('names the release command for the platform', () {
        expect(
          damagedReleaseArtifactHint(ReleaseType.ios),
          equals(
            'Re-run to download it again. If this persists, the release '
            'artifact is damaged: create a new release and patch that one. '
            'Run: shorebird release ios',
          ),
        );
      });

      test('asks an add-to-app release for a new version', () {
        expect(
          damagedReleaseArtifactHint(ReleaseType.iosFramework),
          endsWith(
            'Run: shorebird release ios-framework '
            '--release-version=<new version>',
          ),
        );
      });
    });

    group('extractReleaseArtifact', () {
      late ArtifactManager artifactManager;
      late Progress progress;
      final zipFile = File('release.zip');
      final outputDirectory = Directory('out');

      setUp(() {
        artifactManager = MockArtifactManager();
        progress = MockProgress();
      });

      Future<void> runWithOverrides(Future<void> Function() body) {
        return runScoped(
          body,
          values: {artifactManagerRef.overrideWith(() => artifactManager)},
        );
      }

      test('extracts the artifact', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((_) async {});

        await runWithOverrides(
          () => extractReleaseArtifact(
            zipFile: zipFile,
            outputDirectory: outputDirectory,
            releaseType: ReleaseType.linux,
            progress: progress,
          ),
        );

        verify(
          () => artifactManager.extractZip(
            zipFile: zipFile,
            outputDirectory: outputDirectory,
          ),
        ).called(1);
        verifyNever(() => progress.fail(any()));
      });

      test('fails progress and exits when the artifact is damaged', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenThrow(
          ArchiveException('zip: end of central directory not found'),
        );

        await expectLater(
          () => runWithOverrides(
            () => extractReleaseArtifact(
              zipFile: zipFile,
              outputDirectory: outputDirectory,
              releaseType: ReleaseType.linux,
              progress: progress,
            ),
          ),
          exitsWithError(
            message:
                'The release artifact downloaded from Shorebird is damaged: '
                'zip: end of central directory not found',
            hint: damagedReleaseArtifactHint(ReleaseType.linux),
            exitCode: ExitCode.software,
          ),
        );
        verify(() => progress.fail()).called(1);
      });

      test('exits without a progress to fail', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenThrow(ArchiveException('zip: crc32 mismatch'));

        await expectLater(
          () => runWithOverrides(
            () => extractReleaseArtifact(
              zipFile: zipFile,
              outputDirectory: outputDirectory,
              releaseType: ReleaseType.linux,
            ),
          ),
          exitsWithError(
            message:
                'The release artifact downloaded from Shorebird is damaged: '
                'zip: crc32 mismatch',
            exitCode: ExitCode.software,
          ),
        );
      });
    });

    group('getEncodedPublicKey', () {
      late CodeSigner codeSigner;

      setUp(() {
        codeSigner = MockCodeSigner();
        when(
          () => codeSigner.base64PublicKeyFromPem(any()),
        ).thenReturn('encoded-key');
      });

      test("returns the release's managed key when it has one", () async {
        final argParser = ArgParser()
          ..addOption(CommonArguments.publicKeyArg.name)
          ..addOption(CommonArguments.publicKeyCmd.name);
        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argParser.parse([]),
          flavor: null,
          target: null,
        )..releaseManagedPublicKeyPem = 'managed-pem';

        final key = await runScoped(
          patcher.getEncodedPublicKey,
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );

        expect(key, equals('encoded-key'));
        verify(
          () => codeSigner.base64PublicKeyFromPem('managed-pem'),
        ).called(1);
      });

      test('returns null when no key is configured', () async {
        final argParser = ArgParser()
          ..addOption(CommonArguments.publicKeyArg.name)
          ..addOption(CommonArguments.publicKeyCmd.name);
        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argParser.parse([]),
          flavor: null,
          target: null,
        );

        final key = await runScoped(
          patcher.getEncodedPublicKey,
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );

        expect(key, isNull);
      });
    });

    group('signHash', () {
      final cryptoFixturesBasePath = p.join(fixturesDirectory, 'crypto');
      final privateKeyFile = File(
        p.join(cryptoFixturesBasePath, 'private.pem'),
      );

      late ArgParser argParser;
      late ArgResults argResults;
      late CodeSigner codeSigner;
      late ShorebirdLogger logger;
      late File publicKeyTempFile;

      setUp(() {
        argParser = ArgParser()
          ..addOption(CommonArguments.publicKeyArg.name)
          ..addOption(CommonArguments.privateKeyArg.name)
          ..addOption(CommonArguments.publicKeyCmd.name)
          ..addOption(CommonArguments.signCmd.name);
        codeSigner = MockCodeSigner();
        when(
          () => codeSigner.canonicalPublicKeyPem(any()),
        ).thenAnswer(
          (invocation) => invocation.positionalArguments.single as String,
        );
        logger = MockShorebirdLogger();
        publicKeyTempFile = File(
          p.join(
            Directory.systemTemp.createTempSync().path,
            'public.pem',
          ),
        )..writeAsStringSync('fake-public-key-pem');
      });

      test('returns null when no signing is configured', () async {
        argResults = argParser.parse([]);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, isNull);
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test('returns signature from file-based signing', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyArg.name}=${publicKeyTempFile.path}',
          '--${CommonArguments.privateKeyArg.name}=${privateKeyFile.path}',
        ]);

        when(
          () => codeSigner.sign(
            message: any(named: 'message'),
            privateKeyPemFile: any(named: 'privateKeyPemFile'),
          ),
        ).thenReturn('file-signature');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(true);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, equals('file-signature'));
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test(
        'exits with an error when signer present but no public key',
        () async {
          argResults = argParser.parse([
            '--${CommonArguments.privateKeyArg.name}=${privateKeyFile.path}',
          ]);

          when(
            () => codeSigner.sign(
              message: any(named: 'message'),
              privateKeyPemFile: any(named: 'privateKeyPemFile'),
            ),
          ).thenReturn('file-signature');

          final patcher = _TestPatcher(
            argParser: argParser,
            argResults: argResults,
            flavor: null,
            target: null,
          );

          await runScoped(
            () async {
              await expectLater(
                () => patcher.signHash('test-hash'),
                exitsWithError(
                  message: 'A public key is required for code signing.',
                  hint: 'Pass --public-key-path or --public-key-cmd.',
                ),
              );
            },
            values: {
              codeSignerRef.overrideWith(() => codeSigner),
              loggerRef.overrideWith(() => logger),
            },
          );
        },
      );

      test('returns signature from command-based signing when valid', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=get-key-cmd',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'cmd-signature');
        when(
          () => codeSigner.runPublicKeyCmd(any()),
        ).thenAnswer((_) async => 'pem-public-key');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(true);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, equals('cmd-signature'));
            verify(
              () => codeSigner.signWithCmd(
                data: 'test-hash',
                command: 'sign-cmd',
              ),
            ).called(1);
            verify(() => codeSigner.runPublicKeyCmd('get-key-cmd')).called(1);
            verify(
              () => codeSigner.verify(
                message: 'test-hash',
                signature: 'cmd-signature',
                publicKeyPem: 'pem-public-key',
              ),
            ).called(1);
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test(
        'runs --public-key-cmd once for the build key and every signature',
        () async {
          argResults = argParser.parse([
            '--${CommonArguments.publicKeyCmd.name}=get-key-cmd',
            '--${CommonArguments.signCmd.name}=sign-cmd',
          ]);

          when(
            () => codeSigner.signWithCmd(
              data: any(named: 'data'),
              command: any(named: 'command'),
            ),
          ).thenAnswer((_) async => 'cmd-signature');
          var keyRuns = 0;
          when(() => codeSigner.runPublicKeyCmd(any())).thenAnswer((_) async {
            keyRuns++;
            // A command that returned a different key each time would sign
            // against one key and embed another if it ran more than once.
            return 'pem-public-key-$keyRuns';
          });
          when(
            () => codeSigner.base64PublicKeyFromPem(any()),
          ).thenReturn('encoded-key');
          when(
            () => codeSigner.verify(
              message: any(named: 'message'),
              signature: any(named: 'signature'),
              publicKeyPem: any(named: 'publicKeyPem'),
            ),
          ).thenReturn(true);

          final patcher = _TestPatcher(
            argParser: argParser,
            argResults: argResults,
            flavor: null,
            target: null,
          );

          await runScoped(
            () async {
              // One build, then a signature per architecture.
              await patcher.getEncodedPublicKey();
              await patcher.signHash('arm64-hash');
              await patcher.signHash('arm32-hash');
              await patcher.signHash('x86_64-hash');

              verify(() => codeSigner.runPublicKeyCmd('get-key-cmd')).called(1);
              verify(
                () => codeSigner.base64PublicKeyFromPem('pem-public-key-1'),
              ).called(1);
              verify(
                () => codeSigner.verify(
                  message: any(named: 'message'),
                  signature: 'cmd-signature',
                  publicKeyPem: 'pem-public-key-1',
                ),
              ).called(3);
            },
            values: {codeSignerRef.overrideWith(() => codeSigner)},
          );
        },
      );

      test('exits with an error when sign-cmd fails', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=get-key-cmd',
          '--${CommonArguments.signCmd.name}=bad-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenThrow(
          const ProcessException('bad-cmd', [], 'command not found', 127),
        );

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            await expectLater(
              () => patcher.signHash('test-hash'),
              exitsWithError(
                message: 'Failed to run --sign-cmd: command not found',
                exitCode: ExitCode.software,
              ),
            );
          },
          values: {
            codeSignerRef.overrideWith(() => codeSigner),
            loggerRef.overrideWith(() => logger),
          },
        );
      });

      test('exits with an error when public-key-cmd fails', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=bad-key-cmd',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'signature');
        when(
          () => codeSigner.runPublicKeyCmd(any()),
        ).thenThrow(
          const ProcessException(
            'bad-key-cmd',
            [],
            'command not found',
            127,
          ),
        );

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            await expectLater(
              () => patcher.signHash('test-hash'),
              exitsWithError(
                message: 'Failed to run --public-key-cmd: command not found',
                exitCode: ExitCode.software,
              ),
            );
          },
          values: {
            codeSignerRef.overrideWith(() => codeSigner),
            loggerRef.overrideWith(() => logger),
          },
        );
      });

      test('supports mixed signing (public key file + sign cmd)', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyArg.name}=${publicKeyTempFile.path}',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'cmd-signature');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(true);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, equals('cmd-signature'));
            verifyNever(() => codeSigner.runPublicKeyCmd(any()));
            verify(
              () => codeSigner.verify(
                message: 'test-hash',
                signature: 'cmd-signature',
                publicKeyPem: any(named: 'publicKeyPem'),
              ),
            ).called(1);
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test('exits with an error when signature verification fails', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=get-key-cmd',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'bad-signature');
        when(
          () => codeSigner.runPublicKeyCmd(any()),
        ).thenAnswer((_) async => 'pem-public-key');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(false);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            await expectLater(
              () => patcher.signHash('test-hash'),
              exitsWithError(
                message:
                    'Signature verification failed: the signature does not '
                    'match the provided public key.',
                hint:
                    'Pass the public key of the key pair that signs the patch.',
                exitCode: ExitCode.software,
              ),
            );
          },
          values: {
            codeSignerRef.overrideWith(() => codeSigner),
            loggerRef.overrideWith(() => logger),
          },
        );
      });
    });
  });
}

class _TestPatcher extends Patcher {
  _TestPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
    ReleaseType? releaseType,
  }) : _releaseType = releaseType;

  final ReleaseType? _releaseType;

  @override
  Future<void> assertPreconditions() {
    throw UnimplementedError();
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    throw UnimplementedError();
  }

  Map<Arch, String>? testDebugInfoFileNames = const {
    Arch.arm64: 'app.test-arm64.symbols',
    Arch.x86_64: 'app.test-x64.symbols',
  };

  @override
  Map<Arch, String> get debugInfoFileNames =>
      testDebugInfoFileNames ?? super.debugInfoFileNames;

  @override
  String get primaryReleaseArtifactArch => throw UnimplementedError();

  @override
  ReleaseType get releaseType {
    if (_releaseType != null) return _releaseType;
    throw UnimplementedError();
  }
}
