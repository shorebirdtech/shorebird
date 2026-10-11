import 'dart:io';

import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

// Behavior shared with LinuxPatcher is tested in desktop_patcher_test.dart;
// this file covers only what is specific to Windows.
void main() {
  useTempWorkingDirectory();
  group(WindowsPatcher, () {
    late ArgParser argParser;
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
    });

    setUp(() {
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

    test('identifies as the windows release type', () {
      expect(patcher.releaseType, ReleaseType.windows);
      expect(
        patcher.primaryReleaseArtifactArch,
        primaryWindowsReleaseArtifactArch,
      );
      expect(patcher.supplementaryReleaseArtifactArch, 'windows_supplement');
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
