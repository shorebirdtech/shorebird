import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/abi.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

// Behavior shared with LinuxPatcher is tested in desktop_patcher_test.dart;
// this file covers only what is specific to Windows.
void main() {
  useTempWorkingDirectory();
  group(WindowsPatcher, () {
    late LocalAbi abi;
    late ArgParser argParser;
    late CodePushClientWrapper codePushClientWrapper;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late Directory releaseDirectory;
    late Doctor doctor;
    late Powershell powershell;
    late ShorebirdEnv shorebirdEnv;
    late Windows windows;
    late WindowsPatcher patcher;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          abiRef.overrideWith(() => abi),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          doctorRef.overrideWith(() => doctor),
          powershellRef.overrideWith(() => powershell),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          windowsRef.overrideWith(() => windows),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.windows);
    });

    setUp(() {
      abi = MockAbi();
      when(() => abi.hostArchitecture).thenReturn('x64');
      codePushClientWrapper = MockCodePushClientWrapper();
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      releaseDirectory = Directory.systemTemp.createTempSync();
      doctor = MockDoctor();
      powershell = MockPowershell();
      shorebirdEnv = MockShorebirdEnv();
      windows = MockWindows();

      when(
        () => artifactManager.getWindowsReleaseDirectory(),
      ).thenReturn(releaseDirectory);

      patcher = WindowsPatcher(
        argParser: argParser,
        argResults: argResults,
        flavor: null,
        target: 'lib/main_dev.dart',
      );
    });

    test('requires minimumSupportedWindowsFlutterVersion', () {
      expect(
        runWithOverrides(() => patcher.minimumFlutterVersion),
        minimumSupportedWindowsFlutterVersion,
      );
    });

    test('identifies as the windows release type', () {
      expect(patcher.releaseType, ReleaseType.windows);
      runWithOverrides(() {
        expect(patcher.patchArch, Arch.x86_64);
        expect(
          patcher.primaryReleaseArtifactArch,
          primaryWindowsReleaseArtifactArch,
        );
        expect(patcher.supplementaryReleaseArtifactArch, 'windows_supplement');
      });
    });

    group('on an arm64 machine', () {
      setUp(() {
        when(() => abi.hostArchitecture).thenReturn('arm64');
      });

      test('patches the arm64 build of the release', () {
        runWithOverrides(() {
          expect(patcher.patchArch, Arch.arm64);
          expect(patcher.primaryReleaseArtifactArch, 'win_archive_arm64');
          expect(
            patcher.supplementaryReleaseArtifactArch,
            'windows_supplement_arm64',
          );
          expect(
            patcher.minimumFlutterVersion,
            minimumSupportedWindowsArm64FlutterVersion,
          );
        });
      });
    });

    group('prepareForRelease', () {
      final release = Release(
        id: 7,
        appId: 'app-id',
        version: '1.0.0+1',
        flutterRevision: 'rev',
        flutterVersion: '3.47.9',
        platforms: const {},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      setUp(() {
        when(() => abi.hostArchitecture).thenReturn('arm64');
      });

      test('passes when the release has a build for this arch', () async {
        when(
          () => codePushClientWrapper.maybeGetReleaseArtifact(
            appId: 'app-id',
            releaseId: 7,
            arch: 'win_archive_arm64',
            platform: ReleasePlatform.windows,
          ),
        ).thenAnswer((_) async => MockReleaseArtifact());

        await runWithOverrides(
          () => patcher.prepareForRelease(appId: 'app-id', release: release),
        );
      });

      test('exits when the release has no build for this arch', () async {
        when(
          () => codePushClientWrapper.maybeGetReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenAnswer((_) async => null);

        await expectLater(
          () => runWithOverrides(
            () => patcher.prepareForRelease(appId: 'app-id', release: release),
          ),
          exitsWithError(
            message:
                'Release 1.0.0+1 has no Windows arm64 build to patch. Flutter '
                'builds Windows apps for the machine it runs on, so this arm64 '
                'machine can only patch an arm64 build.',
            hint:
                'Run `shorebird release windows` on this machine for version '
                "1.0.0+1 first, or patch on a machine of the release's "
                'architecture.',
            exitCode: ExitCode.software,
          ),
        );
      });
    });

    test('validates with the windows validators on windows', () {
      final validators = <Validator>[MockValidator()];
      when(() => doctor.windowsCommandValidators).thenReturn(validators);

      expect(runWithOverrides(() => patcher.commandValidators), validators);
      expect(patcher.hostOperatingSystem, NativePlatform.windows);
    });

    test('diffs archives with WindowsArchiveDiffer', () {
      expect(patcher.archiveDiffer, const WindowsArchiveDiffer());
    });

    test('patches data/app.so in the release directory', () {
      expect(runWithOverrides(() => patcher.appDirectory), releaseDirectory);
      expect(patcher.dartLibraryPathSegments, ['data', 'app.so']);
    });

    group('buildApp', () {
      test('builds the windows app and returns its directory', () async {
        final builtDirectory = Directory('built');
        when(
          () => artifactBuilder.buildWindowsApp(
            target: any(named: 'target'),
            args: any(named: 'args'),
            base64PublicKey: any(named: 'base64PublicKey'),
          ),
        ).thenAnswer((_) async => builtDirectory);

        final directory = await runWithOverrides(
          () => patcher.buildApp(args: ['--foo'], base64PublicKey: 'key'),
        );

        expect(directory, builtDirectory);
        verify(
          () => artifactBuilder.buildWindowsApp(
            target: 'lib/main_dev.dart',
            args: ['--foo'],
            base64PublicKey: 'key',
          ),
        ).called(1);
      });
    });

    group('versionFromAppDirectory', () {
      test("reads the executable's product version", () async {
        const projectName = 'my_app';
        final directory = Directory('release');
        final executable = File('my_app.exe');
        final pubspec = MockPubspec();
        when(() => pubspec.name).thenReturn(projectName);
        when(() => shorebirdEnv.getPubspecYaml()).thenReturn(pubspec);
        when(
          () => windows.findExecutable(
            releaseDirectory: any(named: 'releaseDirectory'),
            projectName: any(named: 'projectName'),
          ),
        ).thenReturn(executable);
        when(
          () => powershell.getProductVersion(any()),
        ).thenAnswer((_) async => '1.2.3');

        final version = await runWithOverrides(
          () => patcher.versionFromAppDirectory(directory),
        );

        expect(version, '1.2.3');
        verify(
          () => windows.findExecutable(
            releaseDirectory: directory,
            projectName: projectName,
          ),
        ).called(1);
        verify(() => powershell.getProductVersion(executable)).called(1);
      });
    });
  });
}
