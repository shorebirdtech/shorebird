import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

/// A minimal [Releaser] for testing the behavior every platform shares.
/// Platform tests only check that each releaser wires these helpers in.
class _TestReleaser extends Releaser {
  _TestReleaser({required super.argResults})
    : super(flavor: null, target: null);

  @override
  ReleaseType get releaseType => ReleaseType.linux;

  @override
  String get artifactDisplayName => 'Test app';

  @override
  String get supplementPlatformSubdir => 'test';

  @override
  String get supplementArtifactArch => 'test_supplement';

  @override
  String get postReleaseInstructions => '';

  @override
  Future<void> assertArgsAreValid() async {}

  @override
  Future<void> assertPreconditions() async {}

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async => Directory('');

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async => '1.0.0';

  /// What [prepareReleaseArtifacts] returns.
  List<ReleaseArtifactUpload> artifacts = const [];

  /// What [prepareReleaseArtifacts] throws, if anything.
  Exception? prepareError;

  /// The staging directory [prepareReleaseArtifacts] was last called with.
  Directory? stagingDirectory;

  @override
  Future<List<ReleaseArtifactUpload>> prepareReleaseArtifacts({
    required Directory stagingDirectory,
  }) async {
    this.stagingDirectory = stagingDirectory;
    expect(stagingDirectory.existsSync(), isTrue);
    if (prepareError != null) throw prepareError!;
    return artifacts;
  }
}

