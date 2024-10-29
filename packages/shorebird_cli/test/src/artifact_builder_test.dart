import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(ArtifactBuildException, () {
    test('toString is message', () {
      expect(
        ArtifactBuildException('my message').toString(),
        equals('my message'),
      );
    });
  });

  group(ArtifactBuilder, () {
    late Ios ios;
    late ShorebirdLogger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdProcessResult buildProcessResult;
    late ShorebirdProcessResult pubGetProcessResult;
    late ArtifactBuilder builder;
    late Process buildProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          iosRef.overrideWith(() => ios),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdAndroidArtifactsRef
              .overrideWith(() => shorebirdAndroidArtifacts),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeShorebirdProcess());
      registerFallbackValue(Directory(''));
    });

    setUp(() {
      buildProcessResult = MockProcessResult();
      ios = MockIos();
      logger = MockShorebirdLogger();
      operatingSystemInterface = MockOperatingSystemInterface();
      pubGetProcessResult = MockProcessResult();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();
      buildProcess = MockProcess();

      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => pubGetProcessResult);
      when(() => pubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => buildProcessResult);
      when(
        () => shorebirdProcess.start(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => buildProcess);
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
      when(() => buildProcessResult.stdout).thenReturn(
        '''
           [        ] Will strip AOT snapshot manually after build and dSYM generation.
           [        ] executing: /bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=snapshot_assembly.S /path/to/app.dill
           [+3688 ms] executing: sysctl hw.optional.arm64
''',
      );
      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
      when(() => shorebirdEnv.flutterRevision).thenReturn('1234');
      when(shorebirdEnv.getShorebirdProjectRoot).thenReturn(Directory(''));

      builder = ArtifactBuilder();
    });

    void verifyCorrectFlutterPubGet(
      Future<void> Function() testCall,
    ) {
      group('when flutter is installed', () {
        setUp(() {
          when(() => operatingSystemInterface.which('flutter'))
              .thenReturn('/path/to/flutter');
        });

        test('runs flutter pub get with system flutter', () async {
          await testCall();

          verify(
            () => shorebirdProcess.run(
              'flutter',
              ['--no-version-check', 'pub', 'get', '--offline'],
              runInShell: any(named: 'runInShell'),
              useVendedFlutter: false,
            ),
          ).called(1);
        });

        test('prints error message if system flutter pub get fails', () async {
          when(() => pubGetProcessResult.exitCode).thenReturn(1);

          await testCall();

          verify(
            () => logger.warn(
              '''
Build was successful, but `flutter pub get` failed to run after the build completed. You may see unexpected behavior in VS Code.

Either run `flutter pub get` manually, or follow the steps in ${cannotRunInVSCodeUrl.toLink()}.
''',
            ),
          ).called(1);
        });
      });

      group('when flutter is not installed', () {
        setUp(() {
          when(() => operatingSystemInterface.which('flutter'))
              .thenReturn(null);
        });

        test('does not attempt to run flutter pub get', () async {
          await testCall();

          verifyNever(
            () => shorebirdProcess.run(
              'flutter',
              ['--no-version-check', 'pub', 'get', '--offline'],
              runInShell: any(named: 'runInShell'),
              useVendedFlutter: false,
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
        when(() => buildProcess.stdout).thenAnswer(
          (_) => Stream.fromIterable(
            [
              'Some build output',
            ].map(utf8.encode),
          ),
        );
        when(() => buildProcess.stderr).thenAnswer(
          (_) => Stream.fromIterable(
            [
              'Some build output',
            ].map(utf8.encode),
          ),
        );
        when(() => buildProcess.exitCode).thenAnswer((_) async => 0);
      });

      test('invokes the correct flutter build command', () async {
        await runWithOverrides(() => builder.buildAppBundle());

        verify(
          () => shorebirdProcess.start(
            'flutter',
            ['build', 'appbundle', '--release'],
            runInShell: any(named: 'runInShell'),
            environment: any(named: 'environment'),
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
          () => shorebirdProcess.start(
            'flutter',
            [
              'build',
              'appbundle',
              '--release',
              '--flavor=flavor',
              '--target=target',
              '--target-platform=android-arm64',
              '--foo',
              'bar',
            ],
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        setUp(() {
          when(
            () => shorebirdProcess.start(
              'flutter',
              [
                'build',
                'appbundle',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              runInShell: any(named: 'runInShell'),
              environment: {
                'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
              },
            ),
          ).thenAnswer((_) async => buildProcess);
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
            () => shorebirdProcess.start(
              'flutter',
              [
                'build',
                'appbundle',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              runInShell: any(named: 'runInShell'),
              environment: {
                'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
              },
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
            ArtifactNotFoundException(
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

      group('when output contains gradle task names', () {
        late DetailProgress progress;

        setUp(() {
          progress = MockDetailProgress();

          when(() => buildProcess.stdout).thenAnswer(
            (_) => Stream.fromIterable(
              [
                'Some build output',
                '[  ] > Task :app:bundleRelease',
                'More build output',
                '[  ] > Task :app:someOtherTask',
                'Even more build output',
              ]
                  .map((line) => '$line${Platform.lineTerminator}')
                  .map(utf8.encode),
            ),
          );
          when(() => buildProcess.stderr).thenAnswer(
            (_) => Stream.fromIterable(
              ['Some build output'].map(utf8.encode),
            ),
          );
        });

        test('updates progress with gradle task names', () async {
          await expectLater(
            runWithOverrides(
              () => builder.buildAppBundle(
                buildProgress: progress,
              ),
            ),
            completes,
          );

          // Required to trigger stdout stream events
          await pumpEventQueue();

          // Ensure we update the progress in the correct order and with the
          // correct messages, and reset to the base message after the build
          // completes.
          verifyInOrder(
            [
              () => progress.updateDetailMessage('Task :app:bundleRelease'),
              () => progress.updateDetailMessage('Task :app:someOtherTask'),
              () => progress.updateDetailMessage(null),
            ],
          );
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          setUp(() {
            when(() => buildProcess.exitCode)
                .thenAnswer((_) async => ExitCode.success.code);
          });

          verifyCorrectFlutterPubGet(
            () => runWithOverrides(() => builder.buildAppBundle()),
          );

          group('when the build fails', () {
            setUp(() {
              when(() => buildProcess.exitCode)
                  .thenAnswer((_) async => ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () => expectLater(
                () => runWithOverrides(() => builder.buildAppBundle()),
                throwsA(isA<ArtifactBuildException>()),
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
          () => shorebirdProcess.run(
            'flutter',
            ['build', 'apk', '--release'],
            runInShell: any(named: 'runInShell'),
            environment: any(named: 'environment'),
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
          () => shorebirdProcess.run(
            'flutter',
            [
              'build',
              'apk',
              '--release',
              '--flavor=flavor',
              '--target=target',
              '--target-platform=android-arm64',
              '--foo',
              'bar',
            ],
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });

      group('when base64PublicKey is not null', () {
        const base64PublicKey = 'base64PublicKey';

        setUp(() {
          when(
            () => shorebirdProcess.run(
              'flutter',
              [
                'build',
                'apk',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              runInShell: any(named: 'runInShell'),
              environment: {
                'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
              },
            ),
          ).thenAnswer((_) async => buildProcessResult);
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
            () => shorebirdProcess.run(
              'flutter',
              [
                'build',
                'apk',
                '--release',
                '--flavor=flavor',
                '--target=target',
                '--target-platform=android-arm64',
              ],
              runInShell: any(named: 'runInShell'),
              environment: {
                'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
              },
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
            ArtifactNotFoundException(
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
            when(() => buildProcessResult.exitCode)
                .thenReturn(ExitCode.success.code);
          });

          verifyCorrectFlutterPubGet(
            () => runWithOverrides(() => builder.buildApk()),
          );

          group('when the build fails', () {
            setUp(() {
              when(() => buildProcessResult.exitCode)
                  .thenReturn(ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () => expectLater(
                () => runWithOverrides(() => builder.buildApk()),
                throwsA(isA<ArtifactBuildException>()),
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
          () => shorebirdProcess.run(
            'flutter',
            [
              'build',
              'aar',
              '--no-debug',
              '--no-profile',
              '--build-number=1.0',
            ],
            runInShell: any(named: 'runInShell'),
            environment: any(named: 'environment'),
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
          () => shorebirdProcess.run(
            'flutter',
            [
              'build',
              'aar',
              '--no-debug',
              '--no-profile',
              '--build-number=1.0',
              '--target-platform=android-arm64',
              '--foo',
              'bar',
            ],
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });

      group('after a build', () {
        group('when the build is successful', () {
          setUp(() {
            when(() => buildProcessResult.exitCode)
                .thenReturn(ExitCode.success.code);
          });

          verifyCorrectFlutterPubGet(
            () async => runWithOverrides(
              () => builder.buildAar(buildNumber: buildNumber),
            ),
          );

          group('when the build fails', () {
            setUp(() {
              when(() => buildProcessResult.exitCode)
                  .thenReturn(ExitCode.software.code);
            });

            verifyCorrectFlutterPubGet(
              () async => expectLater(
                () async => runWithOverrides(
                  () => builder.buildAar(buildNumber: buildNumber),
                ),
                throwsA(isA<ArtifactBuildException>()),
              ),
            );
          });
        });
      });
    });

    group(
      'buildIpa',
      () {
        late File exportOptionsPlist;

        setUp(() {
          final tempDir = Directory.systemTemp.createTempSync();
          exportOptionsPlist =
              File(p.join(tempDir.path, 'exportoptions.plist'));
          when(ios.createExportOptionsPlist).thenReturn(exportOptionsPlist);
        });

        group('with default arguments', () {
          test('invokes flutter build with an export options plist', () async {
            final result = await runWithOverrides(builder.buildIpa);

            verify(
              () => shorebirdProcess.run(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
                  '--export-options-plist=${exportOptionsPlist.path}',
                ],
                runInShell: true,
                environment: any(named: 'environment'),
              ),
            ).called(1);
            expect(result.kernelFile.path, equals('/path/to/app.dill'));
          });
        });

        group('when base64PublicKey is not null', () {
          const base64PublicKey = 'base64PublicKey';

          setUp(() {
            when(
              () => shorebirdProcess.run(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
                  '--export-options-plist=${exportOptionsPlist.path}',
                ],
                runInShell: any(named: 'runInShell'),
                environment: {
                  'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
                },
              ),
            ).thenAnswer((_) async => buildProcessResult);
          });

          test('adds the SHOREBIRD_PUBLIC_KEY to the environment', () async {
            await runWithOverrides(
              () => builder.buildIpa(
                base64PublicKey: base64PublicKey,
              ),
            );

            verify(
              () => shorebirdProcess.run(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
                  '--export-options-plist=${exportOptionsPlist.path}',
                ],
                runInShell: any(named: 'runInShell'),
                environment: {
                  'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
                },
              ),
            ).called(1);
          });
        });

        group('when export options plist is provided', () {
          test('forwards to flutter build', () async {
            await runWithOverrides(
              () => builder.buildIpa(
                exportOptionsPlist: File('custom_exportoptions.plist'),
              ),
            );

            verify(
              () => shorebirdProcess.run(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
                  '--export-options-plist=custom_exportoptions.plist',
                ],
                runInShell: any(named: 'runInShell'),
              ),
            ).called(1);
          });
        });

        test('does not provide export options plist without codesigning',
            () async {
          await runWithOverrides(
            () => builder.buildIpa(
              codesign: false,
              exportOptionsPlist: File('exportOptionsPlist.plist'),
            ),
          );

          verify(
            () => shorebirdProcess.run(
              'flutter',
              [
                'build',
                'ipa',
                '--release',
                '--no-codesign',
              ],
              runInShell: any(named: 'runInShell'),
              environment: any(named: 'environment'),
            ),
          ).called(1);
        });

        test('forwards extra arguments to flutter build', () async {
          await runWithOverrides(
            () => builder.buildIpa(
              codesign: false,
              exportOptionsPlist: File('exportOptionsPlist.plist'),
              flavor: 'flavor',
              target: 'target.dart',
              args: ['--foo', 'bar'],
            ),
          );

          verify(
            () => shorebirdProcess.run(
              'flutter',
              [
                'build',
                'ipa',
                '--release',
                '--flavor=flavor',
                '--target=target.dart',
                '--no-codesign',
                '--foo',
                'bar',
              ],
              runInShell: any(named: 'runInShell'),
            ),
          ).called(1);
        });

        group('when the build fails', () {
          group('with non-zero exit code', () {
            setUp(() {
              when(() => buildProcessResult.exitCode)
                  .thenReturn(ExitCode.software.code);
            });

            test('throws ArtifactBuildException', () {
              expect(
                () => runWithOverrides(() => builder.buildIpa(codesign: false)),
                throwsA(isA<ArtifactBuildException>()),
              );
            });
          });

          group('with error message in stderr (Xcode <= 15.x)', () {
            setUp(() {
              when(() => buildProcessResult.exitCode)
                  .thenReturn(ExitCode.success.code);
              when(() => buildProcessResult.stderr).thenReturn(
                '''
Encountered error while creating the IPA:
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
error: exportArchive: No profiles for 'com.example.co' were found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found''',
              );
            });

            test('throws ArtifactBuildException with error message', () {
              expect(
                () => runWithOverrides(() => builder.buildIpa(codesign: false)),
                throwsA(
                  isA<ArtifactBuildException>().having(
                    (e) => e.message,
                    'message',
                    '''
Failed to build:
    Communication with Apple failed
    No signing certificate "iOS Distribution" found
    Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
    No profiles for 'com.example.co' were found''',
                  ),
                ),
              );
            });
          });

          group('with error message in stderr (Xcode >= 16.x)', () {
            setUp(() {
              when(() => buildProcessResult.exitCode)
                  .thenReturn(ExitCode.success.code);
              when(() => buildProcessResult.stderr).thenReturn(
                '''
Encountered error while creating the IPA:
error: exportArchive Communication with Apple failed
error: exportArchive No signing certificate "iOS Distribution" found
error: exportArchive Communication with Apple failed
error: exportArchive No signing certificate "iOS Distribution" found
error: exportArchive Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
error: exportArchive No profiles for 'com.example.co' were found
error: exportArchive Communication with Apple failed
error: exportArchive No signing certificate "iOS Distribution" found
error: exportArchive Communication with Apple failed
error: exportArchive No signing certificate "iOS Distribution" found
error: exportArchive Communication with Apple failed
error: exportArchive No signing certificate "iOS Distribution" found''',
              );
            });

            test('throws ArtifactBuildException with error message', () {
              expect(
                () => runWithOverrides(() => builder.buildIpa(codesign: false)),
                throwsA(
                  isA<ArtifactBuildException>().having(
                    (e) => e.message,
                    'message',
                    '''
Failed to build:
    Communication with Apple failed
    No signing certificate "iOS Distribution" found
    Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
    No profiles for 'com.example.co' were found''',
                  ),
                ),
              );
            });
          });
        });

        group('when an app.dill file is not found in build stdout', () {
          setUp(() {
            when(() => buildProcessResult.stdout).thenReturn('no app.dill');
          });

          test('throws ArtifactBuildException', () {
            expect(
              () => runWithOverrides(() => builder.buildIpa(codesign: false)),
              throwsA(
                isA<ArtifactBuildException>().having(
                  (e) => e.message,
                  'message',
                  '''
Unable to find app.dill file.
Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.
''',
                ),
              ),
            );
          });
        });

        group('after a build', () {
          group('when the build is successful', () {
            setUp(() {
              when(() => buildProcessResult.exitCode)
                  .thenReturn(ExitCode.success.code);
            });

            verifyCorrectFlutterPubGet(
              () async => runWithOverrides(
                () => builder.buildIpa(codesign: false),
              ),
            );

            group('when the build fails', () {
              setUp(() {
                when(() => buildProcessResult.exitCode)
                    .thenReturn(ExitCode.software.code);
              });

              verifyCorrectFlutterPubGet(
                () async => expectLater(
                  () async => runWithOverrides(
                    () => builder.buildIpa(codesign: false),
                  ),
                  throwsA(isA<ArtifactBuildException>()),
                ),
              );
            });
          });
        });
      },
      testOn: 'mac-os',
    );

    group(
      'buildIosFramework',
      () {
        test('invokes the correct flutter build command', () async {
          final result = await runWithOverrides(builder.buildIosFramework);

          verify(
            () => shorebirdProcess.run(
              'flutter',
              [
                'build',
                'ios-framework',
                '--no-debug',
                '--no-profile',
              ],
              runInShell: true,
              environment: any(named: 'environment'),
            ),
          ).called(1);
          expect(result.kernelFile.path, equals('/path/to/app.dill'));
        });

        test('forward arguments to flutter build', () async {
          await runWithOverrides(
            () => builder.buildIosFramework(args: ['--foo', 'bar']),
          );

          verify(
            () => shorebirdProcess.run(
              'flutter',
              [
                'build',
                'ios-framework',
                '--no-debug',
                '--no-profile',
                '--foo',
                'bar',
              ],
              runInShell: true,
            ),
          ).called(1);
        });

        group('after a build', () {
          group('when the build is successful', () {
            setUp(() {
              when(() => buildProcessResult.exitCode)
                  .thenReturn(ExitCode.success.code);
            });

            verifyCorrectFlutterPubGet(
              () => runWithOverrides(builder.buildIosFramework),
            );

            group('when no app.dill file is found in build stdout', () {
              setUp(() {
                when(() => buildProcessResult.stdout).thenReturn('no app.dill');
              });

              test('throws ArtifactBuildException', () {
                expect(
                  () => runWithOverrides(builder.buildIosFramework),
                  throwsA(
                    isA<ArtifactBuildException>().having(
                      (e) => e.message,
                      'message',
                      '''
Unable to find app.dill file.
Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.
''',
                    ),
                  ),
                );
              });
            });

            group('when the build fails', () {
              setUp(() {
                when(() => buildProcessResult.exitCode)
                    .thenReturn(ExitCode.software.code);
              });

              verifyCorrectFlutterPubGet(
                () => expectLater(
                  () => runWithOverrides(builder.buildIosFramework),
                  throwsA(isA<ArtifactBuildException>()),
                ),
              );
            });
          });
        });

        group('buildElfAotSnapshot', () {
          setUp(() {
            when(
              () => shorebirdArtifacts.getArtifactPath(
                artifact: ShorebirdArtifact.genSnapshot,
              ),
            ).thenReturn('gen_snapshot');
          });

          test('passes additional args to gen_snapshot', () async {
            await runWithOverrides(
              () => builder.buildElfAotSnapshot(
                appDillPath: '/app/dill/path',
                outFilePath: '/path/to/out',
                additionalArgs: ['--foo', 'bar'],
              ),
            );

            verify(
              () => shorebirdProcess.run(
                'gen_snapshot',
                [
                  '--deterministic',
                  '--snapshot-kind=app-aot-elf',
                  '--elf=/path/to/out',
                  '--foo',
                  'bar',
                  '/app/dill/path',
                ],
              ),
            ).called(1);
          });

          group('when build fails', () {
            setUp(() {
              when(
                () => buildProcessResult.exitCode,
              ).thenReturn(ExitCode.software.code);
            });

            test('throws ArtifactBuildException', () {
              expect(
                () => runWithOverrides(
                  () => builder.buildElfAotSnapshot(
                    appDillPath: 'asdf',
                    outFilePath: 'asdf',
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
                ),
              );

              expect(outFile.path, '/path/to/out');
            });
          });
        });
      },
      testOn: 'mac-os',
    );
  });
}
