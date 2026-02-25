import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../mocks.dart';

void main() {
  group(ArtifactBuilder, () {
    late Directory projectRoot;
    late Apple apple;
    late ArtifactManager artifactManager;
    late ShorebirdLogger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdProcessResult pubGetProcessResult;
    late ArtifactBuilder builder;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          appleRef.overrideWith(() => apple),
          artifactManagerRef.overrideWith(() => artifactManager),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdAndroidArtifactsRef.overrideWith(
            () => shorebirdAndroidArtifacts,
          ),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeShorebirdProcess());
      registerFallbackValue(Directory(''));
    });

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync();
      apple = MockApple();
      artifactManager = MockArtifactManager();
      logger = MockShorebirdLogger();
      operatingSystemInterface = MockOperatingSystemInterface();
      pubGetProcessResult = MockProcessResult();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();

      when(
        () => shorebirdProcess.run('flutter', [
          '--no-version-check',
          'pub',
          'get',
          '--offline',
        ], useVendedFlutter: false),
      ).thenAnswer((_) async => pubGetProcessResult);
      when(
        () => pubGetProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => shorebirdProcess.stream(
          any(),
          any(),
          environment: any(named: 'environment'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ExitCode.success.code);

      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(
        () => operatingSystemInterface.which('flutter'),
      ).thenReturn('/path/to/flutter');
      when(() => shorebirdEnv.flutterRevision).thenReturn('1234');

      when(shorebirdEnv.getShorebirdProjectRoot).thenReturn(projectRoot);

      builder = ArtifactBuilder();
    });

    void verifyCorrectFlutterPubGet(Future<void> Function() testCall) {
      group('when flutter is installed', () {
        setUp(() {
          when(
            () => operatingSystemInterface.which('flutter'),
          ).thenReturn('/path/to/flutter');
        });

        test('runs flutter pub get with system flutter', () async {
          await testCall();

          verify(
            () => shorebirdProcess.run('flutter', [
              '--no-version-check',
              'pub',
              'get',
              '--offline',
            ], useVendedFlutter: false),
          ).called(1);
        });

        test('prints error message if system flutter pub get fails', () async {
          when(() => pubGetProcessResult.exitCode).thenReturn(1);

          await testCall();

          verify(
            () => logger.warn('''
Build was successful, but `flutter pub get` failed to run after the build completed. You may see unexpected behavior in VS Code.

Either run `flutter pub get` manually, or follow the steps in ${cannotRunInVSCodeUrl.toLink()}.
'''),
          ).called(1);
        });
      });

      group('when flutter is not installed', () {
        setUp(() {
          when(
            () => operatingSystemInterface.which('flutter'),
          ).thenReturn(null);
        });

        test('does not attempt to run flutter pub get', () async {
          await testCall();

          verifyNever(
            () => shorebirdProcess.run(
              'flutter',
              ['--no-version-check', 'pub', 'get', '--offline'],
              useVendedFlutter: false,
              runInShell: any(named: 'runInShell'),
            ),
          );
        });
      });
    }

    group('buildAppBundle', () {
      setUp(() {
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(File('app-release.aab'));
      });

      test('invokes the correct flutter build command', () async {
        await runWithOverrides(() => builder.buildAppBundle());

        verify(
          () => shorebirdProcess.stream(
            'flutter',
            ['build', 'appbundle', '--release'],
            environment: any(named: 'environment'),
            runInShell: false,
          ),
        ).called(1);
      });

      test('forward arguments to flutter build', () async {
        await runWithOverrides(
          () => builder.buildAppBundle(
            flavor: 'flavor',
            target: 'target',
            targetPlatforms: [Arch.arm64],
            args: ['--foo', 'bar'],
          ),
        );

        verify(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'appbundle',
            '--release',
            '--flavor=flavor',
            '--target=target',
            '--target-platform=android-arm64',
            '--foo',
            'bar',
          ], runInShell: false),
        ).called(1);
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        setUp(() {
          when(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'appbundle',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('adds the SHOREBIRD_PUBLIC_KEY to the environment', () async {
          await runWithOverrides(
            () => builder.buildAppBundle(
              flavor: 'flavor',
              target: 'target',
              targetPlatforms: [Arch.arm64],
              base64PublicKey: 'base64PublicKey',
            ),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'appbundle',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });

      group('when multiple artifacts are found', () {
        setUp(() {
          when(
            () => shorebirdAndroidArtifacts.findAab(
              project: any(named: 'project'),
              flavor: any(named: 'flavor'),
            ),
          ).thenThrow(
            MultipleArtifactsFoundException(
              foundArtifacts: [File('a'), File('b')],
              buildDir: 'buildDir',
            ),
          );
        });

        test('throws BuildException', () {
          expect(
            () => runWithOverrides(() => builder.buildAppBundle()),
            throwsA(
              isA<ArtifactBuildException>().having(
                (e) => e.message,
                'message',
                '''Build succeeded, but it generated multiple AABs in the build directory. (a, b)''',
              ),
            ),
          );
        });
      });

      group('when no artifacts are found', () {
        setUp(() {
          when(
            () => shorebirdAndroidArtifacts.findAab(
              project: any(named: 'project'),
              flavor: any(named: 'flavor'),
            ),
          ).thenThrow(
            const ArtifactNotFoundException(
              artifactName: 'app-release.aab',
              buildDir: 'buildDir',
            ),
          );
        });

        test('throws BuildException', () {
          expect(
            () => runWithOverrides(() => builder.buildAppBundle()),
            throwsA(
              isA<ArtifactBuildException>().having(
                (e) => e.message,
                'message',
                '''Build succeeded, but could not find the AAB in the build directory. Expected to find app-release.aab''',
              ),
            ),
          );
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
              ),
            ).thenAnswer((_) async => ExitCode.success.code);
          });

          verifyCorrectFlutterPubGet(
            () => runWithOverrides(() => builder.buildAppBundle()),
          );

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () => expectLater(
                () => runWithOverrides(() => builder.buildAppBundle()),
                throwsA(
                  isA<ArtifactBuildException>().having(
                    (e) => e.fixRecommendation,
                    'recommendation',
                    startsWith(
                      ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                        '',
                      ).substring(0, 80),
                    ),
                  ),
                ),
              ),
            );
          });
        });
      });
    });

    group('buildApk', () {
      setUp(() {
        when(
          () => shorebirdAndroidArtifacts.findApk(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(File('app-release.apk'));
      });

      test('invokes the correct flutter build command', () async {
        await runWithOverrides(() => builder.buildApk());

        verify(
          () => shorebirdProcess.stream(
            'flutter',
            ['build', 'apk', '--release'],
            environment: any(named: 'environment'),
            runInShell: false,
          ),
        ).called(1);
      });

      test('forward arguments to flutter build', () async {
        await runWithOverrides(
          () => builder.buildApk(
            flavor: 'flavor',
            target: 'target',
            targetPlatforms: [Arch.arm64],
            args: ['--foo', 'bar'],
          ),
        );

        verify(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'apk',
            '--release',
            '--flavor=flavor',
            '--target=target',
            '--target-platform=android-arm64',
            '--foo',
            'bar',
          ], runInShell: false),
        ).called(1);
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        setUp(() {
          when(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'apk',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('adds the SHOREBIRD_PUBLIC_KEY to the environment', () async {
          await runWithOverrides(
            () => builder.buildApk(
              flavor: 'flavor',
              target: 'target',
              targetPlatforms: [Arch.arm64],
              base64PublicKey: 'base64PublicKey',
            ),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'apk',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });

      group('when multiple artifacts are found', () {
        setUp(() {
          when(
            () => shorebirdAndroidArtifacts.findApk(
              project: any(named: 'project'),
              flavor: any(named: 'flavor'),
            ),
          ).thenThrow(
            MultipleArtifactsFoundException(
              foundArtifacts: [File('a'), File('b')],
              buildDir: 'buildDir',
            ),
          );
        });

        test('throws BuildException', () {
          expect(
            () => runWithOverrides(() => builder.buildApk()),
            throwsA(
              isA<ArtifactBuildException>().having(
                (e) => e.message,
                'message',
                '''Build succeeded, but it generated multiple APKs in the build directory. (a, b)''',
              ),
            ),
          );
        });
      });

      group('when no artifacts are found', () {
        setUp(() {
          when(
            () => shorebirdAndroidArtifacts.findApk(
              project: any(named: 'project'),
              flavor: any(named: 'flavor'),
            ),
          ).thenThrow(
            const ArtifactNotFoundException(
              artifactName: 'app-release.aab',
              buildDir: 'buildDir',
            ),
          );
        });

        test('throws BuildException', () {
          expect(
            () => runWithOverrides(() => builder.buildApk()),
            throwsA(
              isA<ArtifactBuildException>().having(
                (e) => e.message,
                'message',
                '''Build succeeded, but could not find the APK in the build directory. Expected to find app-release.aab''',
              ),
            ),
          );
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
              ),
            ).thenAnswer((_) async => ExitCode.success.code);
          });

          verifyCorrectFlutterPubGet(
            () => runWithOverrides(() => builder.buildApk()),
          );

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () => expectLater(
                () => runWithOverrides(() => builder.buildApk()),
                throwsA(
                  isA<ArtifactBuildException>().having(
                    (e) => e.fixRecommendation,
                    'recommendation',
                    startsWith(
                      ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                        '',
                      ).substring(0, 80),
                    ),
                  ),
                ),
              ),
            );
          });
        });
      });
    });

    group('buildAar', () {
      const buildNumber = '1.0';

      test('invokes the correct flutter build command', () async {
        await runWithOverrides(
          () => builder.buildAar(buildNumber: buildNumber),
        );

        verify(
          () => shorebirdProcess.stream(
            'flutter',
            [
              'build',
              'aar',
              '--no-debug',
              '--no-profile',
              '--build-number=1.0',
            ],
            environment: any(named: 'environment'),
            runInShell: false,
          ),
        ).called(1);
      });

      test('forward arguments to flutter build', () async {
        await runWithOverrides(
          () => builder.buildAar(
            buildNumber: buildNumber,
            targetPlatforms: [Arch.arm64],
            args: ['--foo', 'bar'],
          ),
        );

        verify(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=1.0',
            '--target-platform=android-arm64',
            '--foo',
            'bar',
          ], runInShell: false),
        ).called(1);
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        test('adds the SHOREBIRD_PUBLIC_KEY to the environment', () async {
          await runWithOverrides(
            () => builder.buildAar(
              buildNumber: buildNumber,
              base64PublicKey: 'base64PublicKey',
            ),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'aar',
                '--no-debug',
                '--no-profile',
                '--build-number=1.0',
              ],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
              ),
            ).thenAnswer((_) async => ExitCode.success.code);
          });

          verifyCorrectFlutterPubGet(
            () async => runWithOverrides(
              () => builder.buildAar(buildNumber: buildNumber),
            ),
          );

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () async => expectLater(
                () async => runWithOverrides(
                  () => builder.buildAar(buildNumber: buildNumber),
                ),
                throwsA(
                  isA<ArtifactBuildException>().having(
                    (e) => e.fixRecommendation,
                    'recommendation',
                    startsWith(
                      ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                        '',
                      ).substring(0, 80),
                    ),
                  ),
                ),
              ),
            );
          });
        });
      });
    });

    group('buildLinuxApp', () {
      late Directory linuxBundleDirectory;

      setUp(() {
        linuxBundleDirectory = Directory(
          p.join(
            projectRoot.path,
            'build',
            'linux',
            'x64',
            'release',
            'bundle',
          ),
        );
        when(
          () => artifactManager.linuxBundleDirectory,
        ).thenReturn(linuxBundleDirectory);
        when(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'linux',
            '--release',
          ], runInShell: any(named: 'runInShell')),
        ).thenAnswer((_) async => ExitCode.success.code);
      });

      group('when flutter build fails', () {
        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.software.code);
        });

        test('throws ArtifactBuildException', () async {
          expect(
            () => runWithOverrides(() => builder.buildLinuxApp()),
            throwsA(
              isA<ArtifactBuildException>()
                  .having(
                    (e) => e.message,
                    'message',
                    equals('''
Failed to build linux app.
Command: flutter build linux --release
Reason: Exited with code 70.'''),
                  )
                  .having(
                    (e) => e.fixRecommendation,
                    'recommendation',
                    startsWith(
                      ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                        '',
                      ).substring(0, 80),
                    ),
                  ),
            ),
          );
        });
      });

      group('when target is provided', () {
        test('forwards target to flutter command', () async {
          await runWithOverrides(
            () => builder.buildLinuxApp(target: 'target.dart'),
          );

          verify(
            () => shorebirdProcess.stream('flutter', [
              'build',
              'linux',
              '--release',
              '--target=target.dart',
            ], runInShell: false),
          ).called(1);
        });
      });

      group('when flutter build succeeds', () {
        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('completes', () async {
          await expectLater(
            runWithOverrides(() => builder.buildLinuxApp()),
            completes,
          );
        });
      });

      group('when public key is provided', () {
        const publicKey = 'publicKey';

        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              environment: any(named: 'environment'),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('provides public key as environment variable', () async {
          await runWithOverrides(
            () => builder.buildLinuxApp(base64PublicKey: publicKey),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              ['build', 'linux', '--release'],
              environment: {'SHOREBIRD_PUBLIC_KEY': publicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });
    });

    group('buildMacos', () {
      late File appDill;
      setUp(() {
        when(
          () => shorebirdProcess.stream(
            any(),
            any(),
            environment: any(named: 'environment'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async {
          appDill = File(p.join(projectRoot.path, '.dart_tool', 'app.dill'))
            ..createSync(recursive: true)
            ..setLastModifiedSync(
              DateTime.now().add(const Duration(seconds: 10)),
            );

          return ExitCode.success.code;
        });
      });

      group('when .dart_tool directory exists', () {
        late File foo;
        setUp(() {
          foo = File(p.join(projectRoot.path, '.dart_tool', 'foo.txt'))
            ..createSync(recursive: true);
        });

        test('deletes .dart_tool directory before building', () async {
          expect(foo.existsSync(), isTrue);
          await runWithOverrides(builder.buildMacos);
          expect(foo.existsSync(), isFalse);
        });
      });

      group('with default arguments', () {
        test('invokes flutter build with an export options plist', () async {
          final result = await runWithOverrides(builder.buildMacos);

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              ['build', 'macos', '--release'],
              environment: any(named: 'environment'),
              runInShell: false,
            ),
          ).called(1);
          expect(result.kernelFile.path, equals(appDill.path));
        });
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        test('adds the SHOREBIRD_PUBLIC_KEY to the environment', () async {
          await runWithOverrides(
            () => builder.buildMacos(base64PublicKey: base64PublicKey),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              ['build', 'macos', '--release'],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });

      test('forwards extra arguments to flutter build', () async {
        await runWithOverrides(
          () => builder.buildMacos(
            codesign: false,
            flavor: 'flavor',
            target: 'target.dart',
            args: ['--foo', 'bar'],
          ),
        );

        verify(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'macos',
            '--release',
            '--flavor=flavor',
            '--target=target.dart',
            '--no-codesign',
            '--foo',
            'bar',
          ], runInShell: false),
        ).called(1);
      });

      group('when the build fails', () {
        group('with non-zero exit code', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
              ),
            ).thenAnswer((_) async => ExitCode.software.code);
          });

          test('throws ArtifactBuildException', () {
            expect(
              () => runWithOverrides(() => builder.buildMacos(codesign: false)),
              throwsA(
                isA<ArtifactBuildException>().having(
                  (e) => e.fixRecommendation,
                  'recommendation',
                  startsWith(
                    ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                      '',
                    ).substring(0, 80),
                  ),
                ),
              ),
            );
          });
        });
      });

      group('when an app.dill file is not found in build stdout', () {
        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('throws ArtifactBuildException', () {
          expect(
            () => runWithOverrides(() => builder.buildMacos(codesign: false)),
            throwsA(
              isA<ArtifactBuildException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'Unable to find app.dill file.',
                  )
                  .having(
                    (e) => e.fixRecommendation,
                    'fixRecommendation',
                    '''Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.''',
                  ),
            ),
          );
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          verifyCorrectFlutterPubGet(
            () async =>
                runWithOverrides(() => builder.buildMacos(codesign: false)),
          );

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () async => expectLater(
                () async =>
                    runWithOverrides(() => builder.buildMacos(codesign: false)),
                throwsA(isA<ArtifactBuildException>()),
              ),
            );
          });
        });
      });
    });

    group('buildIpa', () {
      late File appDill;
      setUp(() {
        when(
          () => shorebirdProcess.stream(
            any(),
            any(),
            environment: any(named: 'environment'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async {
          appDill = File(p.join(projectRoot.path, '.dart_tool', 'app.dill'))
            ..createSync(recursive: true)
            ..setLastModifiedSync(
              DateTime.now().add(const Duration(seconds: 10)),
            );

          return ExitCode.success.code;
        });
      });

      group('when .dart_tool directory exists', () {
        late File foo;
        setUp(() {
          foo = File(p.join(projectRoot.path, '.dart_tool', 'foo.txt'))
            ..createSync(recursive: true);
        });

        test('deletes .dart_tool directory before building', () async {
          expect(foo.existsSync(), isTrue);
          await runWithOverrides(builder.buildIpa);
          expect(foo.existsSync(), isFalse);
        });
      });

      group('with default arguments', () {
        test('invokes flutter build with an export options plist', () async {
          final result = await runWithOverrides(builder.buildIpa);

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              ['build', 'ipa', '--release'],
              environment: any(named: 'environment'),
              runInShell: false,
            ),
          ).called(1);
          expect(result.kernelFile.path, equals(appDill.path));
        });
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        test('adds the SHOREBIRD_PUBLIC_KEY to the environment', () async {
          await runWithOverrides(
            () => builder.buildIpa(base64PublicKey: base64PublicKey),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              ['build', 'ipa', '--release'],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });

      test('forwards extra arguments to flutter build', () async {
        await runWithOverrides(
          () => builder.buildIpa(
            codesign: false,
            flavor: 'flavor',
            target: 'target.dart',
            args: ['--foo', 'bar'],
          ),
        );

        verify(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'ipa',
            '--release',
            '--flavor=flavor',
            '--target=target.dart',
            '--no-codesign',
            '--foo',
            'bar',
          ], runInShell: false),
        ).called(1);
      });

      group('when the build fails', () {
        group('with non-zero exit code', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
              ),
            ).thenAnswer((_) async => ExitCode.software.code);
          });

          test('throws ArtifactBuildException', () {
            expect(
              () => runWithOverrides(() => builder.buildIpa(codesign: false)),
              throwsA(
                isA<ArtifactBuildException>().having(
                  (e) => e.fixRecommendation,
                  'recommendation',
                  startsWith(
                    ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                      '',
                    ).substring(0, 80),
                  ),
                ),
              ),
            );
          });
        });
      });

      group('when an app.dill file is not found', () {
        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('throws ArtifactBuildException', () {
          expect(
            () => runWithOverrides(() => builder.buildIpa(codesign: false)),
            throwsA(
              isA<ArtifactBuildException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'Unable to find app.dill file.',
                  )
                  .having(
                    (e) => e.fixRecommendation,
                    'fixRecommendation',
                    '''Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.''',
                  ),
            ),
          );
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          verifyCorrectFlutterPubGet(
            () async =>
                runWithOverrides(() => builder.buildIpa(codesign: false)),
          );

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () async => expectLater(
                () async =>
                    runWithOverrides(() => builder.buildIpa(codesign: false)),
                throwsA(
                  isA<ArtifactBuildException>().having(
                    (e) => e.fixRecommendation,
                    'recommendation',
                    startsWith(
                      ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                        '',
                      ).substring(0, 80),
                    ),
                  ),
                ),
              ),
            );
          });
        });
      });
    });

    group('buildIosFramework', () {
      late File appDill;
      setUp(() {
        when(
          () => shorebirdProcess.stream(
            any(),
            any(),
            environment: any(named: 'environment'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async {
          appDill = File(p.join(projectRoot.path, '.dart_tool', 'app.dill'))
            ..createSync(recursive: true)
            ..setLastModifiedSync(
              DateTime.now().add(const Duration(seconds: 10)),
            );

          return ExitCode.success.code;
        });
      });

      group('when .dart_tool directory exists', () {
        late File foo;
        setUp(() {
          foo = File(p.join(projectRoot.path, '.dart_tool', 'foo.txt'))
            ..createSync(recursive: true);
        });

        test('deletes .dart_tool directory before building', () async {
          expect(foo.existsSync(), isTrue);
          await runWithOverrides(builder.buildIosFramework);
          expect(foo.existsSync(), isFalse);
        });
      });

      test('invokes the correct flutter build command', () async {
        final result = await runWithOverrides(builder.buildIosFramework);

        verify(
          () => shorebirdProcess.stream(
            'flutter',
            ['build', 'ios-framework', '--no-debug', '--no-profile'],
            environment: any(named: 'environment'),
            runInShell: false,
          ),
        ).called(1);
        expect(result.kernelFile.path, equals(appDill.path));
      });

      test('forward arguments to flutter build', () async {
        await runWithOverrides(
          () => builder.buildIosFramework(args: ['--foo', 'bar']),
        );

        verify(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'ios-framework',
            '--no-debug',
            '--no-profile',
            '--foo',
            'bar',
          ], runInShell: false),
        ).called(1);
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        test('adds the SHOREBIRD_PUBLIC_KEY to the environment', () async {
          await runWithOverrides(
            () => builder.buildIosFramework(base64PublicKey: 'base64PublicKey'),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              ['build', 'ios-framework', '--no-debug', '--no-profile'],
              environment: {'SHOREBIRD_PUBLIC_KEY': base64PublicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          verifyCorrectFlutterPubGet(
            () => runWithOverrides(builder.buildIosFramework),
          );

          group('when no app.dill file is found in build stdout', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                ),
              ).thenAnswer((_) async => ExitCode.success.code);
            });

            test('throws ArtifactBuildException', () {
              expect(
                () => runWithOverrides(builder.buildIosFramework),
                throwsA(
                  isA<ArtifactBuildException>()
                      .having(
                        (e) => e.message,
                        'message',
                        'Unable to find app.dill file.',
                      )
                      .having(
                        (e) => e.fixRecommendation,
                        'fixRecommendation',
                        '''Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.''',
                      ),
                ),
              );
            });
          });

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () => expectLater(
                () => runWithOverrides(builder.buildIosFramework),
                throwsA(
                  isA<ArtifactBuildException>().having(
                    (e) => e.fixRecommendation,
                    'recommendation',
                    startsWith(
                      ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                        '',
                      ).substring(0, 80),
                    ),
                  ),
                ),
              ),
            );
          });
        });
      });

      group('buildElfAotSnapshot', () {
        setUp(() {
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.genSnapshotIos,
            ),
          ).thenReturn('gen_snapshot');
        });

        test('passes additional args to gen_snapshot', () async {
          await runWithOverrides(
            () => builder.buildElfAotSnapshot(
              appDillPath: '/app/dill/path',
              outFilePath: '/path/to/out',
              genSnapshotArtifact: ShorebirdArtifact.genSnapshotIos,
              additionalArgs: ['--foo', 'bar'],
            ),
          );

          verify(
            () => shorebirdProcess.stream('gen_snapshot', [
              '--deterministic',
              '--snapshot-kind=app-aot-elf',
              '--elf=/path/to/out',
              '--strip',
              '--foo',
              'bar',
              '/app/dill/path',
            ], runInShell: false),
          ).called(1);
        });

        group('when build fails', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
              ),
            ).thenAnswer((_) async => ExitCode.software.code);
          });

          test('throws ArtifactBuildException', () {
            expect(
              () => runWithOverrides(
                () => builder.buildElfAotSnapshot(
                  appDillPath: 'asdf',
                  outFilePath: 'asdf',
                  genSnapshotArtifact: ShorebirdArtifact.genSnapshotIos,
                ),
              ),
              throwsA(isA<ArtifactBuildException>()),
            );
          });
        });

        group('when build succeeds', () {
          test('returns outFile', () async {
            final outFile = await runWithOverrides(
              () => builder.buildElfAotSnapshot(
                appDillPath: '/app/dill/path',
                outFilePath: '/path/to/out',
                genSnapshotArtifact: ShorebirdArtifact.genSnapshotIos,
              ),
            );

            expect(outFile.path, '/path/to/out');
          });
        });
      });
    });

    group('buildWindowsApp', () {
      late Directory windowsReleaseDirectory;

      setUp(() {
        windowsReleaseDirectory = Directory(
          p.join(
            projectRoot.path,
            'build',
            'windows',
            'x64',
            'runner',
            'Release',
          ),
        );
        when(
          () => artifactManager.getWindowsReleaseDirectory(),
        ).thenReturn(windowsReleaseDirectory);
        when(
          () => shorebirdProcess.stream('flutter', [
            'build',
            'windows',
            '--release',
          ], runInShell: false),
        ).thenAnswer((_) async => ExitCode.success.code);
      });

      group('when target is provided', () {
        test('forwards target to flutter command', () async {
          await runWithOverrides(
            () => builder.buildWindowsApp(target: 'target.dart'),
          );

          verify(
            () => shorebirdProcess.stream('flutter', [
              'build',
              'windows',
              '--release',
              '--target=target.dart',
            ], runInShell: false),
          ).called(1);
        });
      });

      group('when flutter build fails', () {
        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.software.code);
        });

        test('throws ArtifactBuildException', () async {
          expect(
            () => runWithOverrides(() => builder.buildWindowsApp()),
            throwsA(
              isA<ArtifactBuildException>()
                  .having(
                    (e) => e.message,
                    'message',
                    equals('''
Failed to build windows app.
Command: flutter build windows --release
Reason: Exited with code 70.'''),
                  )
                  .having(
                    (e) => e.fixRecommendation,
                    'recommendation',
                    startsWith(
                      ArtifactBuilder.runVanillaFlutterBuildRecommendation(
                        '',
                      ).substring(0, 80),
                    ),
                  ),
            ),
          );
        });
      });

      group('when flutter build succeeds', () {
        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('returns path to Release directory', () async {
          final result = await runWithOverrides(
            () => builder.buildWindowsApp(),
          );

          expect(
            result.path,
            endsWith(p.join('build', 'windows', 'x64', 'runner', 'Release')),
          );
        });
      });

      group('when public key is provided', () {
        const publicKey = 'publicKey';

        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              environment: any(named: 'environment'),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('provides public key as environment variable', () async {
          await runWithOverrides(
            () => builder.buildWindowsApp(base64PublicKey: publicKey),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              ['build', 'windows', '--release'],
              environment: {'SHOREBIRD_PUBLIC_KEY': publicKey},
              runInShell: false,
            ),
          ).called(1);
        });
      });
    });
  });
}
