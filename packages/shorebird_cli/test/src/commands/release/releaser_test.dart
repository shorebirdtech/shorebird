import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
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

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {}
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
      registerFallbackValue(ReleasePlatform.linux);
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

    group('assertReleaseVersionProvided', () {
      test('returns normally when --release-version was provided', () {
        when(() => argResults['release-version']).thenReturn('1.0.0+1');

        expect(
          () => runWithOverrides(
            () =>
                releaser.assertReleaseVersionProvided(hostAppLabel: 'Android'),
          ),
          returnsNormally,
        );
        verifyNever(() => logger.err(any()));
      });

      test('logs error and exits with usage code when missing', () {
        when(() => argResults['release-version']).thenReturn(null);

        expect(
          () => runWithOverrides(
            () =>
                releaser.assertReleaseVersionProvided(hostAppLabel: 'Android'),
          ),
          exitsWithCode(ExitCode.usage),
        );
        verify(
          () => logger.err(
            '''
Missing required argument: --release-version

Pass the version of the Android app that embeds this module
(e.g. $releaseVersionExample).

Example:
  ${lightCyan.wrap('shorebird release linux --release-version=$releaseVersionExample')}''',
          ),
        ).called(1);
      });

      test('logs error and exits with usage code when empty', () {
        when(() => argResults['release-version']).thenReturn('');

        expect(
          () => runWithOverrides(
            () =>
                releaser.assertReleaseVersionProvided(hostAppLabel: 'Android'),
          ),
          exitsWithCode(ExitCode.usage),
        );
        verify(() => logger.err(any())).called(1);
      });

      test('logs error and exits with usage code for latest', () {
        when(() => argResults['release-version']).thenReturn('latest');

        expect(
          () => runWithOverrides(
            () =>
                releaser.assertReleaseVersionProvided(hostAppLabel: 'Android'),
          ),
          exitsWithCode(ExitCode.usage),
        );
        verify(() => logger.err(any())).called(1);
      });
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

    group('uploadSupplementArtifact', () {
      setUp(() {
        when(
          () => codePushClientWrapper.createSupplementReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            supplementDirectoryPath: any(named: 'supplementDirectoryPath'),
            arch: any(named: 'arch'),
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
          () => codePushClientWrapper.createSupplementReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            supplementDirectoryPath: any(named: 'supplementDirectoryPath'),
            arch: any(named: 'arch'),
          ),
        );
      });

      test('uploads the supplement directory when there is one', () async {
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

        await runWithOverrides(
          () => releaser.uploadSupplementArtifact(appId: 'app', releaseId: 1),
        );

        verify(
          () => codePushClientWrapper.createSupplementReleaseArtifact(
            appId: 'app',
            releaseId: 1,
            platform: ReleasePlatform.linux,
            supplementDirectoryPath: supplementDir.path,
            arch: 'test_supplement',
          ),
        ).called(1);
      });
    });
  });
}
