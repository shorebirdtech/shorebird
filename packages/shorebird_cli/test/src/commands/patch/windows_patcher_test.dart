import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/flavor_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(WindowsPatcher, () {
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late Doctor doctor;
    late EngineConfig engineConfig;
    late Directory projectRoot;
    late FlavorValidator flavorValidator;
    late ShorebirdLogger logger;
    late PatchDiffChecker patchDiffChecker;
    late Powershell powershell;
    late Progress progress;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late WindowsPatcher patcher;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => engineConfig),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          powershellRef.overrideWith(() => powershell),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.windows);
      registerFallbackValue(ShorebirdArtifact.genSnapshotMacOS);
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(const WindowsArchiveDiffer());
    });

    setUp(() {
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      engineConfig = MockEngineConfig();
      flavorValidator = MockFlavorValidator();
      patchDiffChecker = MockPatchDiffChecker();
      powershell = MockPowershell();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argParser.options).thenReturn({});

      when(() => argResults.options).thenReturn([]);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      patcher = WindowsPatcher(
        argParser: argParser,
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('releaseType', () {
      test('is windows', () {
        expect(patcher.releaseType, ReleaseType.windows);
      });
    });

    group('primaryReleaseArtifactArch', () {
      test('is win_archive', () {
        expect(
          patcher.primaryReleaseArtifactArch,
          primaryWindowsReleaseArtifactArch,
        );
      });
    });

    group('assertPreconditions', () {
      setUp(() {
        when(
          () => doctor.windowsCommandValidators,
        ).thenReturn([flavorValidator]);
      });

      group('when validation succeeds', () {
        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(
                named: 'checkUserIsAuthenticated',
              ),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(named: 'validators'),
              supportedOperatingSystems: any(
                named: 'supportedOperatingSystems',
              ),
            ),
          ).thenAnswer((_) async {});
        });

        test('returns normally', () async {
          await expectLater(
            () => runWithOverrides(patcher.assertPreconditions),
            returnsNormally,
          );
        });
      });

      group('when validation fails', () {
        setUp(() {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(
                named: 'checkUserIsAuthenticated',
              ),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(
                named: 'validators',
              ),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(
                named: 'checkUserIsAuthenticated',
              ),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(named: 'validators'),
              supportedOperatingSystems: any(
                named: 'supportedOperatingSystems',
              ),
            ),
          ).thenThrow(exception);
          await expectLater(
            () => runWithOverrides(patcher.assertPreconditions),
            exitsWithCode(exception.exitCode),
          );
          verify(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
              checkShorebirdInitialized: true,
              validators: [flavorValidator],
              supportedOperatingSystems: {Platform.windows},
            ),
          ).called(1);
        });
      });
    });

    group('assertUnpatchableDiffs', () {
      late ReleaseArtifact releaseArtifact;
      late File releaseArchive;
      late File patchArchive;
      late DiffStatus diffStatus;

      setUp(() {
        diffStatus = const DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: false,
        );
        releaseArtifact = MockReleaseArtifact();
        final tempDir = Directory.systemTemp.createTempSync();
        releaseArchive = File(p.join(tempDir.path, 'release.zip'));
        patchArchive = File(p.join(tempDir.path, 'patch.zip'));

        when(
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArchive: any(named: 'localArchive'),
            releaseArchive: any(named: 'releaseArchive'),
            archiveDiffer: any(named: 'archiveDiffer'),
            allowAssetChanges: any(named: 'allowAssetChanges'),
            allowNativeChanges: any(named: 'allowNativeChanges'),
          ),
        ).thenAnswer((_) async => diffStatus);
      });

      test('returns result from patchDiffChecker', () async {
        final diffStatus = await runWithOverrides(
          () => patcher.assertUnpatchableDiffs(
            releaseArtifact: releaseArtifact,
            releaseArchive: releaseArchive,
            patchArchive: patchArchive,
          ),
        );

        expect(
          diffStatus,
          const DiffStatus(hasAssetChanges: false, hasNativeChanges: false),
        );
        verify(
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArchive: patchArchive,
            releaseArchive: releaseArchive,
            archiveDiffer: const WindowsArchiveDiffer(),
            allowAssetChanges: false,
            allowNativeChanges: false,
          ),
        ).called(1);
      });
    });

    group('buildPatchArtifact', () {
      const flutterVersionAndRevision = '3.27.1 (8495dee1fd)';

      setUp(() {
        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => flutterVersionAndRevision);
        when(
          () => shorebirdFlutter.getVersion(),
        ).thenAnswer((_) async => Version(3, 27, 1));
      });

      group('when build fails', () {
        setUp(() {
          when(
            () => artifactBuilder.buildWindowsApp(),
          ).thenThrow(Exception('Failed to build Windows app'));
        });

        test('exits with software error code', () async {
          expect(
            () => runWithOverrides(
              () => patcher.buildPatchArtifact(),
            ),
            throwsA(
              isA<ProcessExit>().having((e) => e.exitCode, 'exitCode', 70),
            ),
          );
        });
      });

      group('when build succeeds', () {
        setUp(() {
          final releaseDir = Directory(
            p.join(
              projectRoot.path,
              'build',
              'windows',
              'x64',
              'runner',
              'Release',
            ),
          )..createSync(recursive: true);
          when(
            () => artifactBuilder.buildWindowsApp(),
          ).thenAnswer((_) async => releaseDir);
        });

        test('returns a zipped exe file', () async {
          await expectLater(
            runWithOverrides(
              () => patcher.buildPatchArtifact(),
            ),
            completion(
              isA<File>().having((f) => f.path, 'path', endsWith('.zip')),
            ),
          );
        });
      });
    });

    group('createPatchArtifacts', () {
      const appId = 'app-id';
      const releaseId = 42;

      late Directory releaseDirectory;
      late File releaseArtifact;
      late File patchArtifact;
      late File diffFile;

      setUp(() {
        final tempDir = Directory.systemTemp.createTempSync();
        releaseArtifact = File(p.join(tempDir.path, 'release.zip'))
          ..createSync(recursive: true);

        diffFile = File(p.join(tempDir.path, 'diff.so'))
          ..createSync(recursive: true);

        releaseDirectory = Directory(
          p.join(
            projectRoot.path,
            'build',
            'windows',
            'x64',
            'runner',
            'Release',
          ),
        )..createSync(recursive: true);

        patchArtifact = File(
          p.join(
            releaseDirectory.path,
            'data',
            'app.so',
          ),
        )..createSync(recursive: true);

        when(
          () => artifactManager.getWindowsReleaseDirectory(),
        ).thenReturn(releaseDirectory);
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((invocation) async {
          (invocation.namedArguments[#outputDirectory] as Directory)
              .createSync(recursive: true);
        });
      });

      group('when creating diff fails', () {
        setUp(() {
          when(
            () => artifactManager.createDiff(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
            ),
          ).thenThrow(Exception('Failed to create diff'));
        });

        test('exits with software error code', () async {
          expect(
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: releaseId,
                releaseArtifact: releaseArtifact,
              ),
            ),
            throwsA(
              isA<ProcessExit>().having((e) => e.exitCode, 'exitCode', 70),
            ),
          );
        });
      });

      group('when creating artifacts succeeds', () {
        setUp(() {
          when(
            () => artifactManager.createDiff(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
            ),
          ).thenAnswer((_) async => diffFile.path);
        });

        test('returns patch artifacts', () async {
          final patchArtifacts = await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: 'com.example.app',
              releaseId: 1,
              releaseArtifact: releaseArtifact,
              supplementArtifact: File('supplement.zip'),
            ),
          );

          final expectedHash =
              sha256.convert(await patchArtifact.readAsBytes()).toString();

          expect(
            patchArtifacts,
            equals({
              Arch.x86_64: PatchArtifactBundle(
                arch: Arch.x86_64.arch,
                path: diffFile.path,
                hash: expectedHash,
                size: diffFile.lengthSync(),
              ),
            }),
          );
        });
      });
    });

    group('extractReleaseVersionFromArtifact', () {
      setUp(() async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((invocation) async {
          final outPath =
              (invocation.namedArguments[#outputDirectory] as Directory).path;
          File(p.join(outPath, 'hello_windows.exe'))
              .createSync(recursive: true);
        });
        when(
          () => powershell.getExeVersionString(any()),
        ).thenAnswer((_) async => '1.2.3');
      });

      test('returns version from archived exe', () async {
        final version = await runWithOverrides(
          () => patcher.extractReleaseVersionFromArtifact(
            File(''),
          ),
        );

        expect(version, '1.2.3');
      });
    });
  });
}
