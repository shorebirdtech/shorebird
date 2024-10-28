import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/releases/releases.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/executables/bundletool.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(GetApkCommand, () {
    const appId = 'test-app-id';
    const releaseId = 123;
    const releaseVersion = '1.2.3';
    const releaseArtifactUrl = 'https://example.com/release.aab';
    const apkFileName = '${appId}_$releaseVersion.apk';

    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late Bundletool bundletool;
    late CodePushClientWrapper codePushClientWrapper;
    late Progress progress;
    late Directory projectRoot;
    late Release release;
    late ReleaseArtifact releaseArtifact;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdYaml shorebirdYaml;

    late GetApkCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactManagerRef.overrideWith(() => artifactManager),
          bundletoolRef.overrideWith(() => bundletool),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    /// Creates a zip file containing an apk file with the apks extension
    Future<File> createTempApksFile() async {
      final tempDir = Directory.systemTemp.createTempSync();
      final apksDir = Directory(p.join(tempDir.path, 'temp.apks'))
        ..createSync(recursive: true);
      final apksFile = File(p.join(tempDir.path, 'test.apks'));

      // Write an "apk" to zip
      File(p.join(apksDir.path, apkFileName))
        ..createSync(recursive: true)
        ..writeAsStringSync('hello');
      ZipFileEncoder().zipDirectory(
        apksDir,
        filename: apksFile.path,
      );
      return apksFile;
    }

    setUpAll(() {
      registerFallbackValue(Uri());
    });

    setUp(() {
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      bundletool = MockBundleTool();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      release = MockRelease();
      releaseArtifact = MockReleaseArtifact();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdYaml = MockShorebirdYaml();

      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);

      when(
        () => artifactManager.downloadWithProgressUpdates(
          any(),
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) async => File(''));

      when(
        () => bundletool.buildApks(
          bundle: any(named: 'bundle'),
          output: any(named: 'output'),
        ),
      ).thenAnswer((invocation) async {
        final apksFile = await createTempApksFile();
        final outputPath = invocation.namedArguments[#output] as String;
        apksFile.renameSync(outputPath);
      });

      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.getReleases(
          appId: any(named: 'appId'),
          sideloadableOnly: any(named: 'sideloadableOnly'),
        ),
      ).thenAnswer((_) async => [release]);
      when(
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: ReleasePlatform.android,
        ),
      ).thenAnswer((_) async => releaseArtifact);

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(release);
      when(() => logger.progress(any())).thenReturn(progress);

      when(() => release.id).thenReturn(releaseId);
      when(() => release.version).thenReturn(releaseVersion);

      when(() => releaseArtifact.url).thenReturn(releaseArtifactUrl);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(
        () => shorebirdEnv.getShorebirdYaml(),
      ).thenReturn(shorebirdYaml);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});

      when(() => shorebirdYaml.appId).thenReturn(appId);

      command = GetApkCommand()..testArgResults = argResults;
    });

    group('when validation fails', () {
      final exception = ValidationFailedException();
      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(exception);
      });

      test('exits with exit code from validation error', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(exception.exitCode.code)),
        );
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
            checkShorebirdInitialized: true,
          ),
        ).called(1);
      });
    });

    group('when querying for releases fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(
            isA<ProcessExit>().having((e) => e.exitCode, 'exitCode', 70),
          ),
        );
        verify(
          () => codePushClientWrapper.getReleases(
            appId: appId,
            sideloadableOnly: true,
          ),
        ).called(1);
      });
    });

    group('when downloading aab fails', () {
      final exception = Exception('oops');

      setUp(() {
        when(
          () => artifactManager.downloadWithProgressUpdates(
            any(),
            message: any(named: 'message'),
          ),
        ).thenThrow(exception);
      });

      test('exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(
            isA<ProcessExit>().having((e) => e.exitCode, 'exitCode', 70),
          ),
        );
      });
    });

    group('when output directory is specified', () {
      late Directory outDirectory;

      setUp(() {
        outDirectory = Directory.systemTemp.createTempSync();
        when(() => argResults['out']).thenReturn(outDirectory.path);
        when(() => argResults.wasParsed('out')).thenReturn(true);
      });

      test('creates apk in specified directory', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(ExitCode.success.code),
        );
        final expectedMessage =
            '''apk generated at ${lightCyan.wrap(p.join(outDirectory.path, apkFileName))}''';
        verify(() => logger.info(expectedMessage)).called(1);
      });
    });

    group('when no output directory is specified', () {
      test('creates apk in project build subdirectory', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(ExitCode.success.code),
        );

        final apkPath = p.join(
          projectRoot.path,
          'build',
          'app',
          'outputs',
          'shorebird-apk',
          apkFileName,
        );
        final expectedMessage = 'apk generated at ${lightCyan.wrap(apkPath)}';
        verify(() => logger.info(expectedMessage)).called(1);
      });
    });
  });
}