void main() {
  useTempWorkingDirectory();
  group(Releaser, () {
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdLogger logger;
    late _TestReleaser releaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    String obfuscationMapPath() =>
        p.join(projectRoot.path, 'build', 'shorebird', 'obfuscation_map.json');

    void setObfuscate({required bool enabled}) {
      when(() => argResults['obfuscate']).thenReturn(enabled);
      when(() => argResults.wasParsed('obfuscate')).thenReturn(enabled);
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(ReleasePlatform.linux);
      registerFallbackValue(<ReleaseArtifactUpload>[]);
    });

    setUp(() {
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      logger = MockShorebirdLogger();

      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults['obfuscate']).thenReturn(false);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn('deadbeef');

      releaser = _TestReleaser(argResults: argResults);
    });

    group('assertReleaseVersionFlagNotProvided', () {
      test('returns normally when --release-version is not passed', () {
        expect(
          () => runWithOverrides(releaser.assertReleaseVersionFlagNotProvided),
          returnsNormally,
        );
      });

      test('logs error and exits with usage code when passed', () {
        when(() => argResults.wasParsed('release-version')).thenReturn(true);

        expect(
          () => runWithOverrides(releaser.assertReleaseVersionFlagNotProvided),
          exitsWithCode(ExitCode.usage),
        );
        verify(
          () => logger.err(
            '''
The "--release-version" flag is only supported for aar and ios-framework releases.

To change the version of this release, change your app's version in your pubspec.yaml.''',
          ),
        ).called(1);
      });
    });

    group('useObfuscation', () {
      test('is false by default', () {
        expect(releaser.useObfuscation, isFalse);
      });

      test('is true when --obfuscate is parsed', () {
        setObfuscate(enabled: true);
        expect(releaser.useObfuscation, isTrue);
      });

      test('is true when --obfuscate is forwarded after --', () {
        when(() => argResults.rest).thenReturn(['--obfuscate']);
        expect(releaser.useObfuscation, isTrue);
      });
    });

    group('ddMaxBytes', () {
      test('is null when the option is absent', () {
        when(() => argResults['dd-max-bytes']).thenReturn(null);
        expect(releaser.ddMaxBytes, isNull);
      });

      test('parses a positive value', () {
        when(() => argResults['dd-max-bytes']).thenReturn('10000');
        expect(releaser.ddMaxBytes, equals(10000));
      });

      test('is null for 0, negative, or malformed values', () {
        for (final value in ['0', '-1', 'abc']) {
          when(() => argResults['dd-max-bytes']).thenReturn(value);
          expect(releaser.ddMaxBytes, isNull, reason: value);
        }
      });
    });

    group('addSplitDebugInfoDefault', () {
      test('is a no-op without obfuscation', () {
        final buildArgs = <String>[];
        releaser.addSplitDebugInfoDefault(buildArgs);
        expect(buildArgs, isEmpty);
      });

      test('adds a default --split-debug-info when obfuscating', () {
        setObfuscate(enabled: true);
        final buildArgs = <String>[];
        releaser.addSplitDebugInfoDefault(buildArgs);
        expect(
          buildArgs,
          equals([
            '--split-debug-info=${p.join('build', 'shorebird', 'symbols')}',
          ]),
        );
      });

      test('preserves a user-provided --split-debug-info', () {
        setObfuscate(enabled: true);
        final buildArgs = ['--split-debug-info=my/symbols'];
        releaser.addSplitDebugInfoDefault(buildArgs);
        expect(buildArgs, equals(['--split-debug-info=my/symbols']));
      });
    });

    group('addObfuscationMapArgs', () {
      // Flutter PR https://github.com/flutter/flutter/pull/181275 (3.44)
      // moved libapp.so stripping responsibility from gen_snapshot to AGP on
      // Android. shouldPreStripLibappInGenSnapshot decides per platform and
      // Flutter revision; the releaser must honor its answer.
      void stubPreStrip({required bool preStrip}) {
        when(
          () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
            platform: any(named: 'platform'),
            flutterRevision: any(named: 'flutterRevision'),
          ),
        ).thenAnswer((_) async => preStrip);
      }

      String saveMapArg() =>
          '--extra-gen-snapshot-options='
          '--save-obfuscation-map=${obfuscationMapPath()}';

      test('is a no-op when --obfuscate is not set', () async {
        final buildArgs = <String>[];
        await runWithOverrides(() => releaser.addObfuscationMapArgs(buildArgs));
        expect(buildArgs, isEmpty);
      });

      test('saves the obfuscation map and passes --strip', () async {
        setObfuscate(enabled: true);
        stubPreStrip(preStrip: true);

        final buildArgs = <String>[];
        await runWithOverrides(() => releaser.addObfuscationMapArgs(buildArgs));

        expect(
          buildArgs,
          equals([saveMapArg(), '--extra-gen-snapshot-options=--strip']),
        );
        expect(Directory(p.dirname(obfuscationMapPath())).existsSync(), isTrue);
        verify(
          () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
            platform: ReleasePlatform.linux,
            flutterRevision: 'deadbeef',
          ),
        ).called(1);
      });

      test('omits --strip when the platform strips libapp.so itself', () async {
        setObfuscate(enabled: true);
        stubPreStrip(preStrip: false);

        final buildArgs = <String>[];
        await runWithOverrides(() => releaser.addObfuscationMapArgs(buildArgs));

        expect(buildArgs, equals([saveMapArg()]));
      });
    });

    group('runReleaseBuild', () {
      setUp(() {
        when(() => argResults.rest).thenReturn(['--dart-define=FOO=bar']);
        when(
          () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
            platform: any(named: 'platform'),
            flutterRevision: any(named: 'flutterRevision'),
          ),
        ).thenAnswer((_) async => true);
      });

      test('builds with the forwarded args and returns the result', () async {
        List<String>? receivedArgs;
        final result = await runWithOverrides(
          () => releaser.runReleaseBuild((buildArgs, base64PublicKey) async {
            receivedArgs = buildArgs;
            expect(base64PublicKey, isNull);
            return 'built';
          }),
        );

        expect(result, equals('built'));
        expect(receivedArgs, equals(['--dart-define=FOO=bar']));
      });

      test(
        'adds the split-debug-info and obfuscation map args, then verifies '
        'the map the build saved',
        () async {
          setObfuscate(enabled: true);
          List<String>? receivedArgs;
          final saveMapArg =
              '--extra-gen-snapshot-options='
              '--save-obfuscation-map=${obfuscationMapPath()}';

          await runWithOverrides(
            () => releaser.runReleaseBuild((buildArgs, _) async {
              receivedArgs = buildArgs;
              File(obfuscationMapPath()).createSync(recursive: true);
            }),
          );

          expect(
            receivedArgs,
            equals([
              '--dart-define=FOO=bar',
              '--obfuscate',
              '--split-debug-info=${p.join('build', 'shorebird', 'symbols')}',
              saveMapArg,
              '--extra-gen-snapshot-options=--strip',
            ]),
          );
          verify(
            () => logger.detail(
              'Obfuscation map saved to ${obfuscationMapPath()}',
            ),
          ).called(1);
        },
      );

      test(
        'deletes the supplement directory before building, leaving the rest '
        'of the build directory alone',
        () async {
          final buildDir = Directory(p.join(projectRoot.path, 'build'));
          final supplementDir = Directory(
            p.join(buildDir.path, 'test', 'shorebird'),
          );
          File(p.join(supplementDir.path, 'App.ct.link'))
            ..createSync(recursive: true)
            ..writeAsStringSync('stale');
          final siblingFile = File(p.join(buildDir.path, 'test', 'output'))
            ..writeAsStringSync('keep');
          final sharedFile = File(
            p.join(buildDir.path, 'shorebird', 'obfuscation_map.json'),
          )..createSync(recursive: true);

          bool? supplementExistedDuringBuild;
          await runWithOverrides(
            () => releaser.runReleaseBuild((_, _) async {
              supplementExistedDuringBuild = supplementDir.existsSync();
            }),
          );

          expect(supplementExistedDuringBuild, isFalse);
          expect(siblingFile.existsSync(), isTrue);
          expect(sharedFile.existsSync(), isTrue);
        },
      );

      test('builds normally when there is no supplement directory', () async {
        await expectLater(
          runWithOverrides(
            () => releaser.runReleaseBuild((_, _) async => 'built'),
          ),
          completion(equals('built')),
        );
      });

      test('exits after the build when it saved no obfuscation map', () async {
        setObfuscate(enabled: true);
        var built = false;

        await expectLater(
          () => runWithOverrides(
            () => releaser.runReleaseBuild((_, _) async => built = true),
          ),
          exitsWithCode(ExitCode.software),
        );
        expect(built, isTrue);
      });
    });

    group('verifyObfuscationMap', () {
      test('is a no-op without obfuscation', () {
        expect(
          () => runWithOverrides(releaser.verifyObfuscationMap),
          returnsNormally,
        );
        verifyNever(() => logger.err(any()));
      });

      test('logs the map location when the map was generated', () {
        setObfuscate(enabled: true);
        File(obfuscationMapPath()).createSync(recursive: true);

        runWithOverrides(releaser.verifyObfuscationMap);

        verify(
          () =>
              logger.detail('Obfuscation map saved to ${obfuscationMapPath()}'),
        ).called(1);
      });

      test('logs error and exits when the map was not generated', () {
        setObfuscate(enabled: true);

        expect(
          () => runWithOverrides(releaser.verifyObfuscationMap),
          exitsWithCode(ExitCode.software),
        );
        verify(
          () => logger.err(
            any(
              that: contains(
                'Obfuscation was enabled but the obfuscation map was not',
              ),
            ),
          ),
        ).called(1);
      });
    });

    group('assembleSupplementDirectory', () {
      late Directory supplementDir;

      setUp(() {
        supplementDir = Directory(
          p.join(projectRoot.path, 'build', 'test', 'shorebird'),
        )..createSync(recursive: true);

        when(
          () => artifactManager.getReleaseSupplementDirectory(
            platformSubdir: any(named: 'platformSubdir'),
            create: any(named: 'create'),
          ),
        ).thenAnswer((invocation) {
          final create =
              invocation.namedArguments[const Symbol('create')] as bool;
          if (!supplementDir.existsSync() && create) {
            supplementDir.createSync(recursive: true);
          }
          return supplementDir.existsSync() ? supplementDir : null;
        });
      });

      test('copies the obfuscation map into the supplement directory', () {
        setObfuscate(enabled: true);
        File(obfuscationMapPath())
          ..createSync(recursive: true)
          ..writeAsStringSync('{"key": "value"}');

        final result = runWithOverrides(releaser.assembleSupplementDirectory);

        expect(result?.path, equals(supplementDir.path));
        final mapInSupplement = File(
          p.join(supplementDir.path, 'obfuscation_map.json'),
        );
        expect(mapInSupplement.readAsStringSync(), '{"key": "value"}');
        verify(
          () => artifactManager.getReleaseSupplementDirectory(
            platformSubdir: 'test',
            create: true,
          ),
        ).called(1);
      });

      test('returns null when there is no supplement directory', () {
        supplementDir.deleteSync(recursive: true);

        final result = runWithOverrides(releaser.assembleSupplementDirectory);

        expect(result, isNull);
      });

      test('removes a stale obfuscation map and returns null', () {
        File(p.join(supplementDir.path, 'obfuscation_map.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{"stale": true}');

        final result = runWithOverrides(releaser.assembleSupplementDirectory);

        expect(result, isNull);
        expect(
          File(p.join(supplementDir.path, 'obfuscation_map.json')).existsSync(),
          isFalse,
        );
        verify(
          () => logger.detail(
            any(that: contains('Removing stale obfuscation map')),
          ),
        ).called(1);
      });
    });

    group('uploadReleaseArtifacts', () {
      const appId = 'test-app-id';
      late Release release;
      late List<ReleaseArtifactUpload> artifacts;

      setUp(() {
        release = MockRelease();
        when(() => release.id).thenReturn(42);
        artifacts = [
          ReleaseArtifactUpload(
            file: File('artifact.zip'),
            name: 'bundle',
            arch: 'bundle',
            platform: ReleasePlatform.linux,
            canSideload: true,
          ),
        ];
        releaser.artifacts = artifacts;
        when(
          () => codePushClientWrapper.uploadReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            artifacts: any(named: 'artifacts'),
          ),
        ).thenAnswer((_) async {});
      });

      test('uploads the prepared artifacts to the release', () async {
        await runWithOverrides(
          () => releaser.uploadReleaseArtifacts(release: release, appId: appId),
        );

        verify(
          () => codePushClientWrapper.uploadReleaseArtifacts(
            appId: appId,
            releaseId: 42,
            artifacts: artifacts,
          ),
        ).called(1);
      });

      test('deletes the staging directory after uploading', () async {
        await runWithOverrides(
          () => releaser.uploadReleaseArtifacts(release: release, appId: appId),
        );

        expect(releaser.stagingDirectory, isNotNull);
        expect(releaser.stagingDirectory!.existsSync(), isFalse);
      });

      test('deletes the staging directory when preparing fails', () async {
        releaser.prepareError = Exception('oops');

        await expectLater(
          () => runWithOverrides(
            () =>
                releaser.uploadReleaseArtifacts(release: release, appId: appId),
          ),
          throwsA(isA<Exception>()),
        );

        expect(releaser.stagingDirectory!.existsSync(), isFalse);
        verifyNever(
          () => codePushClientWrapper.uploadReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            artifacts: any(named: 'artifacts'),
          ),
        );
      });

      test('deletes the staging directory when uploading fails', () async {
        when(
          () => codePushClientWrapper.uploadReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            artifacts: any(named: 'artifacts'),
          ),
        ).thenThrow(Exception('oops'));

        await expectLater(
          () => runWithOverrides(
            () =>
                releaser.uploadReleaseArtifacts(release: release, appId: appId),
          ),
          throwsA(isA<Exception>()),
        );

        expect(releaser.stagingDirectory!.existsSync(), isFalse);
      });
    });

    group('prepareSupplementArtifact', () {
      late Directory stagingDirectory;

      setUp(() {
        stagingDirectory = Directory.systemTemp.createTempSync();
      });

      test('returns null when there is no supplement', () async {
        when(
          () => artifactManager.getReleaseSupplementDirectory(
            platformSubdir: any(named: 'platformSubdir'),
            create: any(named: 'create'),
          ),
        ).thenReturn(null);

        final result = await runWithOverrides(
          () => releaser.prepareSupplementArtifact(
            stagingDirectory: stagingDirectory,
          ),
        );

        expect(result, isNull);
        verifyNever(
          () => codePushClientWrapper.prepareSupplementReleaseArtifact(
            platform: any(named: 'platform'),
            supplementDirectoryPath: any(named: 'supplementDirectoryPath'),
            arch: any(named: 'arch'),
            stagingDirectory: any(named: 'stagingDirectory'),
          ),
        );
      });

      test('prepares the supplement directory when there is one', () async {
        setObfuscate(enabled: true);
        File(obfuscationMapPath()).createSync(recursive: true);
        final supplementDir = Directory(
          p.join(projectRoot.path, 'build', 'test', 'shorebird'),
        )..createSync(recursive: true);
        when(
          () => artifactManager.getReleaseSupplementDirectory(
            platformSubdir: any(named: 'platformSubdir'),
            create: any(named: 'create'),
          ),
        ).thenReturn(supplementDir);
        final supplement = ReleaseArtifactUpload(
          file: File(p.join(stagingDirectory.path, 'test_supplement.zip')),
          name: 'supplement',
          arch: 'test_supplement',
          platform: ReleasePlatform.linux,
          canSideload: false,
        );
        when(
          () => codePushClientWrapper.prepareSupplementReleaseArtifact(
            platform: any(named: 'platform'),
            supplementDirectoryPath: any(named: 'supplementDirectoryPath'),
            arch: any(named: 'arch'),
            stagingDirectory: any(named: 'stagingDirectory'),
          ),
        ).thenAnswer((_) async => supplement);

        final result = await runWithOverrides(
          () => releaser.prepareSupplementArtifact(
            stagingDirectory: stagingDirectory,
          ),
        );

        expect(result, equals(supplement));
        verify(
          () => codePushClientWrapper.prepareSupplementReleaseArtifact(
            platform: ReleasePlatform.linux,
            supplementDirectoryPath: supplementDir.path,
            arch: 'test_supplement',
            stagingDirectory: stagingDirectory,
          ),
        ).called(1);
      });
    });

    group('uploadSupplementArtifact', () {
      late ReleaseArtifactUpload supplement;
      Directory? stagingDirectory;

      setUp(() {
        stagingDirectory = null;
        supplement = ReleaseArtifactUpload(
          file: File('test_supplement.zip'),
          name: 'supplement',
          arch: 'test_supplement',
          platform: ReleasePlatform.linux,
          canSideload: false,
        );
        when(
          () => codePushClientWrapper.prepareSupplementReleaseArtifact(
            platform: any(named: 'platform'),
            supplementDirectoryPath: any(named: 'supplementDirectoryPath'),
            arch: any(named: 'arch'),
            stagingDirectory: any(named: 'stagingDirectory'),
          ),
        ).thenAnswer((invocation) async {
          stagingDirectory =
              invocation.namedArguments[#stagingDirectory] as Directory;
          expect(stagingDirectory!.existsSync(), isTrue);
          return supplement;
        });
        when(
          () => codePushClientWrapper.uploadReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            artifacts: any(named: 'artifacts'),
            message: any(named: 'message'),
          ),
        ).thenAnswer((_) async {});
      });

      test('uploads nothing when there is no supplement', () async {
        when(
          () => artifactManager.getReleaseSupplementDirectory(
            platformSubdir: any(named: 'platformSubdir'),
            create: any(named: 'create'),
          ),
        ).thenReturn(null);

        await runWithOverrides(
          () => releaser.uploadSupplementArtifact(appId: 'app', releaseId: 1),
        );

        verifyNever(
          () => codePushClientWrapper.uploadReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            artifacts: any(named: 'artifacts'),
            message: any(named: 'message'),
          ),
        );
      });

      group('when there is a supplement', () {
        late Directory supplementDir;

        setUp(() {
          setObfuscate(enabled: true);
          File(obfuscationMapPath()).createSync(recursive: true);
          supplementDir = Directory(
            p.join(projectRoot.path, 'build', 'test', 'shorebird'),
          )..createSync(recursive: true);
          when(
            () => artifactManager.getReleaseSupplementDirectory(
              platformSubdir: any(named: 'platformSubdir'),
              create: any(named: 'create'),
            ),
          ).thenReturn(supplementDir);
        });

        test('uploads the prepared supplement', () async {
          await runWithOverrides(
            () => releaser.uploadSupplementArtifact(appId: 'app', releaseId: 1),
          );

          verify(
            () => codePushClientWrapper.prepareSupplementReleaseArtifact(
              platform: ReleasePlatform.linux,
              supplementDirectoryPath: supplementDir.path,
              arch: 'test_supplement',
              stagingDirectory: any(named: 'stagingDirectory'),
            ),
          ).called(1);
          verify(
            () => codePushClientWrapper.uploadReleaseArtifacts(
              appId: 'app',
              releaseId: 1,
              artifacts: [supplement],
              message: 'Uploading supplement artifacts',
            ),
          ).called(1);
          expect(stagingDirectory, isNotNull);
          expect(stagingDirectory!.existsSync(), isFalse);
        });

        test('deletes the staging directory when uploading fails', () async {
          when(
            () => codePushClientWrapper.uploadReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              artifacts: any(named: 'artifacts'),
              message: any(named: 'message'),
            ),
          ).thenThrow(Exception('oops'));

          await expectLater(
            () => runWithOverrides(
              () =>
                  releaser.uploadSupplementArtifact(appId: 'app', releaseId: 1),
            ),
            throwsA(isA<Exception>()),
          );

          expect(stagingDirectory!.existsSync(), isFalse);
        });
      });
    });
  });
}
