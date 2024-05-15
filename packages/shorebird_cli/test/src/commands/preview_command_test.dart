import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Platform;

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(PreviewCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const releaseVersion = '1.2.3';
    const track = DeploymentTrack.production;
    const releaseId = 42;

    late AppMetadata app;
    late AppleDevice appleDevice;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late Auth auth;
    late Cache cache;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late Directory previewDirectory;
    late Platform platform;
    late Progress progress;
    late Release release;
    late ReleaseArtifact releaseArtifact;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late PreviewCommand command;

    R runWithOverrides<R>(R Function() body) {
      return HttpOverrides.runZoned(
        () => runScoped(
          body,
          values: {
            artifactManagerRef.overrideWith(() => artifactManager),
            authRef.overrideWith(() => auth),
            cacheRef.overrideWith(() => cache),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            httpClientRef.overrideWith(() => httpClient),
            loggerRef.overrideWith(() => logger),
            platformRef.overrideWith(() => platform),
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        ),
      );
    }

    setUpAll(() {
      registerFallbackValue(
        const AppleDevice(
          deviceProperties: DeviceProperties(name: 'iPhone 12'),
          hardwareProperties: HardwareProperties(
            platform: 'iOS',
            udid: '12345678-1234567890ABCDEF',
          ),
          connectionProperties: ConnectionProperties(
            transportType: 'wired',
            tunnelState: 'disconnected',
          ),
        ),
      );
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(MockHttpClient());
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(StreamController<List<int>>());
      registerFallbackValue(Uri());
    });

    setUp(() {
      app = MockAppMetadata();
      appleDevice = MockAppleDevice();
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      auth = MockAuth();
      cache = MockCache();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      previewDirectory = Directory.systemTemp.createTempSync();
      progress = MockProgress();
      release = MockRelease();
      releaseArtifact = MockReleaseArtifact();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      command = PreviewCommand()..testArgResults = argResults;

      when(() => argResults.wasParsed('app-id')).thenReturn(true);
      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(() => argResults['staging']).thenReturn(false);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => cache.getPreviewDirectory(any())).thenReturn(previewDirectory);
      when(
        () => codePushClientWrapper.getApps(),
      ).thenAnswer((_) async => [app]);
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
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => releaseArtifact);
      when(() => app.appId).thenReturn(appId);
      when(() => app.displayName).thenReturn(appDisplayName);
      when(() => release.id).thenReturn(releaseId);
      when(() => release.version).thenReturn(releaseVersion);
      when(() => release.platformStatuses).thenReturn({
        ReleasePlatform.android: ReleaseStatus.active,
        ReleasePlatform.ios: ReleaseStatus.active,
      });
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => progress.fail(any())).thenReturn(null);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});

      when(() => platform.isLinux).thenReturn(false);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => platform.isWindows).thenReturn(false);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    test('exits with code 70 when querying for releases fails', () async {
      final exception = Exception('oops');
      when(
        () => codePushClientWrapper.getReleases(
          appId: any(named: 'appId'),
          sideloadableOnly: any(named: 'sideloadableOnly'),
        ),
      ).thenThrow(exception);
      await expectLater(
        () => runWithOverrides(command.run),
        throwsA(exception),
      );
      verify(
        () => codePushClientWrapper.getReleases(
          appId: appId,
          sideloadableOnly: true,
        ),
      ).called(1);
    });

    group('when release is not supported on the current OS', () {
      setUp(() {
        when(() => platform.isLinux).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(true);

        when(() => release.platformStatuses).thenReturn({
          ReleasePlatform.ios: ReleaseStatus.active,
        });
      });

      test('prints error message and exits with code 70', () async {
        final result = await runWithOverrides(command.run);
        expect(result, ExitCode.software.code);
        verify(
          () => logger.err(
            'This release can only be previewed on platforms that support iOS',
          ),
        ).called(1);
      });
    });

    group('android', () {
      const releasePlatform = ReleasePlatform.android;
      const releaseArtifactUrl = 'https://example.com/release.aab';
      const packageName = 'com.example.app';

      late Adb adb;
      late Bundletool bundletool;
      late Process process;

      String aabPath() => p.join(
            previewDirectory.path,
            '${releasePlatform.name}_$releaseVersion.aab',
          );

      String apksPath() => p.join(
            previewDirectory.path,
            '${releasePlatform.name}_$releaseVersion.apks',
          );

      R runWithOverrides<R>(R Function() body) {
        return HttpOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              adbRef.overrideWith(() => adb),
              artifactManagerRef.overrideWith(() => artifactManager),
              authRef.overrideWith(() => auth),
              bundletoolRef.overrideWith(() => bundletool),
              cacheRef.overrideWith(() => cache),
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              httpClientRef.overrideWith(() => httpClient),
              loggerRef.overrideWith(() => logger),
              platformRef.overrideWith(() => platform),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
      }

      Future<void> createShorebirdYaml(Invocation invocation) async {
        File(
          p.join(
            (invocation.namedArguments[#outputDirectory] as Directory).path,
            'base',
            'assets',
            'flutter_assets',
            'shorebird.yaml',
          ),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync('app_id: $appId', flush: true);
      }

      setUp(() {
        adb = MockAdb();
        bundletool = MockBundleTool();
        process = MockProcess();

        when(() => argResults['platform']).thenReturn(releasePlatform.name);
        when(
          () => artifactManager.downloadFile(
            any(),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenAnswer((_) async => File(''));
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => bundletool.getPackageName(any()),
        ).thenAnswer((_) async => packageName);
        when(
          () => bundletool.buildApks(
            bundle: any(named: 'bundle'),
            output: any(named: 'output'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => bundletool.installApks(
            apks: any(named: 'apks'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => adb.clearAppData(
            package: any(named: 'package'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => adb.startApp(
            package: any(named: 'package'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => adb.logcat(
            filter: any(named: 'filter'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async => process);
        when(
          () => process.exitCode,
        ).thenAnswer((_) async => ExitCode.success.code);
        when(() => process.stdout).thenAnswer((_) => const Stream.empty());
        when(() => process.stderr).thenAnswer((_) => const Stream.empty());
        when(() => releaseArtifact.url).thenReturn(releaseArtifactUrl);
        when(() => release.platformStatuses).thenReturn({
          ReleasePlatform.android: ReleaseStatus.active,
          ReleasePlatform.ios: ReleaseStatus.active,
        });
      });

      // This should probably be outside of the android group, but because
      // we want to verify that android-specific behavior is used, here it is.
      group('when release has a mix of supported and unsupported platforms',
          () {
        setUp(() {
          when(() => platform.isLinux).thenReturn(false);
          when(() => platform.isMacOS).thenReturn(false);
          when(() => platform.isWindows).thenReturn(true);

          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(createShorebirdYaml);

          when(() => release.platformStatuses).thenReturn({
            ReleasePlatform.ios: ReleaseStatus.active,
            ReleasePlatform.android: ReleaseStatus.active,
          });
        });

        test('does not prompt for platform, uses android', () async {
          await runWithOverrides(command.run);

          verify(() => bundletool.installApks(apks: apksPath())).called(1);
          verifyNever(
            () => logger.chooseOne<String>(
              any(),
              choices: any(named: 'choices'),
              display: any(named: 'display'),
            ),
          );
        });
      });

      group('setChannelOnAab', () {
        late File aabFile;

        File createAabFile({required String? channel}) {
          final tempDir = Directory.systemTemp.createTempSync();
          final aabDirectory = Directory(p.join(tempDir.path, 'app-release'))
            ..createSync(recursive: true);
          final yamlContents = [
            'app_id: $appId\n',
            if (channel != null) 'channel: $channel\n',
          ].join();
          File(
            p.join(
              aabDirectory.path,
              'base',
              'assets',
              'flutter_assets',
              'shorebird.yaml',
            ),
          )
            ..createSync(recursive: true)
            ..writeAsStringSync(yamlContents);

          ZipFileEncoder().zipDirectory(aabDirectory, filename: aabPath());

          return File(aabPath());
        }

        Future<File> shorebirdYamlFileFromAab(File aab) async {
          final tempDir = Directory.systemTemp.createTempSync();
          final aabDirectory = Directory(p.join(tempDir.path, 'app-release'))
            ..createSync(recursive: true);

          await artifactManager.extractZip(
            zipFile: aab,
            outputDirectory: aabDirectory,
          );
          return File(
            p.join(
              aabDirectory.path,
              'base',
              'assets',
              'flutter_assets',
              'shorebird.yaml',
            ),
          );
        }

        setUp(() {
          artifactManager = ArtifactManager();
        });

        group('when channel is not set', () {
          group('when target channel is  production', () {
            test('does not change shorebird.yaml', () async {
              aabFile = createAabFile(channel: null);
              await runWithOverrides(
                () => command.setChannelOnAab(
                  aabFile: aabFile,
                  channel: DeploymentTrack.production.channel,
                ),
              );

              final updatedShorebirdYamlFile =
                  await shorebirdYamlFileFromAab(aabFile);
              expect(
                updatedShorebirdYamlFile.readAsStringSync(),
                'app_id: $appId\n',
              );
            });
          });

          group('when target channel is not production', () {
            test('sets shorebird.yaml channel to target channel', () async {
              aabFile = createAabFile(channel: null);
              await runWithOverrides(
                () => command.setChannelOnAab(
                  aabFile: aabFile,
                  channel: 'live',
                ),
              );

              final updatedShorebirdYamlFile =
                  await shorebirdYamlFileFromAab(aabFile);
              expect(updatedShorebirdYamlFile.readAsStringSync(), '''
app_id: $appId
channel: live
''');
            });
          });
        });

        group('when channel is set to target channel', () {
          test('does not attempt to set channel', () async {
            aabFile = createAabFile(channel: track.channel);
            final originalModificationTime = aabFile.statSync().modified;
            await runWithOverrides(
              () => command.setChannelOnAab(
                aabFile: aabFile,
                channel: track.channel,
              ),
            );

            final updatedShorebirdYamlFile =
                await shorebirdYamlFileFromAab(aabFile);
            expect(updatedShorebirdYamlFile.readAsStringSync(), '''
app_id: $appId
channel: ${track.channel}
''');
            // Verify that we didn't touch the file.
            expect(originalModificationTime, aabFile.statSync().modified);
          });
        });

        group('when channel is set to a different channel', () {
          test('sets shorebird.yaml channel to target channel', () async {
            aabFile = createAabFile(channel: 'dev');
            await runWithOverrides(
              () => command.setChannelOnAab(
                aabFile: aabFile,
                channel: track.channel,
              ),
            );

            final updatedShorebirdYamlFile =
                await shorebirdYamlFileFromAab(aabFile);
            expect(updatedShorebirdYamlFile.readAsStringSync(), '''
app_id: $appId
channel: ${track.channel}
''');
          });
        });
      });

      test('exits with code 70 when querying for release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: appId,
            releaseId: releaseId,
            arch: 'aab',
            platform: releasePlatform,
          ),
        ).called(1);
      });

      test('exits with code 70 when downloading release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => artifactManager.downloadFile(
            any(),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => progress.fail('$exception')).called(1);
      });

      test('exits with code 70 when unable to find shorebird.yaml', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => progress.fail('Exception: Unable to find shorebird.yaml'),
        ).called(1);
      });

      test('exits with code 70 when extracting metadata fails', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        final exception = Exception('oops');
        when(() => bundletool.getPackageName(any())).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => bundletool.getPackageName(aabPath())).called(1);
      });

      test('exits with code 70 when building apks fails', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        final exception = Exception('oops');
        when(
          () => bundletool.buildApks(
            bundle: any(named: 'bundle'),
            output: any(named: 'output'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => bundletool.buildApks(bundle: aabPath(), output: apksPath()),
        ).called(1);
      });

      test('exits with code 70 when installing apks fails', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        final exception = Exception('oops');
        when(
          () => bundletool.installApks(apks: any(named: 'apks')),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => bundletool.installApks(apks: apksPath())).called(1);
      });

      test('exits with code 70 when clearing app data fails', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        final exception = Exception('oops');
        when(
          () => adb.clearAppData(package: any(named: 'package')),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => adb.clearAppData(package: packageName)).called(1);
      });

      test('exits with code 70 when starting app fails', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        final exception = Exception('oops');
        when(() => adb.startApp(package: any(named: 'package')))
            .thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => adb.startApp(package: packageName)).called(1);
      });

      test('exits with non-zero exit code when logcat process fails', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        when(() => process.exitCode).thenAnswer((_) async => 1);
        final result = await runWithOverrides(command.run);
        expect(result, equals(1));
        verify(() => adb.logcat(filter: 'flutter')).called(1);
      });

      test('pipes stdout output to logger', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        final completer = Completer<int>();
        when(() => process.exitCode).thenAnswer((_) => completer.future);
        const output = 'hello world';
        when(
          () => process.stdout,
        ).thenAnswer((_) => Stream.value(utf8.encode(output)));
        final result = runWithOverrides(command.run);
        completer.complete(0);
        await expectLater(await result, equals(ExitCode.success.code));
        verify(() => logger.info(output)).called(1);
      });

      test('pipes stderr output to logger', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        final completer = Completer<int>();
        when(() => process.exitCode).thenAnswer((_) => completer.future);
        const output = 'hello world';
        when(
          () => process.stderr,
        ).thenAnswer((_) => Stream.value(utf8.encode(output)));
        final result = runWithOverrides(command.run);
        completer.complete(0);
        await expectLater(await result, equals(ExitCode.success.code));
        verify(() => logger.err(output)).called(1);
      });

      test(
          '''does not prompt or query for app when in a shorebird project without flavors''',
          () async {
        when(() => shorebirdEnv.getShorebirdYaml())
            .thenReturn(const ShorebirdYaml(appId: 'test-app-id'));
        when(() => argResults.wasParsed('app-id')).thenReturn(false);
        when(() => argResults['app-id']).thenReturn(null);

        await runWithOverrides(command.run);

        verifyNever(
          () => logger.chooseOne<AppMetadata>(
            'Which app would you like to preview?',
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        );
        verifyNever(() => codePushClientWrapper.getApps());
      });

      test('prompts for the flavor when in shorebird project with flavors',
          () async {
        when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
          const ShorebirdYaml(
            appId: 'test-app-id',
            flavors: {
              'dev': 'dev-app-id',
              'prod': 'prod-app-id',
            },
          ),
        );
        when(() => argResults.wasParsed('app-id')).thenReturn(false);
        when(() => argResults['app-id']).thenReturn(null);
        when(
          () => logger.chooseOne<String>(
            any(),
            choices: any(named: 'choices'),
          ),
        ).thenReturn('dev');

        await runWithOverrides(command.run);

        verify(
          () => logger.chooseOne<String>(
            any(),
            choices: ['dev', 'prod'],
          ),
        ).called(1);
      });

      test('queries for apps when app-id is not specified', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        when(() => argResults.wasParsed('app-id')).thenReturn(false);
        when(() => argResults['app-id']).thenReturn(null);
        when(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).thenReturn(app);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final captured = verify(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        ).captured.single as String Function(AppMetadata);
        expect(captured(app), equals(app.displayName));
        verify(() => codePushClientWrapper.getApps()).called(1);
      });

      test('prompts for platforms when platform is not specified', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);
        // We only prompt when there are multiple platforms to choose from
        when(() => platform.isMacOS).thenReturn(true);

        when(() => argResults['platform']).thenReturn(null);
        when(
          () => logger.chooseOne<String>(
            any(),
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).thenReturn(releasePlatform.displayName);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final platforms = verify(
          () => logger.chooseOne<String>(
            any(),
            choices: captureAny(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).captured.single as List<String>;
        expect(
          platforms,
          equals([
            ReleasePlatform.android.displayName,
            ReleasePlatform.ios.displayName,
          ]),
        );
      });

      test('exits early when no apps are found', () async {
        when(() => argResults.wasParsed('app-id')).thenReturn(false);
        when(() => argResults['app-id']).thenReturn(null);
        when(() => codePushClientWrapper.getApps()).thenAnswer((_) async => []);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verifyNever(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        );
        verify(() => codePushClientWrapper.getApps()).called(1);
        verify(() => logger.info('No apps found')).called(1);
      });

      test('exits early when no releases are found', () async {
        when(() => argResults['release-version']).thenReturn(null);
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenAnswer((_) async => []);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verifyNever(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        );
        verify(
          () => codePushClientWrapper.getReleases(
            appId: appId,
            sideloadableOnly: true,
          ),
        ).called(1);
        verify(() => logger.info('No previewable releases found')).called(1);
      });

      test(
          'queries for releases when '
          'release-version is not specified', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        when(() => argResults['release-version']).thenReturn(null);
        when(
          () => logger.chooseOne<Release>(
            any(),
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).thenReturn(release);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final captured = verify(
          () => logger.chooseOne<Release>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        ).captured.single as String Function(Release);
        expect(captured(release), equals(releaseVersion));
        verify(
          () => codePushClientWrapper.getReleases(
            appId: appId,
            sideloadableOnly: true,
          ),
        ).called(1);
      });

      test('forwards deviceId to adb and bundletool', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(createShorebirdYaml);

        const deviceId = '1234';
        when(() => argResults['device-id']).thenReturn(deviceId);
        await runWithOverrides(command.run);

        verify(
          () => bundletool.installApks(
            apks: any(named: 'apks'),
            deviceId: deviceId,
          ),
        ).called(1);
        verify(
          () => adb.startApp(
            package: any(named: 'package'),
            deviceId: deviceId,
          ),
        ).called(1);
        verify(
          () => adb.logcat(filter: any(named: 'filter'), deviceId: deviceId),
        ).called(1);
      });
    });

    group('ios', () {
      const releaseArtifactUrl = 'https://example.com/runner.app';
      const releasePlatform = ReleasePlatform.ios;
      late Devicectl devicectl;
      late IOSDeploy iosDeploy;

      String runnerPath() => p.join(
            previewDirectory.path,
            '${releasePlatform.name}_$releaseVersion.app',
          );

      R runWithOverrides<R>(R Function() body) {
        return HttpOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              adbRef.overrideWith(() => adb),
              artifactManagerRef.overrideWith(() => artifactManager),
              authRef.overrideWith(() => auth),
              bundletoolRef.overrideWith(() => bundletool),
              cacheRef.overrideWith(() => cache),
              codePushClientWrapperRef
                  .overrideWith(() => codePushClientWrapper),
              devicectlRef.overrideWith(() => devicectl),
              httpClientRef.overrideWith(() => httpClient),
              iosDeployRef.overrideWith(() => iosDeploy),
              loggerRef.overrideWith(() => logger),
              platformRef.overrideWith(() => platform),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
      }

      setUp(() {
        devicectl = MockDevicectl();
        iosDeploy = MockIOSDeploy();

        when(() => appleDevice.name).thenReturn('iPhone 12');
        when(() => appleDevice.udid).thenReturn('12345678-1234567890ABCDEF');
        when(() => argResults['platform']).thenReturn(releasePlatform.name);
        when(
          () => artifactManager.downloadFile(any()),
        ).thenAnswer((_) async => File(''));
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((_) async {});

        when(() => devicectl.deviceForLaunch(deviceId: any(named: 'deviceId')))
            .thenAnswer((_) async => null);
        when(
          () => devicectl.installAndLaunchApp(
            runnerAppDirectory: any(named: 'runnerAppDirectory'),
            device: any(named: 'device'),
          ),
        ).thenAnswer((_) async => ExitCode.success.code);
        when(() => iosDeploy.installIfNeeded()).thenAnswer((_) async {});
        when(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async => ExitCode.success.code);
        when(() => release.platformStatuses).thenReturn({
          ReleasePlatform.android: ReleaseStatus.active,
          ReleasePlatform.ios: ReleaseStatus.active,
        });
        when(() => releaseArtifact.url).thenReturn(releaseArtifactUrl);
        when(() => platform.isMacOS).thenReturn(true);
      });

      File setupShorebirdYaml() => File(
            p.join(
              runnerPath(),
              'Frameworks',
              'App.framework',
              'flutter_assets',
              'shorebird.yaml',
            ),
          )
            ..createSync(recursive: true)
            ..writeAsStringSync('app_id: $appId', flush: true);

      test('ensures ios-deploy is installed', () async {
        await runWithOverrides(command.run);
        verify(() => iosDeploy.installIfNeeded()).called(1);
      });

      test('exits with code 70 when querying for release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: appId,
            releaseId: releaseId,
            arch: 'runner',
            platform: releasePlatform,
          ),
        ).called(1);
      });

      test('exits with code 70 when downloading release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => artifactManager.downloadFile(any()),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => progress.fail('$exception')).called(1);
      });

      test(
          'exits with code 70 when extracting '
          'release artifact fails', () async {
        final exception = Exception('oops');
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => progress.fail('$exception')).called(1);
      });

      test('exits with code 70 when unable to find shorebird.yaml', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => progress.fail('Exception: Unable to find shorebird.yaml'),
        ).called(1);
        verifyNever(
          () => iosDeploy.installAndLaunchApp(bundlePath: runnerPath()),
        );
      });

      group('when device-id arg is provided', () {
        const devicectlDeviceId = '12345';
        setUp(() {
          when(() => appleDevice.udid).thenReturn(devicectlDeviceId);
          when(() => devicectl.listAvailableIosDevices())
              .thenAnswer((_) async => [appleDevice]);
        });

        test('uses matching devicectl device if found', () async {
          when(() => argResults['device-id'])
              .thenAnswer((_) => devicectlDeviceId);

          setupShorebirdYaml();
          await runWithOverrides(command.run);

          verifyNever(
            () => iosDeploy.installAndLaunchApp(bundlePath: runnerPath()),
          );
        });

        test(
            'falls back to ios-deploy if no devicectl devices have matching id',
            () async {
          when(() => argResults['device-id'])
              .thenAnswer((_) => 'not-a-device-id');
          setupShorebirdYaml();
          await runWithOverrides(command.run);

          verify(
            () => progress.complete(
              '''No iOS 17+ device found, looking for devices running iOS 16 or lower''',
            ),
          ).called(1);
          verify(
            () => iosDeploy.installAndLaunchApp(
              bundlePath: runnerPath(),
              deviceId: 'not-a-device-id',
            ),
          ).called(1);
        });
      });

      test('uses devicectl if devicectl returns a usable device', () async {
        when(() => devicectl.deviceForLaunch(deviceId: any(named: 'deviceId')))
            .thenAnswer((_) async => appleDevice);
        setupShorebirdYaml();
        await runWithOverrides(command.run);
        verify(
          () => devicectl.installAndLaunchApp(
            runnerAppDirectory: any(named: 'runnerAppDirectory'),
            device: any(named: 'device'),
          ),
        ).called(1);
        verifyNever(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        );
      });

      test('exits with code 70 when install/launch throws', () async {
        setupShorebirdYaml();
        final exception = Exception('oops');
        when(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => iosDeploy.installAndLaunchApp(bundlePath: runnerPath()),
        ).called(1);
      });

      test('exits with code 0 when install/launch succeeds (production)',
          () async {
        final shorebirdYaml = setupShorebirdYaml();
        when(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async => ExitCode.success.code);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => iosDeploy.installAndLaunchApp(bundlePath: runnerPath()),
        ).called(1);
        expect(
          shorebirdYaml.readAsStringSync(),
          equals('''
app_id: $appId
channel: ${track.channel}
'''),
        );
      });

      test('exits with code 0 when install/launch succeeds (staging)',
          () async {
        when(() => argResults['staging']).thenReturn(true);
        final shorebirdYaml = File(
          p.join(
            runnerPath(),
            'Frameworks',
            'App.framework',
            'flutter_assets',
            'shorebird.yaml',
          ),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync('app_id: $appId', flush: true);
        when(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async => ExitCode.success.code);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => iosDeploy.installAndLaunchApp(bundlePath: runnerPath()),
        ).called(1);
        expect(
          shorebirdYaml.readAsStringSync(),
          equals('''
app_id: $appId
channel: ${DeploymentTrack.staging.channel}
'''),
        );
      });
    });
  });
}
