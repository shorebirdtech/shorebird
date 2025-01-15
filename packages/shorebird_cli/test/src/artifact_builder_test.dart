import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
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
    final projectRoot = Directory.systemTemp.createTempSync();
    late ArtifactManager artifactManager;
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
          artifactManagerRef.overrideWith(() => artifactManager),
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
      artifactManager = MockArtifactManager();
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
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
      when(() => buildProcessResult.stdout).thenReturn('some stdout');
      when(
        () => shorebirdProcess.start(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => buildProcess);
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

      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
      when(() => shorebirdEnv.flutterRevision).thenReturn('1234');

      when(shorebirdEnv.getShorebirdProjectRoot).thenReturn(projectRoot);

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
      'buildMacos',
      () {
        setUp(() {
          when(() => buildProcess.stdout).thenAnswer(
            (_) => Stream.fromIterable(
              [
                '''
[        ] [   +1 ms] targetingApplePlatform = true
[        ] [        ] extractAppleDebugSymbols = true
[        ] [        ] Will strip AOT snapshot manually after build and dSYM generation.
[        ] [        ] executing: /Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/b1fabdf140ab5591c45dbea4196dc3c018a4ed3a/bin/cache/artifacts/engine/darwin-x64-release/gen_snapshot_arm64 --deterministic --print_class_table_link_debug_info_to=/Users/bryanoltman/Documents/sandbox/macos_sandbox/.dart_tool/flutter_build/f9149091b9c399e05076c18d6b754a0f/App.class_table.json --print_class_table_link_info_to=/Users/bryanoltman/Documents/sandbox/macos_sandbox/.dart_tool/flutter_build/f9149091b9c399e05076c18d6b754a0f/App.ct.link --snapshot_kind=app-aot-assembly --assembly=/Users/bryanoltman/Documents/sandbox/macos_sandbox/.dart_tool/flutter_build/f9149091b9c399e05076c18d6b754a0f/arm64/snapshot_assembly.S /path/to/app.dill
[        ] [        ] targetingApplePlatform = true
[        ] [        ] extractAppleDebugSymbols = true
[        ] [        ] Will strip AOT snapshot manually after build and dSYM generation.
[+5214 ms] [        ] executing: /Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/b1fabdf140ab5591c45dbea4196dc3c018a4ed3a/bin/cache/artifacts/engine/darwin-x64-release/gen_snapshot_x64 --deterministic --print_class_table_link_debug_info_to=/Users/bryanoltman/Documents/sandbox/macos_sandbox/.dart_tool/flutter_build/f9149091b9c399e05076c18d6b754a0f/App.class_table.json --print_class_table_link_info_to=/Users/bryanoltman/Documents/sandbox/macos_sandbox/.dart_tool/flutter_build/f9149091b9c399e05076c18d6b754a0f/App.ct.link --snapshot_kind=app-aot-assembly --assembly=/Users/bryanoltman/Documents/sandbox/macos_sandbox/.dart_tool/flutter_build/f9149091b9c399e05076c18d6b754a0f/x86_64/snapshot_assembly.S /path/to/app.dill
[        ] [+3527 ms] Building App.framework for x86_64...
[        ] [   +6 ms] executing: sysctl hw.optional.arm64
''',
              ].map(utf8.encode),
            ),
          );
        });

        group('when .dart_tool directory exists', () {
          late Directory dartToolDir;

          setUp(() {
            dartToolDir = Directory(
              p.join(projectRoot.path, '.dart_tool'),
            )..createSync(recursive: true);
          });

          test('deletes .dart_tool directory before building', () async {
            expect(dartToolDir.existsSync(), isTrue);
            await runWithOverrides(builder.buildMacos);
            expect(dartToolDir.existsSync(), isFalse);
          });
        });

        group('with default arguments', () {
          test('invokes flutter build with an export options plist', () async {
            final result = await runWithOverrides(builder.buildMacos);

            verify(
              () => shorebirdProcess.start(
                'flutter',
                [
                  'build',
                  'macos',
                  '--release',
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
              () => shorebirdProcess.start(
                'flutter',
                [
                  'build',
                  'macos',
                  '--release',
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
              () => builder.buildMacos(
                base64PublicKey: base64PublicKey,
              ),
            );

            verify(
              () => shorebirdProcess.start(
                'flutter',
                [
                  'build',
                  'macos',
                  '--release',
                ],
                runInShell: any(named: 'runInShell'),
                environment: {
                  'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
                },
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
            () => shorebirdProcess.start(
              'flutter',
              [
                'build',
                'macos',
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
              when(() => buildProcess.exitCode)
                  .thenAnswer((_) async => ExitCode.software.code);
            });

            test('throws ArtifactBuildException', () {
              expect(
                () => runWithOverrides(
                  () => builder.buildMacos(codesign: false),
                ),
                throwsA(isA<ArtifactBuildException>()),
              );
            });
          });
        });

        group('when an app.dill file is not found in build stdout', () {
          setUp(() {
            when(() => buildProcess.stdout).thenAnswer(
              (_) => Stream.fromIterable(
                [
                  'no app.dill',
                ].map(utf8.encode),
              ),
            );
          });

          test('throws ArtifactBuildException', () {
            expect(
              () => runWithOverrides(() => builder.buildMacos(codesign: false)),
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
              when(
                () => buildProcess.exitCode,
              ).thenAnswer((_) async => ExitCode.success.code);
            });

            verifyCorrectFlutterPubGet(
              () async => runWithOverrides(
                () => builder.buildMacos(codesign: false),
              ),
            );

            group('when the build fails', () {
              setUp(() {
                when(
                  () => buildProcess.exitCode,
                ).thenAnswer((_) async => ExitCode.software.code);
              });

              verifyCorrectFlutterPubGet(
                () async => expectLater(
                  () async => runWithOverrides(
                    () => builder.buildMacos(codesign: false),
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
      'buildIpa',
      () {
        setUp(() {
          when(() => buildProcess.stdout).thenAnswer(
            (_) => Stream.fromIterable(
              [
                '''
           [        ] Will strip AOT snapshot manually after build and dSYM generation.
           [        ] executing: /bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=snapshot_assembly.S /path/to/app.dill
           [+3688 ms] executing: sysctl hw.optional.arm64
''',
              ].map(utf8.encode),
            ),
          );
        });

        group('with default arguments', () {
          test('invokes flutter build with an export options plist', () async {
            final result = await runWithOverrides(builder.buildIpa);

            verify(
              () => shorebirdProcess.start(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
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
              () => shorebirdProcess.start(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
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
              () => builder.buildIpa(
                base64PublicKey: base64PublicKey,
              ),
            );

            verify(
              () => shorebirdProcess.start(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
                ],
                runInShell: any(named: 'runInShell'),
                environment: {
                  'SHOREBIRD_PUBLIC_KEY': base64PublicKey,
                },
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
            () => shorebirdProcess.start(
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

        group('when progress contains known build steps', () {
          late DetailProgress progress;

          setUp(() {
            progress = MockDetailProgress();

            when(() => buildProcess.stdout).thenAnswer(
              (_) => Stream.fromIterable(
                [
                  // cSpell:disable
                  '''
                  [        ] Will strip AOT snapshot manually after build and dSYM generation.
                  [        ] executing: /bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=snapshot_assembly.S /path/to/app.dill
                  [+3688 ms] executing: sysctl hw.optional.arm64''',
                  '[  +10 ms] Generating /Users/bryanoltman/Documents/sandbox/notification_extension/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
                  '[  +50 ms] executing: [/Users/bryanoltman/Documents/sandbox/notification_extension/ios/] /usr/bin/arch -arm64e xcrun xcodebuild -list',
                  '[+32333 ms] Command line invocation:',
                  '[   +6 ms] Exit code 0 from: mkfifo /var/folders/64/dj6krpq1093dmx08dy4r1cwh0000gn/T/flutter_tools.WDvaE9/flutter_ios_build_temp_dirUAyStV/pipe_to_stdout',
                  '[   +1 ms] Running Xcode build...',
                  '[        ] executing: [/Users/bryanoltman/Documents/sandbox/notification_extension/ios/] /usr/bin/arch -arm64e xcrun xcodebuild -configuration Release VERBOSE_SCRIPT_LOGGING=YES -workspace Runner.xcworkspace -scheme Runner -sdk iphoneos -destination generic/platform=iOS SCRIPT_OUTPUT_STREAM_FILE=/var/folders/64/dj6krpq1093dmx08dy4r1cwh0000gn/T/flutter_tools.WDvaE9/flutter_ios_build_temp_dirUAyStV/pipe_to_stdout -resultBundlePath /var/folders/64/dj6krpq1093dmx08dy4r1cwh0000gn/T/flutter_tools.WDvaE9/flutter_ios_build_temp_dirUAyStV/temporary_xcresult_bundle -resultBundleVersion 3 FLUTTER_SUPPRESS_ANALYTICS=true COMPILER_INDEX_STORE_ENABLE=NO -archivePath /Users/bryanoltman/Documents/sandbox/notification_extension/build/ios/archive/Runner archive',
                  '[+62601 ms] Running Xcode build... (completed in 62.6s)',
                  '[        ]  └─Compiling, linking and signing...',
                  '[+5925 ms] Command line invocation:',
                  '/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -configuration Release VERBOSE_SCRIPT_LOGGING=YES -workspace Runner.xcworkspace -scheme Runner -sdk iphoneos -destination generic/platform=iOS SCRIPT_OUTPUT_STREAM_FILE=/var/folders/64/dj6krpq1093dmx08dy4r1cwh0000gn/T/flutter_tools.WDvaE9/flutter_ios_build_temp_dirUAyStV/pipe_to_stdout -resultBundlePath /var/folders/64/dj6krpq1093dmx08dy4r1cwh0000gn/T/flutter_tools.WDvaE9/flutter_ios_build_temp_dirUAyStV/temporary_xcresult_bundle -resultBundleVersion 3 FLUTTER_SUPPRESS_ANALYTICS=true COMPILER_INDEX_STORE_ENABLE=NO -archivePath /Users/bryanoltman/Documents/sandbox/notification_extension/build/ios/archive/Runner archive',
                  // cSpell:enable
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

          test('updates progress with known build steps', () async {
            await expectLater(
              runWithOverrides(
                () => builder.buildIpa(
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
                () => progress.updateDetailMessage('Collecting schemes'),
                () => progress.updateDetailMessage('Running Xcode build'),
                () => progress.updateDetailMessage('Running Xcode build'),
                () => progress.updateDetailMessage(
                      'Compiling, linking and signing',
                    ),
              ],
            );
          });
        });

        group('when the build fails', () {
          group('with non-zero exit code', () {
            setUp(() {
              when(() => buildProcess.exitCode)
                  .thenAnswer((_) async => ExitCode.software.code);
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
              when(() => buildProcess.exitCode)
                  .thenAnswer((_) async => ExitCode.success.code);
              when(() => buildProcess.stderr).thenAnswer(
                (_) => Stream.fromIterable(
                  [
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
                  ].map(utf8.encode),
                ),
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
                  ),
                ),
              );
            });
          });

          group('with error message in stderr (Xcode >= 16.x)', () {
            setUp(() {
              when(() => buildProcess.exitCode)
                  .thenAnswer((_) async => ExitCode.success.code);
              when(() => buildProcess.stderr).thenAnswer(
                (_) => Stream.fromIterable(
                  [
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
                  ].map(utf8.encode),
                ),
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
                  ),
                ),
              );
            });
          });
        });

        group('when an app.dill file is not found in build stdout', () {
          setUp(() {
            when(() => buildProcess.stdout).thenAnswer(
              (_) => Stream.fromIterable(
                [
                  'no app.dill',
                ].map(utf8.encode),
              ),
            );
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
              when(
                () => buildProcess.exitCode,
              ).thenAnswer((_) async => ExitCode.success.code);
            });

            verifyCorrectFlutterPubGet(
              () async => runWithOverrides(
                () => builder.buildIpa(codesign: false),
              ),
            );

            group('when the build fails', () {
              setUp(() {
                when(
                  () => buildProcess.exitCode,
                ).thenAnswer((_) async => ExitCode.software.code);
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
        setUp(() {
          when(() => buildProcessResult.stdout).thenReturn(
            '''
           [        ] Will strip AOT snapshot manually after build and dSYM generation.
           [        ] executing: /bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=snapshot_assembly.S /path/to/app.dill
           [+3688 ms] executing: sysctl hw.optional.arm64
''',
          );
        });

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
      },
      testOn: 'mac-os',
    );

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
          () => shorebirdProcess.start(
            'flutter',
            [
              'build',
              'windows',
              '--release',
            ],
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => buildProcess);
      });

      group('when flutter build fails', () {
        setUp(() {
          when(
            () => buildProcess.exitCode,
          ).thenAnswer((_) async => ExitCode.software.code);
          when(() => buildProcess.stderr).thenAnswer(
            (_) => Stream.fromIterable(
              [
                'stderr contents',
              ].map(utf8.encode),
            ),
          );
        });

        test('throws ArtifactBuildException', () async {
          expect(
            () => runWithOverrides(() => builder.buildWindowsApp()),
            throwsA(
              isA<ArtifactBuildException>().having(
                (e) => e.message,
                'message',
                equals('Failed to build: stderr contents'),
              ),
            ),
          );
        });
      });

      group('when flutter build succeeds', () {
        setUp(() {
          when(
            () => buildProcess.exitCode,
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
            () => buildProcess.exitCode,
          ).thenAnswer((_) async => ExitCode.success.code);
        });

        test('provides public key as environment variable', () async {
          await runWithOverrides(
            () => builder.buildWindowsApp(base64PublicKey: publicKey),
          );

          verify(
            () => shorebirdProcess.start(
              'flutter',
              [
                'build',
                'windows',
                '--release',
              ],
              runInShell: any(named: 'runInShell'),
              environment: {
                'SHOREBIRD_PUBLIC_KEY': publicKey,
              },
            ),
          ).called(1);
        });
      });
    });

    group('findAppDill', () {
      group('when gen_snapshot is invoked with app.dill', () {
        test('returns the path to app.dill', () {
          const result = '''
           [        ] Will strip AOT snapshot manually after build and dSYM generation.
           [        ] executing: /Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/985ec84cb99d3c60341e2c78be9826e0a88cc697/bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/arm64/snapshot_assembly.S /Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/app.dill
           [+3688 ms] executing: sysctl hw.optional.arm64
''';

          expect(
            builder.findAppDill(stdout: result),
            equals(
              '/Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/app.dill',
            ),
          );
        });

        test('returns the path to app.dill (local engine)', () {
          const result = '''
          [        ] Will strip AOT snapshot manually after build and dSYM generation.
          [        ] executing: /Users/felix/Development/github.com/shorebirdtech/engine/src/out/ios_release/clang_x64/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/felix/Development/github.com/felangel/flutter_and_friends/.dart_tool/flutter_build/ae2d368b5940aefb0c55ff62186de056/arm64/snapshot_assembly.S /Users/felix/Development/github.com/felangel/flutter_and_friends/.dart_tool/flutter_build/ae2d368b5940aefb0c55ff62186de056/app.dill
          [+5435 ms] executing: sysctl hw.optional.arm64
''';

          expect(
            builder.findAppDill(stdout: result),
            equals(
              '/Users/felix/Development/github.com/felangel/flutter_and_friends/.dart_tool/flutter_build/ae2d368b5940aefb0c55ff62186de056/app.dill',
            ),
          );
        });

        group('when path to app.dill contains a space', () {
          test('returns full path to app.dill, including the space(s)', () {
            const result = '''
            [   +3 ms] targetingApplePlatform = true
            [        ] extractAppleDebugSymbols = true
            [        ] Will strip AOT snapshot manually after build and dSYM generation.
            [        ] executing: /Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/9015e1b42a1ba41d97176e22b502b0e0e8ad28af/bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/bryanoltman/Documents/sandbox/folder with space/ios_patcher/.dart_tool/flutter_build/cd4f4aa272817365910648606e3e4164/arm64/snapshot_assembly.S /Users/bryanoltman/Documents/sandbox/folder with space/ios_patcher/.dart_tool/flutter_build/cd4f4aa272817365910648606e3e4164/app.dill
            [+3395 ms] executing: sysctl hw.optional.arm64
            [   +3 ms] Exit code 0 from: sysctl hw.optional.arm64
''';

            expect(
              builder.findAppDill(stdout: result),
              equals(
                '/Users/bryanoltman/Documents/sandbox/folder with space/ios_patcher/.dart_tool/flutter_build/cd4f4aa272817365910648606e3e4164/app.dill',
              ),
            );
          });
        });
      });

      group('when gen_snapshot is not invoked with app.dill', () {
        test('returns null', () {
          const result =
              'executing: .../gen_snapshot_arm64 .../snapshot_assembly.S';

          expect(builder.findAppDill(stdout: result), isNull);
        });
      });
    });
  });
}
