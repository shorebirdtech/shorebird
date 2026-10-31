import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(ArtifactBuilder, () {
    late Directory projectRoot;
    late Apple apple;
    late ArtifactManager artifactManager;
    late ShorebirdLogger logger;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdProcess shorebirdProcess;
    late ArtifactBuilder builder;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          appleRef.overrideWith(() => apple),
          artifactManagerRef.overrideWith(() => artifactManager),
          buildTraceSessionRef.overrideWith(
            () => BuildTraceSession(commandStartedAt: DateTime.now()),
          ),
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdTracerRef.overrideWith(ShorebirdTracer.new),
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
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdProcess = MockShorebirdProcess();

      // Default to a Flutter version that does not support --trace so
      // existing exact-argument verifications aren't disturbed. Tests that
      // exercise the trace path override this stub.
      when(
        () => shorebirdFlutter.resolveFlutterVersion(any()),
      ).thenAnswer((_) async => Version(3, 0, 0));

      // Default stub for the `flutter build <command> -h` probe used by
      // `_supportsTraceFlag`. Returns help text that includes
      // `--shorebird-trace` so that trace tests pass when tracing is enabled.
      // Tests that need to verify the flag is NOT passed should either use a
      // Flutter version below the trace threshold (the default 3.0.0) or
      // override this stub.
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: false,
        ),
      ).thenAnswer(
        (_) async => ShorebirdProcessResult(
          exitCode: ExitCode.success.code,
          stdout: '--shorebird-trace',
          stderr: '',
        ),
      );
      when(
        () => shorebirdProcess.stream(
          any(),
          any(),
          environment: any(named: 'environment'),
          runInShell: any(named: 'runInShell'),
          onStart: any(named: 'onStart'),
        ),
      ).thenAnswer((_) async => ExitCode.success.code);

      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => shorebirdEnv.flutterRevision).thenReturn('1234');
      when(
        () => shorebirdEnv.buildDirectory,
      ).thenReturn(Directory(p.join(projectRoot.path, 'build')));

      when(shorebirdEnv.getShorebirdProjectRoot).thenReturn(projectRoot);

      builder = ArtifactBuilder();
    });

    /// Checks that [testCall]'s build puts back the package_config.json the
    /// project had before it. The fake build rewrites that file and
    /// .dart_tool/version as `pub get` with Shorebird's Flutter does, and
    /// writes an app.dill for Apple builds to find.
    void verifyRestoresPackageConfig(
      Future<void> Function() testCall, {
      bool buildFails = false,
    }) {
      group('package_config.json', () {
        const original = '{"flutterRoot": "file:///system/flutter"}';
        late File packageConfig;
        late File version;

        setUp(() {
          final dartTool = p.join(projectRoot.path, '.dart_tool');
          packageConfig = File(p.join(dartTool, 'package_config.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync(original);
          version = File(p.join(dartTool, 'version'));
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              environment: any(named: 'environment'),
              runInShell: any(named: 'runInShell'),
              onStart: any(named: 'onStart'),
            ),
          ).thenAnswer((_) async {
            packageConfig.writeAsStringSync(
              '{"flutterRoot": "file:///shorebird/flutter"}',
            );
            version.writeAsStringSync('3.35.4');
            File(p.join(dartTool, 'flutter_build', 'h', 'app.dill'))
              ..createSync(recursive: true)
              ..setLastModifiedSync(
                DateTime.now().add(const Duration(seconds: 10)),
              );
            return buildFails ? ExitCode.software.code : ExitCode.success.code;
          });
        });

        test('restores the one from before the build', () async {
          await testCall();

          expect(packageConfig.readAsStringSync(), equals(original));
          expect(version.existsSync(), isFalse);
        });
      });
    }

    group('restoring package_config.json', () {
      const original = '{"flutterRoot": "file:///system/flutter"}';
      const vended = '{"flutterRoot": "file:///shorebird/flutter"}';
      late Directory packageConfigRoot;
      late bool buildRewritesConfig;

      File packageConfigIn(Directory root) =>
          File(p.join(root.path, '.dart_tool', 'package_config.json'));
      File versionIn(Directory root) =>
          File(p.join(root.path, '.dart_tool', 'version'));

      setUp(() {
        packageConfigRoot = projectRoot;
        buildRewritesConfig = true;
        when(
          () => artifactManager.linuxBundleDirectory,
        ).thenReturn(Directory(p.join(projectRoot.path, 'build')));
        when(
          () => shorebirdProcess.stream(
            any(),
            any(),
            environment: any(named: 'environment'),
            runInShell: any(named: 'runInShell'),
            onStart: any(named: 'onStart'),
          ),
        ).thenAnswer((_) async {
          if (buildRewritesConfig) {
            packageConfigIn(packageConfigRoot)
              ..createSync(recursive: true)
              ..writeAsStringSync(vended);
            versionIn(packageConfigRoot)
              ..createSync(recursive: true)
              ..writeAsStringSync('3.35.4');
          }
          return ExitCode.success.code;
        });
      });

      test("keeps the build's when there was none before", () async {
        await runWithOverrides(builder.buildLinuxApp);

        expect(
          packageConfigIn(projectRoot).readAsStringSync(),
          equals(vended),
        );
        expect(versionIn(projectRoot).existsSync(), isTrue);
      });

      test('leaves .dart_tool/version when the build kept the file', () async {
        buildRewritesConfig = false;
        packageConfigIn(projectRoot)
          ..createSync(recursive: true)
          ..writeAsStringSync(original);
        versionIn(projectRoot).writeAsStringSync('3.35.4');

        await runWithOverrides(builder.buildLinuxApp);

        expect(
          packageConfigIn(projectRoot).readAsStringSync(),
          equals(original),
        );
        expect(versionIn(projectRoot).existsSync(), isTrue);
      });

      group('in a pub workspace', () {
        late Directory app;

        setUp(() {
          packageConfigRoot = projectRoot;
          app = Directory(p.join(projectRoot.path, 'packages', 'app'));
          File(p.join(app.path, '.dart_tool', 'pub', 'workspace_ref.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync('{"workspaceRoot": "../../../.."}');
          when(shorebirdEnv.getShorebirdProjectRoot).thenReturn(app);
          packageConfigIn(projectRoot)
            ..createSync(recursive: true)
            ..writeAsStringSync(original);
        });

        test("restores the workspace root's", () async {
          await runWithOverrides(builder.buildLinuxApp);

          expect(
            packageConfigIn(projectRoot).readAsStringSync(),
            equals(original),
          );
          expect(versionIn(projectRoot).existsSync(), isFalse);
        });

        test(
          "uses the project's when workspace_ref.json is malformed",
          () async {
            File(
              p.join(app.path, '.dart_tool', 'pub', 'workspace_ref.json'),
            ).writeAsStringSync('not json');
            packageConfigRoot = app;
            packageConfigIn(app).writeAsStringSync(original);

            await runWithOverrides(builder.buildLinuxApp);

            expect(packageConfigIn(app).readAsStringSync(), equals(original));
            expect(
              packageConfigIn(projectRoot).readAsStringSync(),
              equals(original),
            );
          },
        );
      });
    });

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
            onStart: any(named: 'onStart'),
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
          () => shorebirdProcess.stream(
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
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
        ).called(1);
      });

      test(
        'onStart callback records a flow-start keyed to the child pid',
        () async {
          // Flutter needs to advertise trace support so the onStart
          // callback is wired in the first place.
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));

          // Capture the onStart callback the builder hands to
          // process.stream so we can invoke it with a fake child Process
          // carrying a known pid.
          void Function(Process)? capturedOnStart;
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              environment: any(named: 'environment'),
              runInShell: any(named: 'runInShell'),
              onStart: any(named: 'onStart'),
            ),
          ).thenAnswer((invocation) async {
            capturedOnStart =
                invocation.namedArguments[#onStart] as void Function(Process)?;
            return ExitCode.success.code;
          });

          final child = MockProcess();
          when(() => child.pid).thenReturn(12345);

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'android');
            await builder.buildAppBundle();
            expect(capturedOnStart, isNotNull);
            capturedOnStart!(child);

            final flowStarts = shorebirdTracer.events
                .where((e) => e['ph'] == 's')
                .toList();
            expect(flowStarts, hasLength(1));
            expect(flowStarts.single['id'], 12345);
            expect(flowStarts.single['cat'], 'flow');
          });
        },
      );

      test('adds --trace when Flutter supports build tracing', () async {
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => Version(3, 41, 7));

        await runWithOverrides(() async {
          await builder.prepareBuildTrace(platform: 'android');
          await builder.buildAppBundle();
        });

        final expectedTracePath = p.join(
          projectRoot.path,
          'build',
          'shorebird',
          'debug',
          'build-trace-android.json',
        );
        verify(
          () => shorebirdProcess.stream(
            'flutter',
            [
              'build',
              'appbundle',
              '--release',
              '--shorebird-trace=$expectedTracePath',
            ],
            environment: any(named: 'environment'),
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
        ).called(1);
      });

      test('caches trace flag probe result across calls', () async {
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => Version(3, 41, 7));

        await runWithOverrides(() async {
          await builder.prepareBuildTrace(platform: 'android');
          await builder.buildAppBundle();
          await builder.buildAppBundle();
        });

        // The help probe should only be called once despite two builds.
        verify(
          () => shorebirdProcess.run(
            'flutter',
            ['build', 'appbundle', '-h', '-v'],
            runInShell: false,
          ),
        ).called(1);
      });

      test(
        'detects --shorebird-trace even though it is hidden from -h',
        () async {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
          // Flutter registers --shorebird-trace with `hide: !verboseHelp`,
          // so it only appears in verbose help. Model that: plain `-h` omits
          // the flag, `-h -v` includes it. Probing without `-v` (the
          // original bug) would miss it and silently disable tracing on
          // every supported build.
          when(
            () => shorebirdProcess.run(
              'flutter',
              ['build', 'appbundle', '-h'],
              runInShell: false,
            ),
          ).thenAnswer(
            (_) async => ShorebirdProcessResult(
              exitCode: ExitCode.success.code,
              stdout: '--release',
              stderr: '',
            ),
          );
          when(
            () => shorebirdProcess.run(
              'flutter',
              ['build', 'appbundle', '-h', '-v'],
              runInShell: false,
            ),
          ).thenAnswer(
            (_) async => ShorebirdProcessResult(
              exitCode: ExitCode.success.code,
              stdout: '--release\n--shorebird-trace',
              stderr: '',
            ),
          );

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'android');
            await builder.buildAppBundle();
          });

          final expectedTracePath = p.join(
            projectRoot.path,
            'build',
            'shorebird',
            'debug',
            'build-trace-android.json',
          );
          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'appbundle',
                '--release',
                '--shorebird-trace=$expectedTracePath',
              ],
              environment: any(named: 'environment'),
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        },
      );

      test('skips trace when help probe throws', () async {
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => Version(3, 41, 7));
        when(
          () => shorebirdProcess.run(
            'flutter',
            ['build', 'appbundle', '-h', '-v'],
            runInShell: false,
          ),
        ).thenThrow(Exception('process failed'));

        await runWithOverrides(() async {
          await builder.prepareBuildTrace(platform: 'android');
          await builder.buildAppBundle();
        });

        verify(
          () => shorebirdProcess.stream(
            'flutter',
            [
              'build',
              'appbundle',
              '--release',
            ],
            environment: any(named: 'environment'),
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
                '''Build succeeded, but it generated multiple AABs in the build directory. (${File('a').path}, ${File('b').path})''',
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
                onStart: any(named: 'onStart'),
              ),
            ).thenAnswer((_) async => ExitCode.success.code);
          });

          verifyRestoresPackageConfig(
            () => runWithOverrides(() => builder.buildAppBundle()),
          );

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                  onStart: any(named: 'onStart'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyRestoresPackageConfig(
              buildFails: true,
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

            group('when a plugin references the legacy flutter.jar', () {
              setUp(() {
                final pluginRoot = Directory(
                  p.join(projectRoot.path, 'huawei_location'),
                );
                Directory(
                  p.join(pluginRoot.path, 'android'),
                ).createSync(recursive: true);
                File(
                  p.join(pluginRoot.path, 'android', 'build.gradle'),
                ).writeAsStringSync('compileOnly files("...flutter.jar")');
                File(
                  p.join(projectRoot.path, '.flutter-plugins-dependencies'),
                ).writeAsStringSync(
                  '{"plugins": {"android": [{"name": "huawei_location", '
                  '"path": "${pluginRoot.path.replaceAll(r'\', r'\\')}", '
                  '"native_build": true, "dependencies": []}]}}',
                );
              });

              test('prepends a targeted hint to the recommendation', () async {
                await expectLater(
                  () => runWithOverrides(() => builder.buildAppBundle()),
                  throwsA(
                    isA<ArtifactBuildException>().having(
                      (e) => e.fixRecommendation,
                      'recommendation',
                      allOf(
                        contains('legacy `flutter.jar`'),
                        contains('• huawei_location'),
                      ),
                    ),
                  ),
                );
              });
            });
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
            onStart: any(named: 'onStart'),
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
          () => shorebirdProcess.stream(
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
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
        ).called(1);
      });

      group('when Flutter supports build tracing', () {
        setUp(() {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
        });

        test(
          'passes --trace with a path under build/shorebird/debug',
          () async {
            await runWithOverrides(() async {
              await builder.prepareBuildTrace(platform: 'android');
              await builder.buildApk();
            });

            final expectedTracePath = p.join(
              projectRoot.path,
              'build',
              'shorebird',
              'debug',
              'build-trace-android.json',
            );
            verify(
              () => shorebirdProcess.stream(
                'flutter',
                [
                  'build',
                  'apk',
                  '--release',
                  '--shorebird-trace=$expectedTracePath',
                ],
                environment: any(named: 'environment'),
                runInShell: false,
                onStart: any(named: 'onStart'),
              ),
            ).called(1);
            expect(
              Directory(p.dirname(expectedTracePath)).existsSync(),
              isTrue,
            );
          },
        );

        test(
          'writes a summary JSON next to a trace file Flutter produced',
          () async {
            final traceFile = File(
              p.join(
                projectRoot.path,
                'build',
                'shorebird',
                'debug',
                'build-trace-android.json',
              ),
            );
            // Simulate Flutter writing the trace: create the file just before
            // the build command would return.
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                environment: any(named: 'environment'),
                runInShell: any(named: 'runInShell'),
                onStart: any(named: 'onStart'),
              ),
            ).thenAnswer((_) async {
              traceFile.parent.createSync(recursive: true);
              traceFile.writeAsStringSync(
                jsonEncode([
                  {
                    'ph': 'X',
                    'name': 'pre-gradle setup',
                    'cat': 'flutter',
                    'ts': 1000,
                    'dur': 100,
                    'pid': 1,
                    'tid': 1,
                  },
                  {
                    'ph': 'X',
                    'name': 'gradle assembleRelease',
                    'cat': 'gradle',
                    'ts': 1100,
                    'dur': 3_000_000,
                    'pid': 1,
                    'tid': 2,
                  },
                  {
                    'ph': 'X',
                    'name': 'kernel_snapshot_program',
                    'cat': 'assemble',
                    'ts': 2000,
                    'dur': 500_000,
                    'pid': 1,
                    'tid': 3,
                  },
                  {
                    'ph': 'X',
                    'name': 'android_aot',
                    'cat': 'assemble',
                    'ts': 500000,
                    'dur': 200_000,
                    'pid': 1,
                    'tid': 3,
                  },
                  {
                    'ph': 'X',
                    'name': 'flutter build apk',
                    'cat': 'flutter',
                    'ts': 1000,
                    'dur': 3_000_100,
                    'pid': 1,
                    'tid': 1,
                  },
                ]),
              );
              return ExitCode.success.code;
            });

            await runWithOverrides(() async {
              await builder.prepareBuildTrace(platform: 'android');
              await builder.buildApk();
              builder.writeBuildTraceSummary();
            });

            final summaryFile = File(
              p.join(
                p.dirname(traceFile.path),
                'build-trace-android-summary.json',
              ),
            );
            expect(summaryFile.existsSync(), isTrue);
            final summary =
                jsonDecode(summaryFile.readAsStringSync())
                    as Map<String, Object?>;
            expect(summary['platform'], 'android');
            expect(summary['version'], 9);
            // 500ms kernel + 200ms aot
            expect((summary['dart']! as Map)['totalMs'], 700);
            expect(summary['flutterBuildMs'], 3000);
            expect(summary['shorebirdOverheadMs'], isNonNegative);
            final dart = summary['dart']! as Map<String, Object?>;
            expect(dart['kernelSnapshotMs'], 500);
            expect(dart['genSnapshotMs'], 200);
            final assemble =
                summary['flutterAssemble']! as Map<String, Object?>;
            expect(assemble['targetCount'], 2);
            expect(summary['android'], isA<Map<String, Object?>>());
            expect(summary.containsKey('ios'), isFalse);
          },
        );
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
                '''Build succeeded, but it generated multiple APKs in the build directory. (${File('a').path}, ${File('b').path})''',
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
                onStart: any(named: 'onStart'),
              ),
            ).thenAnswer((_) async => ExitCode.success.code);
          });

          verifyRestoresPackageConfig(
            () => runWithOverrides(() => builder.buildApk()),
          );

          group('when the build fails', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                  onStart: any(named: 'onStart'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyRestoresPackageConfig(
              buildFails: true,
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

      test(
        'skips --shorebird-trace when help probe shows no support',
        () async {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
          when(
            () => shorebirdProcess.run(
              'flutter',
              ['build', 'aar', '-h', '-v'],
              runInShell: false,
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: 'no trace flag here',
              stderr: '',
            ),
          );

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'android');
            await builder.buildAar(buildNumber: buildNumber);
          });

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
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        },
      );

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
            onStart: any(named: 'onStart'),
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
          () => shorebirdProcess.stream(
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
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
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
              onStart: any(named: 'onStart'),
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
                onStart: any(named: 'onStart'),
              ),
            ).thenAnswer((_) async => ExitCode.success.code);
          });

          verifyRestoresPackageConfig(
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
                  onStart: any(named: 'onStart'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyRestoresPackageConfig(
              buildFails: true,
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

      test(
        'skips --shorebird-trace when help probe shows no support',
        () async {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
          when(
            () => shorebirdProcess.run(
              'flutter',
              ['build', 'linux', '-h', '-v'],
              runInShell: false,
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: 'no trace flag here',
              stderr: '',
            ),
          );

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'linux');
            await builder.buildLinuxApp();
          });

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'linux',
                '--release',
              ],
              environment: any(named: 'environment'),
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        },
      );

      group('when flutter build fails', () {
        setUp(() {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
              onStart: any(named: 'onStart'),
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
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'linux',
                '--release',
                '--target=target.dart',
              ],
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
            onStart: any(named: 'onStart'),
          ),
        ).thenAnswer((_) async {
          appDill =
              File(
                  p.join(
                    projectRoot.path,
                    '.dart_tool',
                    'flutter_build',
                    'h',
                    'app.dill',
                  ),
                )
                ..createSync(recursive: true)
                ..setLastModifiedSync(
                  DateTime.now().add(const Duration(seconds: 10)),
                );

          return ExitCode.success.code;
        });
      });

      test(
        'skips --shorebird-trace when help probe shows no support',
        () async {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
          when(
            () => shorebirdProcess.run(
              'flutter',
              ['build', 'macos', '-h', '-v'],
              runInShell: false,
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: 'no trace flag here',
              stderr: '',
            ),
          );

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'macos');
            await builder.buildMacos();
          });

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'macos',
                '--release',
              ],
              environment: any(named: 'environment'),
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        },
      );

      group('when .dart_tool directory exists', () {
        late File packageConfig;
        late File buildRunnerCache;
        late File versionFile;
        late File buildCache;
        setUp(() {
          File dartToolFile(List<String> parts) => File(
            p.joinAll([projectRoot.path, '.dart_tool', ...parts]),
          )..createSync(recursive: true);
          packageConfig = dartToolFile(['package_config.json']);
          buildRunnerCache = dartToolFile([
            'build',
            'entrypoint',
            'build.dart',
          ]);
          versionFile = dartToolFile(['version']);
          buildCache = dartToolFile(['flutter_build', 'a.stamp']);
        });

        test('deletes the flutter_build cache before building', () async {
          await runWithOverrides(builder.buildMacos);
          expect(buildCache.existsSync(), isFalse);
        });

        test('deletes .dart_tool/version so pub get re-runs', () async {
          await runWithOverrides(builder.buildMacos);
          expect(versionFile.existsSync(), isFalse);
        });

        test('keeps the rest of .dart_tool', () async {
          await runWithOverrides(builder.buildMacos);
          expect(packageConfig.existsSync(), isTrue);
          expect(buildRunnerCache.existsSync(), isTrue);
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
          () => shorebirdProcess.stream(
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
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
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
                onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
          verifyRestoresPackageConfig(
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
                  onStart: any(named: 'onStart'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyRestoresPackageConfig(
              buildFails: true,
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
            onStart: any(named: 'onStart'),
          ),
        ).thenAnswer((_) async {
          appDill =
              File(
                  p.join(
                    projectRoot.path,
                    '.dart_tool',
                    'flutter_build',
                    'h',
                    'app.dill',
                  ),
                )
                ..createSync(recursive: true)
                ..setLastModifiedSync(
                  DateTime.now().add(const Duration(seconds: 10)),
                );

          return ExitCode.success.code;
        });
      });

      group('when .dart_tool directory exists', () {
        late File packageConfig;
        late File buildRunnerCache;
        late File versionFile;
        late File buildCache;
        setUp(() {
          File dartToolFile(List<String> parts) => File(
            p.joinAll([projectRoot.path, '.dart_tool', ...parts]),
          )..createSync(recursive: true);
          packageConfig = dartToolFile(['package_config.json']);
          buildRunnerCache = dartToolFile([
            'build',
            'entrypoint',
            'build.dart',
          ]);
          versionFile = dartToolFile(['version']);
          buildCache = dartToolFile(['flutter_build', 'a.stamp']);
        });

        test('deletes the flutter_build cache before building', () async {
          await runWithOverrides(builder.buildIpa);
          expect(buildCache.existsSync(), isFalse);
        });

        test('deletes .dart_tool/version so pub get re-runs', () async {
          await runWithOverrides(builder.buildIpa);
          expect(versionFile.existsSync(), isFalse);
        });

        test('keeps the rest of .dart_tool', () async {
          await runWithOverrides(builder.buildIpa);
          expect(packageConfig.existsSync(), isTrue);
          expect(buildRunnerCache.existsSync(), isTrue);
        });

        test('ignores app.dill files outside flutter_build', () async {
          when(
            () => shorebirdProcess.stream(
              any(),
              any(),
              environment: any(named: 'environment'),
              runInShell: any(named: 'runInShell'),
              onStart: any(named: 'onStart'),
            ),
          ).thenAnswer((_) async {
            File(p.join(projectRoot.path, '.dart_tool', 'build', 'app.dill'))
              ..createSync(recursive: true)
              ..setLastModifiedSync(
                DateTime.now().add(const Duration(seconds: 10)),
              );
            return ExitCode.success.code;
          });

          await expectLater(
            () => runWithOverrides(builder.buildIpa),
            throwsA(
              isA<ArtifactBuildException>().having(
                (e) => e.message,
                'message',
                'Unable to find app.dill file.',
              ),
            ),
          );
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
          () => shorebirdProcess.stream(
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
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
        ).called(1);
      });

      group('when Flutter supports build tracing', () {
        setUp(() {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
        });

        test(
          'passes --trace with a path under build/shorebird/debug',
          () async {
            await runWithOverrides(() async {
              await builder.prepareBuildTrace(platform: 'ios');
              await builder.buildIpa();
            });

            final expectedTracePath = p.join(
              projectRoot.path,
              'build',
              'shorebird',
              'debug',
              'build-trace-ios.json',
            );
            verify(
              () => shorebirdProcess.stream(
                'flutter',
                [
                  'build',
                  'ipa',
                  '--release',
                  '--shorebird-trace=$expectedTracePath',
                ],
                environment: any(named: 'environment'),
                runInShell: false,
                onStart: any(named: 'onStart'),
              ),
            ).called(1);
            expect(
              Directory(p.dirname(expectedTracePath)).existsSync(),
              isTrue,
            );
          },
        );
      });

      group('when the build fails', () {
        group('with non-zero exit code', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
                onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
          verifyRestoresPackageConfig(
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
                  onStart: any(named: 'onStart'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyRestoresPackageConfig(
              buildFails: true,
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
            onStart: any(named: 'onStart'),
          ),
        ).thenAnswer((_) async {
          appDill =
              File(
                  p.join(
                    projectRoot.path,
                    '.dart_tool',
                    'flutter_build',
                    'h',
                    'app.dill',
                  ),
                )
                ..createSync(recursive: true)
                ..setLastModifiedSync(
                  DateTime.now().add(const Duration(seconds: 10)),
                );

          return ExitCode.success.code;
        });
      });

      test(
        'skips --shorebird-trace when help probe shows no support',
        () async {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
          when(
            () => shorebirdProcess.run(
              'flutter',
              ['build', 'ios-framework', '-h', '-v'],
              runInShell: false,
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: 'no trace flag here',
              stderr: '',
            ),
          );

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'ios');
            await builder.buildIosFramework();
          });

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'ios-framework',
                '--no-debug',
                '--no-profile',
              ],
              environment: any(named: 'environment'),
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        },
      );

      group('when .dart_tool directory exists', () {
        late File packageConfig;
        late File buildRunnerCache;
        late File versionFile;
        late File buildCache;
        setUp(() {
          File dartToolFile(List<String> parts) => File(
            p.joinAll([projectRoot.path, '.dart_tool', ...parts]),
          )..createSync(recursive: true);
          packageConfig = dartToolFile(['package_config.json']);
          buildRunnerCache = dartToolFile([
            'build',
            'entrypoint',
            'build.dart',
          ]);
          versionFile = dartToolFile(['version']);
          buildCache = dartToolFile(['flutter_build', 'a.stamp']);
        });

        test('deletes the flutter_build cache before building', () async {
          await runWithOverrides(builder.buildIosFramework);
          expect(buildCache.existsSync(), isFalse);
        });

        test('deletes .dart_tool/version so pub get re-runs', () async {
          await runWithOverrides(builder.buildIosFramework);
          expect(versionFile.existsSync(), isFalse);
        });

        test('keeps the rest of .dart_tool', () async {
          await runWithOverrides(builder.buildIosFramework);
          expect(packageConfig.existsSync(), isTrue);
          expect(buildRunnerCache.existsSync(), isTrue);
        });
      });

      group('when the module has generated Xcode properties', () {
        const vendedRoot = '/shorebird/bin/cache/flutter/1234';
        late File xcconfig;
        late File exportEnvironment;

        void writeProperties({required String flutterRoot}) {
          final flutterDir = p.join(projectRoot.path, '.ios', 'Flutter');
          xcconfig = File(p.join(flutterDir, 'Generated.xcconfig'))
            ..createSync(recursive: true)
            ..writeAsStringSync('''
// This is a generated file; do not edit or check into version control.
FLUTTER_ROOT=$flutterRoot
FLUTTER_APPLICATION_PATH=${projectRoot.path}
''');
          exportEnvironment = File(
            p.join(flutterDir, 'flutter_export_environment.sh'),
          )..writeAsStringSync('export "FLUTTER_ROOT=$flutterRoot"\n');
        }

        setUp(() {
          when(
            () => shorebirdEnv.flutterDirectory,
          ).thenReturn(Directory(vendedRoot));
        });

        test('deletes them when they name another Flutter', () async {
          writeProperties(flutterRoot: '/Users/me/Developer/flutter');

          await runWithOverrides(builder.buildIosFramework);

          expect(xcconfig.existsSync(), isFalse);
          expect(exportEnvironment.existsSync(), isFalse);
        });

        test('deletes them when they name no Flutter', () async {
          writeProperties(flutterRoot: vendedRoot);
          xcconfig.writeAsStringSync('FLUTTER_APPLICATION_PATH=/app\n');

          await runWithOverrides(builder.buildIosFramework);

          expect(xcconfig.existsSync(), isFalse);
          expect(exportEnvironment.existsSync(), isFalse);
        });

        test("keeps them when they name Shorebird's Flutter", () async {
          writeProperties(flutterRoot: vendedRoot);

          await runWithOverrides(builder.buildIosFramework);

          expect(xcconfig.existsSync(), isTrue);
          expect(exportEnvironment.existsSync(), isTrue);
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
            onStart: any(named: 'onStart'),
          ),
        ).called(1);
        expect(result.kernelFile.path, equals(appDill.path));
      });

      test('uses the first app.dill the build produced', () async {
        late File firstAppDill;
        late File secondAppDill;
        when(
          () => shorebirdProcess.stream(
            any(),
            any(),
            environment: any(named: 'environment'),
            runInShell: any(named: 'runInShell'),
            onStart: any(named: 'onStart'),
          ),
        ).thenAnswer((_) async {
          final now = DateTime.now();
          // The earlier file sorts second by name, so the test can't pass on
          // directory listing order alone.
          secondAppDill =
              File(
                  p.join(
                    projectRoot.path,
                    '.dart_tool',
                    'flutter_build',
                    'a',
                    'app.dill',
                  ),
                )
                ..createSync(recursive: true)
                ..setLastModifiedSync(now.add(const Duration(seconds: 20)));
          firstAppDill =
              File(
                  p.join(
                    projectRoot.path,
                    '.dart_tool',
                    'flutter_build',
                    'b',
                    'app.dill',
                  ),
                )
                ..createSync(recursive: true)
                ..setLastModifiedSync(now.add(const Duration(seconds: 10)));
          return ExitCode.success.code;
        });

        final result = await runWithOverrides(builder.buildIosFramework);

        expect(result.kernelFile.path, equals(firstAppDill.path));
        expect(result.kernelFile.path, isNot(equals(secondAppDill.path)));
      });

      test('forward arguments to flutter build', () async {
        await runWithOverrides(
          () => builder.buildIosFramework(args: ['--foo', 'bar']),
        );

        verify(
          () => shorebirdProcess.stream(
            'flutter',
            [
              'build',
              'ios-framework',
              '--no-debug',
              '--no-profile',
              '--foo',
              'bar',
            ],
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
        ).called(1);
      });

      test('passes the target to flutter build', () async {
        await runWithOverrides(
          () => builder.buildIosFramework(target: 'lib/main_prod.dart'),
        );

        verify(
          () => shorebirdProcess.stream(
            'flutter',
            [
              'build',
              'ios-framework',
              '--no-debug',
              '--no-profile',
              '--target=lib/main_prod.dart',
            ],
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
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
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        });
      });

      group('after a build', () {
        group('when the build is successful', () {
          verifyRestoresPackageConfig(
            () => runWithOverrides(builder.buildIosFramework),
          );

          group('when no app.dill file is found in build stdout', () {
            setUp(() {
              when(
                () => shorebirdProcess.stream(
                  any(),
                  any(),
                  runInShell: any(named: 'runInShell'),
                  onStart: any(named: 'onStart'),
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
                  onStart: any(named: 'onStart'),
                ),
              ).thenAnswer((_) async => ExitCode.software.code);
            });

            verifyRestoresPackageConfig(
              buildFails: true,
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
            () => shorebirdProcess.stream(
              'gen_snapshot',
              [
                '--deterministic',
                '--snapshot-kind=app-aot-elf',
                '--elf=/path/to/out',
                '--foo',
                'bar',
                '/app/dill/path',
              ],
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        });

        group('when build fails', () {
          setUp(() {
            when(
              () => shorebirdProcess.stream(
                any(),
                any(),
                runInShell: any(named: 'runInShell'),
                onStart: any(named: 'onStart'),
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
          () => shorebirdProcess.stream(
            'flutter',
            [
              'build',
              'windows',
              '--release',
            ],
            runInShell: false,
            onStart: any(named: 'onStart'),
          ),
        ).thenAnswer((_) async => ExitCode.success.code);
      });

      test(
        'skips --shorebird-trace when help probe shows no support',
        () async {
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => Version(3, 41, 7));
          when(
            () => shorebirdProcess.run(
              'flutter',
              ['build', 'windows', '-h', '-v'],
              runInShell: false,
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: 'no trace flag here',
              stderr: '',
            ),
          );

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'windows');
            await builder.buildWindowsApp();
          });

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'windows',
                '--release',
              ],
              environment: any(named: 'environment'),
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        },
      );

      group('when target is provided', () {
        test('forwards target to flutter command', () async {
          await runWithOverrides(
            () => builder.buildWindowsApp(target: 'target.dart'),
          );

          verify(
            () => shorebirdProcess.stream(
              'flutter',
              [
                'build',
                'windows',
                '--release',
                '--target=target.dart',
              ],
              runInShell: false,
              onStart: any(named: 'onStart'),
            ),
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
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
              onStart: any(named: 'onStart'),
            ),
          ).called(1);
        });
      });
    });

    group('prepareBuildTrace', () {
      test(
        'leaves traceFile null when Flutter pin does not support tracing',
        () async {
          // shorebirdFlutter.resolveFlutterVersion default in setUp is 3.0.0,
          // which is below buildTraceSupportConstraint.minVersion.
          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'android');
            expect(buildTraceSession.traceFile, isNull);
            expect(buildTraceSession.platform, 'android');
          });
        },
      );

      test('sets traceFile for a version at the floor', () async {
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => buildTraceSupportConstraint.minVersion);

        await runWithOverrides(() async {
          await builder.prepareBuildTrace(platform: 'android');
          expect(buildTraceSession.traceFile, isNotNull);
        });
      });

      test(
        'treats unresolved Flutter version as new enough (dev pin)',
        () async {
          // resolveFlutterVersion returns null for revisions not on a
          // flutter_release branch (e.g. a pinned dev revision). The
          // minVersion fallback admits these.
          when(
            () => shorebirdFlutter.resolveFlutterVersion(any()),
          ).thenAnswer((_) async => null);

          await runWithOverrides(() async {
            await builder.prepareBuildTrace(platform: 'android');
            expect(buildTraceSession.traceFile, isNotNull);
          });
        },
      );
    });

    group('writeBuildTraceSummary', () {
      test('logs detail and returns when trace file is missing', () async {
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => Version(3, 41, 7));

        await runWithOverrides(() async {
          await builder.prepareBuildTrace(platform: 'android');
          // Simulate a build that never produced a trace file (e.g. an
          // older Flutter that accepts --shorebird-trace but silently
          // drops the flag, or a build that failed before writing).
          expect(buildTraceSession.traceFile!.existsSync(), isFalse);
          builder.writeBuildTraceSummary();
          expect(buildTraceSession.summary, isNull);
        });

        verify(
          () => logger.detail(
            any(that: contains('Skipping build trace summary')),
          ),
        ).called(1);
      });
    });
  });
}
