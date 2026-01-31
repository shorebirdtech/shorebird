// cspell:words libinfo networkd FFFD
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
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(PreviewCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const releaseVersion = '1.2.3';
    const track = DeploymentTrack.stable;
    const releaseId = 42;
    const androidArtifactId = 21;
    const iosArtifactId = 12;
    const macosArtifactId = 13;

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

    String iosRunnerPath() {
      final platformName = ReleasePlatform.ios.name;
      return p.join(
        previewDirectory.path,
        '${platformName}_${releaseVersion}_$iosArtifactId.app',
      );
    }

    String macosAppPath() {
      final platformName = ReleasePlatform.macos.name;
      return p.join(
        previewDirectory.path,
        '${platformName}_${releaseVersion}_$macosArtifactId.app',
      );
    }

    String aabPath() {
      final platformName = ReleasePlatform.android.name;
      return p.join(
        previewDirectory.path,
        '${platformName}_${releaseVersion}_$androidArtifactId.aab',
      );
    }

    String apksPath() {
      final platformName = ReleasePlatform.android.name;
      return p.join(
        previewDirectory.path,
        '${platformName}_${releaseVersion}_$androidArtifactId.apks',
      );
    }

    File setupIOSShorebirdYaml() =>
        File(
            p.join(
              iosRunnerPath(),
              'Frameworks',
              'App.framework',
              'flutter_assets',
              'shorebird.yaml',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('app_id: $appId', flush: true);

    Future<void> setupAndroidShorebirdYaml(Invocation invocation) async {
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

    Future<File> createAabFile({required String? channel}) async {
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

      await ZipFileEncoder().zipDirectory(aabDirectory, filename: aabPath());

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
      when(
        () => argResults['track'],
      ).thenReturn(DeploymentTrack.stable.channel);
      when(() => argResults.wasParsed(any())).thenReturn(true);
      when(() => argResults.wasParsed('staging')).thenReturn(false);
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
      when(() => release.createdAt).thenReturn(DateTime(2023));
      when(() => release.platformStatuses).thenReturn({
        ReleasePlatform.android: ReleaseStatus.active,
        ReleasePlatform.ios: ReleaseStatus.active,
        ReleasePlatform.linux: ReleaseStatus.active,
        ReleasePlatform.macos: ReleaseStatus.active,
        ReleasePlatform.windows: ReleaseStatus.active,
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

    group('when --staging is passed', () {
      setUp(() {
        when(() => argResults.wasParsed('staging')).thenReturn(true);
      });

      test(
        '''warns that staging flag will be deprecated and exits with usage code''',
        () async {
          await expectLater(
            runWithOverrides(command.run),
            completion(equals(ExitCode.usage.code)),
          );
          verify(
            () => logger.err(
              '''The --staging flag is deprecated and will be removed in a future release. Use --track=staging instead.''',
            ),
          ).called(1);
        },
      );
    });

    group('when validation fails', () {
      final exception = ValidationFailedException();
      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
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
          ),
        ).called(1);
      });
    });

    group('when querying for releases fails', () {
      final exception = Exception('oops');

      setUp(() {
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenThrow(exception);
      });

      test('exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(exception),
        );
        verify(() => codePushClientWrapper.getReleases(appId: appId)).called(1);
      });
    });

    group('when no releases exist', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenAnswer((_) async => []);
      });

      test('prints error and exits with usage code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, ExitCode.usage.code);
        verify(
          () => logger.err('No previewable releases found for this app'),
        ).called(1);
      });
    });

    group('when no releases are found for the specified release', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenAnswer((_) async => [release]);
        when(
          () => argResults['release-version'],
        ).thenReturn('not-a-real-version');
      });

      test('prints error and exits with usage code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, ExitCode.usage.code);
        verify(
          () => logger.err(
            'No previewable releases found for version not-a-real-version',
          ),
        ).called(1);
      });
    });

    group('when release is not supported on the current OS', () {
      setUp(() {
        when(() => platform.isLinux).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(true);

        when(
          () => release.platformStatuses,
        ).thenReturn({ReleasePlatform.ios: ReleaseStatus.active});
      });

      test('prints error message and exits with code 70', () async {
        final result = await runWithOverrides(command.run);
        expect(result, ExitCode.usage.code);
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

      setUp(() {
        adb = MockAdb();
        bundletool = MockBundleTool();
        process = MockProcess();

        when(() => releaseArtifact.id).thenReturn(androidArtifactId);
        when(() => argResults['platform']).thenReturn(releasePlatform.name);
        when(
          () => artifactManager.downloadWithProgressUpdates(
            any(),
            message: any(named: 'message'),
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
            keystore: any(named: 'keystore'),
            keystorePassword: any(named: 'keystorePassword'),
            keyPassword: any(named: 'keyPassword'),
            keyAlias: any(named: 'keyAlias'),
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
        when(() => releaseArtifact.arch).thenReturn('app');
        when(() => release.platformStatuses).thenReturn({
          ReleasePlatform.android: ReleaseStatus.active,
          ReleasePlatform.ios: ReleaseStatus.active,
        });
      });

      // This should probably be outside of the android group, but because
      // we want to verify that android-specific behavior is used, here it is.
      group(
        'when release has a mix of supported and unsupported platforms',
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
            ).thenAnswer(setupAndroidShorebirdYaml);

            when(() => release.platformStatuses).thenReturn({
              ReleasePlatform.ios: ReleaseStatus.active,
              ReleasePlatform.android: ReleaseStatus.active,
            });
          });

          test('outputs apks path', () async {
            await runWithOverrides(command.run);
            final apksLink = link(uri: Uri.parse(apksPath()));
            verify(
              () => progress.complete('Built apks: ${cyan.wrap(apksLink)}'),
            ).called(1);
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

          group('when valid keystore is specified', () {
            const keystore = 'keystore.jks';
            const keystorePassword = 'pass:keystorePassword';
            const keyPassword = 'pass:keyPassword';
            const keyAlias = 'keyAlias';

            setUp(() {
              when(() => argResults['ks']).thenReturn(keystore);
              when(() => argResults['ks-pass']).thenReturn(keystorePassword);
              when(() => argResults['ks-key-pass']).thenReturn(keyPassword);
              when(() => argResults['ks-key-alias']).thenReturn(keyAlias);
            });

            test('builds apks with keystore', () async {
              await runWithOverrides(command.run);

              verify(
                () => bundletool.buildApks(
                  bundle: aabPath(),
                  output: apksPath(),
                  keystore: keystore,
                  keystorePassword: keystorePassword,
                  keyPassword: keyPassword,
                  keyAlias: keyAlias,
                ),
              ).called(1);
            });
          });

          group('when keystorePassword is missing', () {
            const keystore = 'keystore.jks';

            setUp(() {
              when(() => argResults['ks']).thenReturn(keystore);
            });

            test('exits with usage error', () async {
              final result = await runWithOverrides(command.run);
              expect(result, equals(ExitCode.usage.code));

              verify(
                () => logger.err('You must provide a keystore password.'),
              ).called(1);

              verifyNever(
                () => bundletool.buildApks(
                  bundle: aabPath(),
                  output: apksPath(),
                  keystore: any(named: 'keystore'),
                  keystorePassword: any(named: 'keystorePassword'),
                  keyPassword: any(named: 'keyPassword'),
                  keyAlias: any(named: 'keyAlias'),
                ),
              );
            });
          });

          group('when keyAlias is missing', () {
            const keystore = 'keystore.jks';
            const keystorePassword = 'keystorePassword';

            setUp(() {
              when(() => argResults['ks']).thenReturn(keystore);
              when(() => argResults['ks-pass']).thenReturn(keystorePassword);
            });

            test('exits with usage error', () async {
              final result = await runWithOverrides(command.run);
              expect(result, equals(ExitCode.usage.code));

              verify(
                () => logger.err('You must provide a key alias.'),
              ).called(1);

              verifyNever(
                () => bundletool.buildApks(
                  bundle: aabPath(),
                  output: apksPath(),
                  keystore: any(named: 'keystore'),
                  keystorePassword: any(named: 'keystorePassword'),
                  keyPassword: any(named: 'keyPassword'),
                  keyAlias: any(named: 'keyAlias'),
                ),
              );
            });
          });

          group('when keystorePassword is invalid', () {
            const keystore = 'keystore.jks';
            const keystorePassword = 'keystorePassword';
            const keyPassword = 'pass:keyPassword';
            const keyAlias = 'keyAlias';

            setUp(() {
              when(() => argResults['ks']).thenReturn(keystore);
              when(() => argResults['ks-pass']).thenReturn(keystorePassword);
              when(() => argResults['ks-key-pass']).thenReturn(keyPassword);
              when(() => argResults['ks-key-alias']).thenReturn(keyAlias);
            });

            test('exits with usage error', () async {
              final result = await runWithOverrides(command.run);
              expect(result, equals(ExitCode.usage.code));

              verify(
                () => logger.err(
                  'Keystore password must start with "pass:" or "file:".',
                ),
              ).called(1);

              verifyNever(
                () => bundletool.buildApks(
                  bundle: aabPath(),
                  output: apksPath(),
                  keystore: any(named: 'keystore'),
                  keystorePassword: any(named: 'keystorePassword'),
                  keyPassword: any(named: 'keyPassword'),
                  keyAlias: any(named: 'keyAlias'),
                ),
              );
            });
          });

          group('when keyPassword is invalid', () {
            const keystore = 'keystore.jks';
            const keystorePassword = 'file:keystorePasswordFile';
            const keyPassword = 'keyPassword';
            const keyAlias = 'keyAlias';

            setUp(() {
              when(() => argResults['ks']).thenReturn(keystore);
              when(() => argResults['ks-pass']).thenReturn(keystorePassword);
              when(() => argResults['ks-key-pass']).thenReturn(keyPassword);
              when(() => argResults['ks-key-alias']).thenReturn(keyAlias);
            });

            test('exits with usage error', () async {
              final result = await runWithOverrides(command.run);
              expect(result, equals(ExitCode.usage.code));

              verify(
                () => logger.err(
                  'Key password must start with "pass:" or "file:".',
                ),
              ).called(1);

              verifyNever(
                () => bundletool.buildApks(
                  bundle: aabPath(),
                  output: apksPath(),
                  keystore: any(named: 'keystore'),
                  keystorePassword: any(named: 'keystorePassword'),
                  keyPassword: any(named: 'keyPassword'),
                  keyAlias: any(named: 'keyAlias'),
                ),
              );
            });
          });
        },
      );

      group('setChannelOnAab', () {
        late File aabFile;

        setUp(() {
          artifactManager = ArtifactManager();
        });

        group('when channel is not set', () {
          group('when target channel is  production', () {
            test('does not change shorebird.yaml', () async {
              aabFile = await createAabFile(channel: null);
              await runWithOverrides(
                () => command.setChannelOnAab(
                  aabFile: aabFile,
                  channel: DeploymentTrack.stable.channel,
                ),
              );

              final updatedShorebirdYamlFile = await shorebirdYamlFileFromAab(
                aabFile,
              );
              expect(
                updatedShorebirdYamlFile.readAsStringSync(),
                'app_id: $appId\n',
              );
            });
          });

          group('when target channel is not production', () {
            test('sets shorebird.yaml channel to target channel', () async {
              aabFile = await createAabFile(channel: null);
              await runWithOverrides(
                () =>
                    command.setChannelOnAab(aabFile: aabFile, channel: 'live'),
              );

              final updatedShorebirdYamlFile = await shorebirdYamlFileFromAab(
                aabFile,
              );
              expect(updatedShorebirdYamlFile.readAsStringSync(), '''
app_id: $appId
channel: live
''');
            });
          });
        });

        group('when channel is set to target channel', () {
          test('does not attempt to set channel', () async {
            aabFile = await createAabFile(channel: track.channel);
            final originalModificationTime = aabFile.statSync().modified;
            await runWithOverrides(
              () => command.setChannelOnAab(
                aabFile: aabFile,
                channel: track.channel,
              ),
            );

            final updatedShorebirdYamlFile = await shorebirdYamlFileFromAab(
              aabFile,
            );
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
            aabFile = await createAabFile(channel: 'dev');
            await runWithOverrides(
              () => command.setChannelOnAab(
                aabFile: aabFile,
                channel: track.channel,
              ),
            );

            final updatedShorebirdYamlFile = await shorebirdYamlFileFromAab(
              aabFile,
            );
            expect(updatedShorebirdYamlFile.readAsStringSync(), '''
app_id: $appId
channel: ${track.channel}
''');
          });
        });
      });

      group('when querying for release artifact fails', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
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
      });

      group('when downloading release artifact fails', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => logger.err('$exception')).called(1);
        });
      });

      group('when unable to find shorebird.yaml', () {
        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => progress.fail('Exception: Unable to find shorebird.yaml'),
          ).called(1);
        });
      });

      group('when extracting metadata fails', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);
        });

        test('exits with code 70', () async {
          final exception = Exception('oops');
          when(() => bundletool.getPackageName(any())).thenThrow(exception);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => bundletool.getPackageName(aabPath())).called(1);
        });
      });

      group('when building apks fails', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          final exception = Exception('oops');
          when(
            () => bundletool.buildApks(
              bundle: any(named: 'bundle'),
              output: any(named: 'output'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => bundletool.buildApks(bundle: aabPath(), output: apksPath()),
          ).called(1);
        });
      });

      group('when installing apks fails', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          final exception = Exception('oops');
          when(
            () => bundletool.installApks(apks: any(named: 'apks')),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => bundletool.installApks(apks: apksPath())).called(1);
        });
      });

      group('when clearing app data fails', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          final exception = Exception('oops');
          when(
            () => adb.clearAppData(package: any(named: 'package')),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => adb.clearAppData(package: packageName)).called(1);
        });
      });

      group('when starting app fails', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          final exception = Exception('oops');
          when(
            () => adb.startApp(package: any(named: 'package')),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => adb.startApp(package: packageName)).called(1);
        });
      });

      group('when logcat process fails', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          when(() => process.exitCode).thenAnswer((_) async => 1);
        });

        test('exits with non-zero exit code', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(1));
          verify(() => adb.logcat(filter: 'flutter')).called(1);
        });
      });

      test('pipes stdout output to logger', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(setupAndroidShorebirdYaml);

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
        ).thenAnswer(setupAndroidShorebirdYaml);

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

      test('handles non-UTF8 bytes in output without throwing', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(setupAndroidShorebirdYaml);

        final completer = Completer<int>();
        when(() => process.exitCode).thenAnswer((_) => completer.future);
        // Create byte sequences with invalid UTF-8: 0xFF is not valid in UTF-8
        // "Hello" + 0xFF + "!" for stdout, "Error" + 0xFF + "!" for stderr
        when(
          () => process.stdout,
        ).thenAnswer(
          (_) => Stream.value([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xFF, 0x21]),
        );
        when(
          () => process.stderr,
        ).thenAnswer(
          (_) => Stream.value([0x45, 0x72, 0x72, 0x6F, 0x72, 0xFF, 0x21]),
        );
        final result = runWithOverrides(command.run);
        completer.complete(0);
        await expectLater(await result, equals(ExitCode.success.code));
        // The invalid bytes should be replaced with the replacement character
        verify(() => logger.info('Hello\uFFFD!')).called(1);
        verify(() => logger.err('Error\uFFFD!')).called(1);
      });

      group('when in a shorebird project without flavors', () {
        setUp(() {
          when(
            () => shorebirdEnv.getShorebirdYaml(),
          ).thenReturn(const ShorebirdYaml(appId: 'test-app-id'));
          when(() => argResults.wasParsed('app-id')).thenReturn(false);
          when(() => argResults['app-id']).thenReturn(null);
        });

        test('does not prompt or query for app', () async {
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
      });

      group('when in shorebird project with flavors', () {
        setUp(() {
          when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
            const ShorebirdYaml(
              appId: 'test-app-id',
              flavors: {'dev': 'dev-app-id', 'prod': 'prod-app-id'},
            ),
          );
          when(() => argResults.wasParsed('app-id')).thenReturn(false);
          when(() => argResults['app-id']).thenReturn(null);
          when(
            () =>
                logger.chooseOne<String>(any(), choices: any(named: 'choices')),
          ).thenReturn('dev');
        });

        test('prompts for the flavor', () async {
          await runWithOverrides(command.run);

          verify(
            () => logger.chooseOne<String>(any(), choices: ['dev', 'prod']),
          ).called(1);
        });
      });

      group('when app-id is not specified', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          when(() => argResults.wasParsed('app-id')).thenReturn(false);
          when(() => argResults['app-id']).thenReturn(null);
          when(
            () => logger.chooseOne<AppMetadata>(
              any(),
              choices: any(named: 'choices'),
              display: any(named: 'display'),
            ),
          ).thenReturn(app);
        });

        test('queries for apps', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          final captured =
              verify(
                    () => logger.chooseOne<AppMetadata>(
                      any(),
                      choices: any(named: 'choices'),
                      display: captureAny(named: 'display'),
                    ),
                  ).captured.single
                  as String Function(AppMetadata);
          expect(captured(app), equals(app.displayName));
          verify(() => codePushClientWrapper.getApps()).called(1);
        });
      });

      group('when release-version is not specified', () {
        late Release otherRelease;

        setUp(() {
          otherRelease = MockRelease();
          when(() => otherRelease.appId).thenReturn(appId);
          when(() => otherRelease.version).thenReturn(releaseVersion);
          when(() => otherRelease.createdAt).thenReturn(DateTime(2023));
          when(() => otherRelease.displayName).thenReturn('2.0.0+1');
          when(() => otherRelease.platformStatuses).thenReturn({
            ReleasePlatform.macos: ReleaseStatus.active,
            ReleasePlatform.windows: ReleaseStatus.active,
          });
          when(() => argResults['release-version']).thenReturn(null);
          when(() => argResults['platform']).thenReturn(releasePlatform.name);
          when(
            () => logger.chooseOne<Release>(
              any(),
              choices: any(named: 'choices'),
              display: any(named: 'display'),
            ),
          ).thenReturn(release);
          when(
            () => codePushClientWrapper.getReleases(
              appId: any(named: 'appId'),
              sideloadableOnly: any(named: 'sideloadableOnly'),
            ),
          ).thenAnswer((_) async => [release, otherRelease]);
        });

        test('only prompts for release versions that '
            'support the current platform', () async {
          await runWithOverrides(command.run);
          final releases =
              verify(
                    () => logger.chooseOne<Release>(
                      any(),
                      choices: captureAny(named: 'choices'),
                      display: any(named: 'display'),
                    ),
                  ).captured.single
                  as List<Release>;
          expect(releases.length, equals(1));
          expect(releases.first.version, equals(releaseVersion));
        });
      });

      group('when platform is not specified', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);
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
        });

        test('prompts for platforms', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          final platforms =
              verify(
                    () => logger.chooseOne<String>(
                      any(),
                      choices: captureAny(named: 'choices'),
                      display: any(named: 'display'),
                    ),
                  ).captured.single
                  as List<String>;
          expect(
            platforms,
            equals([
              ReleasePlatform.android.displayName,
              ReleasePlatform.ios.displayName,
            ]),
          );
        });
      });

      group('when no apps are found', () {
        setUp(() {
          when(() => argResults.wasParsed('app-id')).thenReturn(false);
          when(() => argResults['app-id']).thenReturn(null);
          when(
            () => codePushClientWrapper.getApps(),
          ).thenAnswer((_) async => []);
        });

        test('exits early with success code', () async {
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
      });

      group('when no releases are found', () {
        setUp(() {
          when(() => argResults['release-version']).thenReturn(null);
          when(
            () => codePushClientWrapper.getReleases(
              appId: any(named: 'appId'),
              sideloadableOnly: any(named: 'sideloadableOnly'),
            ),
          ).thenAnswer((_) async => []);
        });

        test('logs error message exits early', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.usage.code));
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
          verify(
            () => logger.err('No previewable Android releases found'),
          ).called(1);
        });
      });

      group('when release-version is not specified', () {
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          when(() => argResults['release-version']).thenReturn(null);
          when(
            () => logger.chooseOne<Release>(
              any(),
              choices: any(named: 'choices'),
              display: any(named: 'display'),
            ),
          ).thenReturn(release);
        });

        test('queries for releases', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          final captured =
              verify(
                    () => logger.chooseOne<Release>(
                      any(),
                      choices: any(named: 'choices'),
                      display: captureAny(named: 'display'),
                    ),
                  ).captured.single
                  as String Function(Release);
          expect(captured(release), equals('$releaseVersion  (Jan 1)'));
          verify(
            () => codePushClientWrapper.getReleases(
              appId: appId,
              sideloadableOnly: true,
            ),
          ).called(1);
        });
      });

      test('forwards deviceId to adb and bundletool', () async {
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer(setupAndroidShorebirdYaml);

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
          () => adb.logcat(
            filter: any(named: 'filter'),
            deviceId: deviceId,
          ),
        ).called(1);
      });

      group('when fetching the artifact fails', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('returns error and logs', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => logger.err('Error getting release artifact: Exception: oops'),
          ).called(1);
        });
      });
    });

    group('ios', () {
      const releaseArtifactUrl = 'https://example.com/runner.app';
      const releasePlatform = ReleasePlatform.ios;
      late Devicectl devicectl;
      late IOSDeploy iosDeploy;

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

        when(() => releaseArtifact.id).thenReturn(iosArtifactId);
        when(() => appleDevice.name).thenReturn('iPhone 12');
        when(() => appleDevice.udid).thenReturn('12345678-1234567890ABCDEF');
        when(() => argResults['platform']).thenReturn(releasePlatform.name);
        when(
          () => artifactManager.downloadWithProgressUpdates(
            any(),
            message: any(named: 'message'),
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
          () => devicectl.deviceForLaunch(deviceId: any(named: 'deviceId')),
        ).thenAnswer((_) async => null);
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
        when(() => releaseArtifact.arch).thenReturn('app');
        when(() => platform.isMacOS).thenReturn(true);
      });

      test('ensures ios-deploy is installed', () async {
        await runWithOverrides(command.run);
        verify(() => iosDeploy.installIfNeeded()).called(1);
      });

      group('when querying for release artifact fails', () {
        setUp(() {
          final exception = Exception('oops');
          when(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
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
      });

      group('when downloading release artifact fails', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => logger.err('$exception')).called(1);
        });
      });

      group('when extracting release artifact fails', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => logger.err('$exception')).called(1);
        });
      });

      group('when unable to find shorebird.yaml', () {
        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => progress.fail('Exception: Unable to find shorebird.yaml'),
          ).called(1);
          verifyNever(
            () => iosDeploy.installAndLaunchApp(bundlePath: iosRunnerPath()),
          );
        });
      });

      group('when device-id arg is provided', () {
        const devicectlDeviceId = '12345';
        setUp(() {
          when(() => appleDevice.udid).thenReturn(devicectlDeviceId);
          when(
            () => devicectl.listAvailableIosDevices(),
          ).thenAnswer((_) async => [appleDevice]);
        });

        test('uses matching devicectl device if found', () async {
          when(
            () => argResults['device-id'],
          ).thenAnswer((_) => devicectlDeviceId);

          setupIOSShorebirdYaml();
          await runWithOverrides(command.run);

          verifyNever(
            () => iosDeploy.installAndLaunchApp(bundlePath: iosRunnerPath()),
          );
        });

        group('when no devicectl devices have matching id', () {
          setUp(() {
            when(
              () => argResults['device-id'],
            ).thenAnswer((_) => 'not-a-device-id');
            setupIOSShorebirdYaml();
          });

          test('falls back to ios-deploy', () async {
            await runWithOverrides(command.run);

            verify(
              () => progress.complete(
                '''No iOS 17+ device found, looking for devices running iOS 16 or lower''',
              ),
            ).called(1);
            verify(
              () => iosDeploy.installAndLaunchApp(
                bundlePath: iosRunnerPath(),
                deviceId: 'not-a-device-id',
              ),
            ).called(1);
          });
        });
      });

      group('when devicectl returns a usable device', () {
        setUp(() {
          when(
            () => devicectl.deviceForLaunch(deviceId: any(named: 'deviceId')),
          ).thenAnswer((_) async => appleDevice);
          setupIOSShorebirdYaml();
        });

        test('uses devicectl', () async {
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
      });

      group('when install/launch throws', () {
        setUp(() {
          setupIOSShorebirdYaml();
          final exception = Exception('oops');
          when(
            () => iosDeploy.installAndLaunchApp(
              bundlePath: any(named: 'bundlePath'),
              deviceId: any(named: 'deviceId'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => iosDeploy.installAndLaunchApp(bundlePath: iosRunnerPath()),
          ).called(1);
        });
      });

      group('when install/launch succeeds (production)', () {
        late File shorebirdYaml;
        setUp(() {
          shorebirdYaml = setupIOSShorebirdYaml();
          when(
            () => iosDeploy.installAndLaunchApp(
              bundlePath: any(named: 'bundlePath'),
              deviceId: any(named: 'deviceId'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('exits with code 0', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => iosDeploy.installAndLaunchApp(bundlePath: iosRunnerPath()),
          ).called(1);
          expect(shorebirdYaml.readAsStringSync(), equals('app_id: $appId'));
        });
      });

      group('when install/launch succeeds (staging)', () {
        late File shorebirdYaml;
        setUp(() {
          when(
            () => argResults['track'],
          ).thenReturn(DeploymentTrack.staging.channel);
          shorebirdYaml =
              File(
                  p.join(
                    iosRunnerPath(),
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
        });

        test('exits with code 0', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => iosDeploy.installAndLaunchApp(bundlePath: iosRunnerPath()),
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

      group('when fetching the artifact fails', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('returns error and logs', () async {
          when(
            () => iosDeploy.installAndLaunchApp(
              bundlePath: any(named: 'bundlePath'),
              deviceId: any(named: 'deviceId'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => logger.err('Error getting release artifact: Exception: oops'),
          ).called(1);
        });
      });

      group('when the android release is not sideloadable', () {
        setUp(() {
          final releaseWithAllPlatforms = MockRelease();
          when(() => releaseWithAllPlatforms.id).thenReturn(releaseId);
          when(
            () => releaseWithAllPlatforms.version,
          ).thenReturn(releaseVersion);
          when(() => releaseWithAllPlatforms.platformStatuses).thenReturn({
            ReleasePlatform.ios: ReleaseStatus.active,
            ReleasePlatform.android: ReleaseStatus.active,
          });
          when(
            () => release.platformStatuses,
          ).thenReturn({ReleasePlatform.ios: ReleaseStatus.active});
          when(
            () => codePushClientWrapper.getReleases(
              appId: any(named: 'appId'),
              sideloadableOnly: true,
            ),
          ).thenAnswer((_) async => [release]);
          when(
            () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => [releaseWithAllPlatforms]);
        });

        test('does not warn since the user explicitly asked for iOS', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.software.code));

          verifyNever(
            () => logger.warn(
              '''The ${ReleasePlatform.android.displayName} artifact for this release is not previewable.''',
            ),
          );
        });
      });

      group('when the ios release is not sideloadable', () {
        setUp(() {
          final releaseWithAllPlatforms = MockRelease();
          when(() => releaseWithAllPlatforms.id).thenReturn(releaseId);
          when(
            () => releaseWithAllPlatforms.version,
          ).thenReturn(releaseVersion);
          when(() => releaseWithAllPlatforms.platformStatuses).thenReturn({
            ReleasePlatform.ios: ReleaseStatus.active,
            ReleasePlatform.android: ReleaseStatus.active,
          });
          when(
            () => release.platformStatuses,
          ).thenReturn({ReleasePlatform.android: ReleaseStatus.active});
          when(
            () => codePushClientWrapper.getReleases(
              appId: any(named: 'appId'),
              sideloadableOnly: true,
            ),
          ).thenAnswer((_) async => [release]);
          when(
            () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => [releaseWithAllPlatforms]);
        });

        test(
          'prints error that platform is not previewable and exits',
          () async {
            await expectLater(
              runWithOverrides(command.run),
              completion(equals(ExitCode.usage.code)),
            );

            verify(
              () => logger.err('No previewable iOS releases found'),
            ).called(1);
          },
        );
      });
    });

    group('linux', () {
      const executableName = 'my_app';
      const releaseArtifactUrl = 'https://example.com/Release.zip';
      const releaseArtifactId = 42;

      late File releaseArtifactFile;
      late ReleaseArtifact linuxReleaseArtifact;
      late ShorebirdProcess shorebirdProcess;
      late Process process;

      void setupPreviewArtifact({required Directory baseDirectory}) {
        File(
            p.join(
              baseDirectory.path,
              'data',
              'flutter_assets',
              'shorebird.yaml',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('app_id: $appId', flush: true);
        File(
          p.join(baseDirectory.path, executableName),
        ).createSync(recursive: true);
      }

      R runWithOverrides<R>(R Function() body) {
        return HttpOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              artifactManagerRef.overrideWith(() => artifactManager),
              authRef.overrideWith(() => auth),
              cacheRef.overrideWith(() => cache),
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              httpClientRef.overrideWith(() => httpClient),
              loggerRef.overrideWith(() => logger),
              platformRef.overrideWith(() => platform),
              processRef.overrideWith(() => shorebirdProcess),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
      }

      setUp(() {
        shorebirdProcess = MockShorebirdProcess();
        process = MockProcess();
        linuxReleaseArtifact = MockReleaseArtifact();

        final tempDir = Directory.systemTemp.createTempSync();
        releaseArtifactFile = File(p.join(tempDir.path, 'Release.zip'));

        when(
          () => process.stdout,
        ).thenAnswer((_) => Stream.value(utf8.encode('hello world')));
        when(
          () => process.stderr,
        ).thenAnswer((_) => Stream.value(utf8.encode('hello error')));
        when(
          () => process.exitCode,
        ).thenAnswer((_) async => ExitCode.success.code);

        when(
          () => shorebirdProcess.start(any(), any()),
        ).thenAnswer((_) async => process);
        when(() => shorebirdProcess.run(any(), any())).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: null,
            stderr: null,
          ),
        );

        when(() => linuxReleaseArtifact.id).thenReturn(releaseArtifactId);
        when(() => linuxReleaseArtifact.url).thenReturn(releaseArtifactUrl);
        when(() => linuxReleaseArtifact.arch).thenReturn('app');

        when(
          () => release.platformStatuses,
        ).thenReturn({ReleasePlatform.linux: ReleaseStatus.active});

        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenAnswer((_) async => linuxReleaseArtifact);
      });

      group('when getting release artifact fails', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('returns code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: appId,
              releaseId: releaseId,
              arch: primaryLinuxReleaseArtifactArch,
              platform: ReleasePlatform.linux,
            ),
          ).called(1);
        });
      });

      group('when downloading release artifact fails', () {
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('returns code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => artifactManager.downloadWithProgressUpdates(
              Uri.parse(releaseArtifactUrl),
              message: 'Downloading app',
            ),
          ).called(1);
        });
      });

      group('when setting channel on app fails', () {
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenAnswer((_) async => releaseArtifactFile);
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer((_) async {});
        });

        test('returns code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => progress.fail('Exception: Unable to find shorebird.yaml'),
          ).called(1);
        });
      });

      group('when preview artifact is not cached', () {
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenAnswer((_) async => releaseArtifactFile);
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer((invocation) async {
            final outDirectory =
                invocation.namedArguments[#outputDirectory] as Directory;
            setupPreviewArtifact(baseDirectory: outDirectory);
          });
        });

        test('downloads and launches artifact', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));

          verify(
            () => artifactManager.downloadWithProgressUpdates(
              Uri.parse(releaseArtifactUrl),
              message: 'Downloading app',
            ),
          ).called(1);
          verify(
            () =>
                shorebirdProcess.start(any(that: endsWith(executableName)), []),
          ).called(1);
          verify(() => logger.info('hello world')).called(1);
          verify(() => logger.err('hello error')).called(1);
        });
      });

      group('when preview artifact is cached', () {
        setUp(() {
          setupPreviewArtifact(
            baseDirectory: Directory(
              p.join(
                previewDirectory.path,
                'linux_${releaseVersion}_$releaseArtifactId',
              ),
            ),
          );
        });

        test('launches cached artifact', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));

          verifyNever(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          );
          verify(() => shorebirdProcess.run('chmod', any())).called(1);
          verify(
            () =>
                shorebirdProcess.start(any(that: endsWith(executableName)), []),
          ).called(1);
          verify(() => logger.info('hello world')).called(1);
          verify(() => logger.err('hello error')).called(1);
        });
      });

      test('handles non-UTF8 bytes in output without throwing', () async {
        setupPreviewArtifact(
          baseDirectory: Directory(
            p.join(
              previewDirectory.path,
              'linux_${releaseVersion}_$releaseArtifactId',
            ),
          ),
        );
        // Create byte sequences with invalid UTF-8: 0xFF is not valid in UTF-8
        // "Hello" + 0xFF + "!" for stdout, "Error" + 0xFF + "!" for stderr
        when(
          () => process.stdout,
        ).thenAnswer(
          (_) => Stream.value([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xFF, 0x21]),
        );
        when(
          () => process.stderr,
        ).thenAnswer(
          (_) => Stream.value([0x45, 0x72, 0x72, 0x6F, 0x72, 0xFF, 0x21]),
        );

        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        // The invalid bytes should be replaced with the replacement character
        verify(() => logger.info('Hello\uFFFD!')).called(1);
        verify(() => logger.err('Error\uFFFD!')).called(1);
      });
    });

    group('macos', () {
      const releaseArtifactUrl = 'https://example.com/sample.app';
      const releasePlatform = ReleasePlatform.macos;

      late Ditto ditto;
      late Open open;

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
              dittoRef.overrideWith(() => ditto),
              httpClientRef.overrideWith(() => httpClient),
              loggerRef.overrideWith(() => logger),
              platformRef.overrideWith(() => platform),
              openRef.overrideWith(() => open),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
      }

      File setupMacosShorebirdYaml() =>
          File(
              p.join(
                macosAppPath(),
                'Contents',
                'Frameworks',
                'App.framework',
                'Resources',
                'flutter_assets',
                'shorebird.yaml',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('app_id: $appId', flush: true);

      setUp(() {
        ditto = MockDitto();
        open = MockOpen();

        when(() => releaseArtifact.id).thenReturn(macosArtifactId);
        when(() => argResults['platform']).thenReturn(releasePlatform.name);
        when(
          () => artifactManager.downloadWithProgressUpdates(
            any(),
            message: any(named: 'message'),
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
          () => ditto.extract(
            source: any(named: 'source'),
            destination: any(named: 'destination'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => release.platformStatuses,
        ).thenReturn({ReleasePlatform.macos: ReleaseStatus.active});
        when(() => releaseArtifact.url).thenReturn(releaseArtifactUrl);
        when(() => releaseArtifact.arch).thenReturn('app');
        when(() => platform.isMacOS).thenReturn(true);
        when(
          () => open.newApplication(path: any(named: 'path')),
        ).thenAnswer((_) async => Stream.value(utf8.encode('hello world')));
      });

      group('when querying for release artifact fails', () {
        setUp(() {
          final exception = Exception('oops');
          when(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: appId,
              releaseId: releaseId,
              arch: 'app',
              platform: releasePlatform,
            ),
          ).called(1);
        });
      });

      group('when downloading release artifact fails', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => logger.err('$exception')).called(1);
        });
      });

      group('when extracting release artifact fails', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => ditto.extract(
              source: any(named: 'source'),
              destination: any(named: 'destination'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(() => logger.err('$exception')).called(1);
        });
      });

      group('staging', () {
        late File shorebirdYaml;
        setUp(() {
          when(
            () => argResults['track'],
          ).thenReturn(DeploymentTrack.staging.channel);
          shorebirdYaml = setupMacosShorebirdYaml();
        });

        test('sets channel in shorebird.yaml', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));

          expect(
            shorebirdYaml.readAsStringSync(),
            equals('''
app_id: $appId
channel: ${DeploymentTrack.staging.channel}
'''),
          );
        });
      });

      group('when process completes with exit code 0', () {
        setUp(setupMacosShorebirdYaml);

        test('completes successfully', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(() => logger.info('hello world')).called(1);
        });
      });

      group('log output', () {
        final rawLogOutput =
            '''
2025-01-31 10:15:29.807 Df macos_sandbox[33557:2cc3d] [com.apple.network:] networkd_settings_read_from_file initialized networkd settings by reading plist directly

2025-01-31 10:15:29.807 Df macos_sandbox[33557:2cc3d] [com.apple.network:path] nw_path_libinfo_path_check [5E11C960-BB0A-456A-8024-620DAB6CCF17 Hostname#941210b4:0 tcp, legacy-socket, attribution: developer]
        libinfo check path: satisfied (Path is satisfied), interface: en0, ipv4, dns

2025-01-31 10:15:29.808 Df macos_sandbox[33557:2cc12] [dev.shorebird:updater::updater] [shorebird] Reporting successful launch.
'''
                .split('\n');

        setUp(() {
          setupMacosShorebirdYaml();
          when(() => open.newApplication(path: any(named: 'path'))).thenAnswer(
            (_) async => Stream.fromIterable(rawLogOutput.map(utf8.encode)),
          );
        });

        test('removes noisy lines from log output', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));

          verify(
            () => logger.info(
              '''[dev.shorebird:updater::updater] [shorebird] Reporting successful launch.''',
            ),
          ).called(1);
          verifyNever(
            () => logger.info(
              any(that: contains('networkd_settings_read_from_file')),
            ),
          );
          verifyNever(
            () =>
                logger.info(any(that: contains('nw_path_libinfo_path_check'))),
          );
        });
      });

      group('non-UTF8 handling', () {
        setUp(setupMacosShorebirdYaml);

        test('handles non-UTF8 bytes in log stream without throwing', () async {
          // Create bytes with invalid UTF-8: 0xFF is not valid in UTF-8
          // Simulates a macOS log line with invalid bytes
          final invalidUtf8Bytes = [
            ...utf8.encode(
              '2025-01-31 09:53:22.889 Df app[22535:1d268] [shorebird] Hello',
            ),
            0xFF,
            0x0A, // newline
          ];
          when(() => open.newApplication(path: any(named: 'path'))).thenAnswer(
            (_) async => Stream.value(invalidUtf8Bytes),
          );

          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          // The invalid byte should be replaced with the replacement character
          verify(() => logger.info('[shorebird] Hello\uFFFD')).called(1);
        });
      });
    });

    group('windows', () {
      const releaseArtifactUrl = 'https://example.com/Release.zip';
      const releaseArtifactId = 42;

      late File releaseArtifactFile;
      late ReleaseArtifact windowsReleaseArtifact;
      late ShorebirdProcess shorebirdProcess;
      late Process process;
      late Directory windowsReleaseDirectory;

      R runWithOverrides<R>(R Function() body) {
        return HttpOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              artifactManagerRef.overrideWith(() => artifactManager),
              authRef.overrideWith(() => auth),
              cacheRef.overrideWith(() => cache),
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              httpClientRef.overrideWith(() => httpClient),
              loggerRef.overrideWith(() => logger),
              platformRef.overrideWith(() => platform),
              processRef.overrideWith(() => shorebirdProcess),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
      }

      void createShorebirdYaml({String? channel}) {
        final shorebirdYaml =
            File(
                p.join(
                  windowsReleaseDirectory.path,
                  'data',
                  'flutter_assets',
                  'shorebird.yaml',
                ),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('app_id: $appId', flush: true);
        if (channel != null) {
          shorebirdYaml.writeAsStringSync(
            'channel: $channel',
            flush: true,
            mode: FileMode.append,
          );
        }
      }

      setUp(() {
        shorebirdProcess = MockShorebirdProcess();
        process = MockProcess();
        windowsReleaseArtifact = MockReleaseArtifact();

        final tempDir = Directory.systemTemp.createTempSync();
        releaseArtifactFile = File(p.join(tempDir.path, 'Release.zip'));

        windowsReleaseDirectory = Directory(
          p.join(
            previewDirectory.path,
            'windows_${releaseVersion}_$releaseArtifactId.exe',
          ),
        );

        when(
          () => process.stdout,
        ).thenAnswer((_) => Stream.value(utf8.encode('hello world')));
        when(
          () => process.stderr,
        ).thenAnswer((_) => Stream.value(utf8.encode('hello error')));
        when(
          () => process.exitCode,
        ).thenAnswer((_) async => ExitCode.success.code);

        when(
          () => shorebirdProcess.start(any(), any()),
        ).thenAnswer((_) async => process);

        when(() => windowsReleaseArtifact.id).thenReturn(releaseArtifactId);
        when(() => windowsReleaseArtifact.url).thenReturn(releaseArtifactUrl);
        when(() => windowsReleaseArtifact.arch).thenReturn('app');

        when(
          () => release.platformStatuses,
        ).thenReturn({ReleasePlatform.windows: ReleaseStatus.active});

        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenAnswer((_) async => windowsReleaseArtifact);
      });

      group('when getting release artifact fails', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('returns code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => codePushClientWrapper.getReleaseArtifact(
              appId: appId,
              releaseId: releaseId,
              arch: primaryWindowsReleaseArtifactArch,
              platform: ReleasePlatform.windows,
            ),
          ).called(1);
        });
      });

      group('when downloading release artifact fails', () {
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('returns code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.software.code));
          verify(
            () => artifactManager.downloadWithProgressUpdates(
              Uri.parse(releaseArtifactUrl),
              message: 'Downloading app',
            ),
          ).called(1);
        });
      });

      group('when preview artifact is not cached', () {
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenAnswer((_) async => releaseArtifactFile);
          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer((invocation) async {
            final outDirectory =
                invocation.namedArguments[#outputDirectory] as Directory;
            File(
              p.join(outDirectory.path, 'runner.exe'),
            ).createSync(recursive: true);
            createShorebirdYaml();
          });
        });

        test('downloads and launches artifact', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));

          verify(
            () => artifactManager.downloadWithProgressUpdates(
              Uri.parse(releaseArtifactUrl),
              message: 'Downloading app',
            ),
          ).called(1);
          verify(
            () => shorebirdProcess.start(any(that: endsWith('runner.exe')), []),
          ).called(1);
          verify(() => logger.info('hello world')).called(1);
          verify(() => logger.err('hello error')).called(1);
        });
      });

      group('when preview artifact is cached', () {
        setUp(() {
          File(
            p.join(windowsReleaseDirectory.path, 'runner.exe'),
          ).createSync(recursive: true);
          createShorebirdYaml();
        });

        test('launches cached artifact', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));

          verifyNever(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
              outputPath: any(named: 'outputPath'),
            ),
          );
          verify(
            () => shorebirdProcess.start(any(that: endsWith('runner.exe')), []),
          ).called(1);
          verify(() => logger.info('hello world')).called(1);
          verify(() => logger.err('hello error')).called(1);
        });
      });

      test('handles non-UTF8 bytes in output without throwing', () async {
        File(
          p.join(windowsReleaseDirectory.path, 'runner.exe'),
        ).createSync(recursive: true);
        createShorebirdYaml();
        // Create byte sequences with invalid UTF-8: 0xFF is not valid in UTF-8
        // "Hello" + 0xFF + "!" for stdout, "Error" + 0xFF + "!" for stderr
        when(
          () => process.stdout,
        ).thenAnswer(
          (_) => Stream.value([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xFF, 0x21]),
        );
        when(
          () => process.stderr,
        ).thenAnswer(
          (_) => Stream.value([0x45, 0x72, 0x72, 0x6F, 0x72, 0xFF, 0x21]),
        );

        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        // The invalid bytes should be replaced with the replacement character
        verify(() => logger.info('Hello\uFFFD!')).called(1);
        verify(() => logger.err('Error\uFFFD!')).called(1);
      });
    });

    group('when no platform is specified', () {
      const iosReleaseArtifactUrl = 'https://example.com/runner.app';
      const macosReleaseArtifactUrl = 'https://example.com/sample.app';
      late Devicectl devicectl;
      late IOSDeploy iosDeploy;

      const androidReleaseArtifactUrl = 'https://example.com/release.aab';
      const androidPackageName = 'com.example.app';

      late ReleaseArtifact iosReleaseArtifact;
      late ReleaseArtifact androidReleaseArtifact;
      late ReleaseArtifact macosReleaseArtifact;

      late Adb adb;
      late Bundletool bundletool;
      late Process process;

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
        adb = MockAdb();
        bundletool = MockBundleTool();
        process = MockProcess();
        devicectl = MockDevicectl();
        iosDeploy = MockIOSDeploy();
        iosReleaseArtifact = MockReleaseArtifact();
        androidReleaseArtifact = MockReleaseArtifact();
        macosReleaseArtifact = MockReleaseArtifact();

        when(() => appleDevice.name).thenReturn('iPhone 12');
        when(() => appleDevice.udid).thenReturn('12345678-1234567890ABCDEF');
        when(
          () => artifactManager.downloadWithProgressUpdates(
            any(),
            message: any(named: 'message'),
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
          () => devicectl.deviceForLaunch(deviceId: any(named: 'deviceId')),
        ).thenAnswer((_) async => null);
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

        when(() => iosReleaseArtifact.id).thenReturn(iosArtifactId);
        when(() => iosReleaseArtifact.url).thenReturn(iosReleaseArtifactUrl);

        when(() => macosReleaseArtifact.id).thenReturn(macosArtifactId);
        when(
          () => macosReleaseArtifact.url,
        ).thenReturn(macosReleaseArtifactUrl);

        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: ReleasePlatform.ios,
          ),
        ).thenAnswer((_) async => iosReleaseArtifact);

        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: ReleasePlatform.macos,
          ),
        ).thenAnswer((_) async => macosReleaseArtifact);

        when(() => androidReleaseArtifact.id).thenReturn(androidArtifactId);
        when(
          () => androidReleaseArtifact.url,
        ).thenReturn(androidReleaseArtifactUrl);

        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: ReleasePlatform.android,
          ),
        ).thenAnswer((_) async => androidReleaseArtifact);

        when(() => platform.isMacOS).thenReturn(true);
      });

      group('when the user chooses ios at the prompt', () {
        setUp(() {
          when(
            () => logger.chooseOne<String>(
              'Which platform would you like to preview?',
              choices: any(named: 'choices'),
            ),
          ).thenReturn(ReleasePlatform.ios.displayName);

          setupIOSShorebirdYaml()
            ..createSync(recursive: true)
            ..writeAsStringSync('app_id: $appId', flush: true);

          when(
            () => iosDeploy.installAndLaunchApp(
              bundlePath: any(named: 'bundlePath'),
              deviceId: any(named: 'deviceId'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('exits with success and calls install and launch app', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));

          verify(
            () => iosDeploy.installAndLaunchApp(
              bundlePath: any(named: 'bundlePath'),
              deviceId: any(named: 'deviceId'),
            ),
          ).called(1);
        });

        group('when the android release is not sideloadable', () {
          setUp(() {
            final releaseWithAllPlatforms = MockRelease();
            when(() => releaseWithAllPlatforms.id).thenReturn(releaseId);
            when(
              () => releaseWithAllPlatforms.version,
            ).thenReturn(releaseVersion);
            when(() => releaseWithAllPlatforms.platformStatuses).thenReturn({
              ReleasePlatform.ios: ReleaseStatus.active,
              ReleasePlatform.android: ReleaseStatus.active,
            });
            when(
              () => release.platformStatuses,
            ).thenReturn({ReleasePlatform.ios: ReleaseStatus.active});
            when(
              () => codePushClientWrapper.getReleases(
                appId: any(named: 'appId'),
                sideloadableOnly: true,
              ),
            ).thenAnswer((_) async => [release]);
            when(
              () =>
                  codePushClientWrapper.getReleases(appId: any(named: 'appId')),
            ).thenAnswer((_) async => [releaseWithAllPlatforms]);
          });

          test('warns about the platform and goes directly to iOS', () async {
            final exitCode = await runWithOverrides(command.run);
            expect(exitCode, equals(ExitCode.success.code));

            verify(
              () => logger.warn(
                '''The ${ReleasePlatform.android.displayName} artifact for this release is not previewable.''',
              ),
            ).called(1);
          });
        });
      });

      group('when the user chooses android at the prompt', () {
        const deviceId = '1234';

        setUp(() {
          when(
            () => logger.chooseOne<String>(
              'Which platform would you like to preview?',
              choices: any(named: 'choices'),
            ),
          ).thenReturn(ReleasePlatform.android.displayName);

          when(
            () => artifactManager.extractZip(
              zipFile: any(named: 'zipFile'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer(setupAndroidShorebirdYaml);

          when(() => argResults['device-id']).thenReturn(deviceId);

          when(
            () => bundletool.getPackageName(any()),
          ).thenAnswer((_) async => androidPackageName);
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
          when(() => process.stdout).thenAnswer((_) => const Stream.empty());
          when(() => process.stderr).thenAnswer((_) => const Stream.empty());
          when(() => releaseArtifact.url).thenReturn(androidReleaseArtifactUrl);
          when(
            () => process.exitCode,
          ).thenAnswer((_) async => ExitCode.success.code);

          unawaited(createAabFile(channel: null));
        });

        test('exits with success and calls install and launch app', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));

          verify(
            () => bundletool.installApks(
              apks: any(named: 'apks'),
              deviceId: deviceId,
            ),
          ).called(1);
        });

        group('when the ios release is not sideloadable', () {
          setUp(() {
            final releaseWithAllPlatforms = MockRelease();
            when(() => releaseWithAllPlatforms.id).thenReturn(releaseId);
            when(
              () => releaseWithAllPlatforms.version,
            ).thenReturn(releaseVersion);
            when(() => releaseWithAllPlatforms.platformStatuses).thenReturn({
              ReleasePlatform.ios: ReleaseStatus.active,
              ReleasePlatform.android: ReleaseStatus.active,
            });
            when(
              () => release.platformStatuses,
            ).thenReturn({ReleasePlatform.android: ReleaseStatus.active});
            when(
              () => codePushClientWrapper.getReleases(
                appId: any(named: 'appId'),
                sideloadableOnly: true,
              ),
            ).thenAnswer((_) async => [release]);
            when(
              () =>
                  codePushClientWrapper.getReleases(appId: any(named: 'appId')),
            ).thenAnswer((_) async => [releaseWithAllPlatforms]);
          });

          test('warns about it not being previewable', () async {
            final exitCode = await runWithOverrides(command.run);
            expect(exitCode, equals(ExitCode.success.code));

            verify(
              () => logger.warn(
                '''The ${ReleasePlatform.ios.displayName} artifact for this release is not previewable.''',
              ),
            ).called(1);
          });
        });
      });
    });
  });

  group('assertPreviewableReleases', () {
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return HttpOverrides.runZoned(
        () => runScoped(body, values: {loggerRef.overrideWith(() => logger)}),
      );
    }

    setUp(() {
      logger = MockShorebirdLogger();
    });

    test('warns about non-previewable platforms', () {
      final releaseWithAllPlatforms = MockRelease();
      final release = MockRelease();

      when(() => releaseWithAllPlatforms.platformStatuses).thenReturn({
        ReleasePlatform.android: ReleaseStatus.active,
        ReleasePlatform.ios: ReleaseStatus.active,
        ReleasePlatform.linux: ReleaseStatus.active,
        ReleasePlatform.macos: ReleaseStatus.active,
        ReleasePlatform.windows: ReleaseStatus.active,
      });

      when(() => release.platformStatuses).thenReturn({
        ReleasePlatform.android: ReleaseStatus.active,
        ReleasePlatform.linux: ReleaseStatus.active,
        ReleasePlatform.windows: ReleaseStatus.active,
      });

      runWithOverrides(
        () => assertPreviewableReleases(
          releaseWithAllPlatforms: releaseWithAllPlatforms,
          release: release,
          targetPlatform: null,
        ),
      );
      verify(
        () => logger.warn(
          '''The ${ReleasePlatform.ios.displayName} artifact for this release is not previewable.''',
        ),
      ).called(1);
      verify(
        () => logger.warn(
          '''The ${ReleasePlatform.macos.displayName} artifact for this release is not previewable.''',
        ),
      ).called(1);

      verifyNever(
        () => logger.warn(
          '''The ${ReleasePlatform.android.displayName} artifact for this release is not previewable.''',
        ),
      );
      verifyNever(
        () => logger.warn(
          '''The ${ReleasePlatform.linux.displayName} artifact for this release is not previewable.''',
        ),
      );
      verifyNever(
        () => logger.warn(
          '''The ${ReleasePlatform.windows.displayName} artifact for this release is not previewable.''',
        ),
      );
    });

    test(
      'exits early when user explicitly specifies a non-previewable platform',
      () async {
        final releaseWithAllPlatforms = MockRelease();
        final release = MockRelease();

        when(() => releaseWithAllPlatforms.platformStatuses).thenReturn({
          ReleasePlatform.android: ReleaseStatus.active,
          ReleasePlatform.ios: ReleaseStatus.active,
          ReleasePlatform.linux: ReleaseStatus.active,
          ReleasePlatform.macos: ReleaseStatus.active,
          ReleasePlatform.windows: ReleaseStatus.active,
        });

        when(() => release.platformStatuses).thenReturn({
          ReleasePlatform.android: ReleaseStatus.active,
          ReleasePlatform.linux: ReleaseStatus.active,
          ReleasePlatform.windows: ReleaseStatus.active,
        });
        expect(
          () => runWithOverrides(
            () => assertPreviewableReleases(
              releaseWithAllPlatforms: releaseWithAllPlatforms,
              release: release,
              targetPlatform: ReleasePlatform.ios,
            ),
          ),
          throwsA(
            isA<ProcessExit>().having(
              (e) => e.exitCode,
              'exitCode',
              ExitCode.software.code,
            ),
          ),
        );
        verify(
          () => logger.err(
            '''The ${ReleasePlatform.ios.displayName} artifact for this release is not previewable.''',
          ),
        ).called(1);

        verifyNever(
          () => logger.warn(
            '''The ${ReleasePlatform.macos.displayName} artifact for this release is not previewable.''',
          ),
        );
        verifyNever(
          () => logger.warn(
            '''The ${ReleasePlatform.android.displayName} artifact for this release is not previewable.''',
          ),
        );
        verifyNever(
          () => logger.warn(
            '''The ${ReleasePlatform.linux.displayName} artifact for this release is not previewable.''',
          ),
        );
        verifyNever(
          () => logger.warn(
            '''The ${ReleasePlatform.windows.displayName} artifact for this release is not previewable.''',
          ),
        );
      },
    );
  });
}
