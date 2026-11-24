import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/build_flags.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/split_debug_info.dart';
import 'package:shorebird_cli/src/symbols/sbsymbols.dart';
import 'package:shorebird_cli/src/symbols/symbol_extractor.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
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

  Set<Arch>? testBuiltArchitectures;
  Map<Arch, String>? testDebugInfoFileNames = const {
    Arch.arm64: 'app.test-arm64.symbols',
    Arch.x86_64: 'app.test-x64.symbols',
  };

  @override
  ReleaseType get releaseType => ReleaseType.linux;

  @override
  String get artifactDisplayName => 'Test app';

  @override
  String get supplementPlatformSubdir => 'test';

  @override
  String get supplementArtifactArch => 'test_supplement';

  @override
  Map<Arch, String> get debugInfoFileNames =>
      testDebugInfoFileNames ?? super.debugInfoFileNames;

  @override
  Set<Arch> get builtArchitectures =>
      testBuiltArchitectures ?? super.builtArchitectures;

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
    const appId = 'test-app-id';
    const managedPem = 'managed-public-key-pem';
    const managedKeyBase64 = 'bWFuYWdlZA==';
    const signingKey = SigningKey(id: 7, publicKeyPem: managedPem);

    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late CodeSigner codeSigner;
    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdLogger logger;
    late SymbolExtractor symbolExtractor;
    late _TestReleaser releaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          codeSignerRef.overrideWith(() => codeSigner),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          symbolExtractorRef.overrideWith(() => symbolExtractor),
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
      registerFallbackValue(File(''));
      registerFallbackValue(SymbolImage.release);
      registerFallbackValue(SymbolsFormat.sbsymbols);
    });

    setUp(() {
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      codeSigner = MockCodeSigner();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      logger = MockShorebirdLogger();
      symbolExtractor = MockSymbolExtractor();

      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults['obfuscate']).thenReturn(false);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn('deadbeef');
      when(
        () => shorebirdEnv.getShorebirdYaml(),
      ).thenReturn(const ShorebirdYaml(appId: appId));
      when(
        () => codePushClientWrapper.getSigningKey(appId: any(named: 'appId')),
      ).thenAnswer((_) async => signingKey);
      when(
        () => codeSigner.base64PublicKeyFromPem(managedPem),
      ).thenReturn(managedKeyBase64);

      when(
        () => symbolExtractor.writeIndex(
          debugInfo: any(named: 'debugInfo'),
          output: any(named: 'output'),
          image: any(named: 'image'),
        ),
      ).thenAnswer((invocation) {
        final output = invocation.namedArguments[const Symbol('output')] as File
          ..createSync(recursive: true)
          ..writeAsStringSync('an index');
        return output;
      });

      releaser = _TestReleaser(argResults: argResults);
    });

    group('assertReleaseVersionFlagNotProvided', () {
      test('returns normally when --release-version is not passed', () {
        expect(
          () => runWithOverrides(releaser.assertReleaseVersionFlagNotProvided),
          returnsNormally,
        );
      });

      test(
        'exits with an error saying the flag is unsupported when passed',
        () {
          when(() => argResults.wasParsed('release-version')).thenReturn(true);

          expect(
            () =>
                runWithOverrides(releaser.assertReleaseVersionFlagNotProvided),
            exitsWithError(
              message:
                  '--release-version is only supported for aar and '
                  'ios-framework releases.',
              hint:
                  'Remove --release-version. This release takes its version '
                  'from your pubspec.yaml.',
            ),
          );
        },
      );
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

      group('when the user passes --save-obfuscation-map', () {
        const userArg =
            '--extra-gen-snapshot-options='
            '--save-obfuscation-map=build/map.json';

        setUp(() {
          when(() => argResults.rest).thenReturn([userArg]);
        });

        test('keeps theirs and reads the map from their path', () async {
          setObfuscate(enabled: true);
          stubPreStrip(preStrip: false);

          final buildArgs = [userArg];
          await runWithOverrides(
            () => releaser.addObfuscationMapArgs(buildArgs),
          );

          expect(buildArgs, equals([userArg]));
          expect(
            runWithOverrides(() => releaser.obfuscationMapPath),
            equals(p.join(projectRoot.path, 'build', 'map.json')),
          );
        });

        test('finds it among comma-separated options', () {
          // An absolute path in this platform's style.
          final absolutePath = p.join(Directory.systemTemp.path, 'b.json');
          when(() => argResults.rest).thenReturn([
            '--extra-gen-snapshot-options=--foo,--save-obfuscation-map=a.json',
            '--extra-gen-snapshot-options',
            '--save-obfuscation-map=$absolutePath',
          ]);
          expect(
            runWithOverrides(() => releaser.userObfuscationMapPath),
            equals(absolutePath),
          );
          expect(
            runWithOverrides(() => releaser.obfuscationMapPath),
            equals(p.normalize(absolutePath)),
          );
        });

        test('verifies the map at their path', () {
          setObfuscate(enabled: true);
          File(
            p.join(projectRoot.path, 'build', 'map.json'),
          ).createSync(recursive: true);

          runWithOverrides(releaser.verifyObfuscationMap);
        });
      });
    });

    group('resolvePatchSigningKey', () {
      test('embeds the managed key by default', () async {
        when(
          () => argResults[CommonArguments.patchSigningArg.name],
        ).thenReturn(true);

        final key = await runWithOverrides(releaser.resolvePatchSigningKey);

        expect(key, equals(managedKeyBase64));
        expect(
          releaser.signing,
          equals(
            const ArtifactSigningRequest(
              mode: ReleaseSigningMode.managed,
              keyId: 7,
            ),
          ),
        );
        verify(
          () => codePushClientWrapper.getSigningKey(appId: appId),
        ).called(1);
      });

      test('says how to release without a key when the fetch fails', () async {
        when(
          () => argResults[CommonArguments.patchSigningArg.name],
        ).thenReturn(true);
        when(
          () => codePushClientWrapper.getSigningKey(appId: appId),
        ).thenThrow(ProcessExit(ExitCode.software.code));

        await expectLater(
          runWithOverrides(releaser.resolvePatchSigningKey),
          throwsA(isA<ProcessExit>()),
        );
        verify(
          () => logger.info(
            'Releases embed a Shorebird-managed patch signing key by '
            'default. To release without one (patches will be unsigned), '
            'pass --no-patch-signing.',
          ),
        ).called(1);
      });

      test('embeds no key with --no-patch-signing', () async {
        when(
          () => argResults[CommonArguments.patchSigningArg.name],
        ).thenReturn(false);
        final key = await runWithOverrides(releaser.resolvePatchSigningKey);

        expect(key, isNull);
        expect(
          releaser.signing,
          equals(
            const ArtifactSigningRequest(mode: ReleaseSigningMode.unsigned),
          ),
        );
        verifyNever(
          () => codePushClientWrapper.getSigningKey(appId: any(named: 'appId')),
        );
      });

      test('embeds the customer key from --public-key-path', () async {
        final publicKeyFile = File(p.join(projectRoot.path, 'public.pem'))
          ..writeAsStringSync('customer-pem');
        when(
          () => argResults[CommonArguments.publicKeyArg.name],
        ).thenReturn(publicKeyFile.path);
        when(
          () => codeSigner.canonicalPublicKeyPem('customer-pem'),
        ).thenReturn('customer-pem');
        when(
          () => codeSigner.base64PublicKeyFromPem('customer-pem'),
        ).thenReturn('Y3VzdG9tZXI=');

        final key = await runWithOverrides(releaser.resolvePatchSigningKey);

        expect(key, equals('Y3VzdG9tZXI='));
        expect(
          releaser.signing,
          equals(
            const ArtifactSigningRequest(mode: ReleaseSigningMode.customer),
          ),
        );
        verifyNever(
          () => codePushClientWrapper.getSigningKey(appId: any(named: 'appId')),
        );
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

      test('exits with an error when the map was not generated', () {
        setObfuscate(enabled: true);

        expect(
          () => runWithOverrides(releaser.verifyObfuscationMap),
          exitsWithError(
            message: contains(
              'Obfuscation was enabled but the obfuscation map was not',
            ),
            hint: 'Re-run with --verbose to see the build output.',
            exitCode: ExitCode.software,
          ),
        );
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

      test('returns null when there is no project', () {
        supplementDir.deleteSync(recursive: true);
        when(
          () => artifactManager.getReleaseSupplementDirectory(
            platformSubdir: any(named: 'platformSubdir'),
            create: any(named: 'create'),
          ),
        ).thenReturn(null);

        final result = runWithOverrides(releaser.assembleSupplementDirectory);

        expect(result, isNull);
      });

      test('records the build flags as hashes', () {
        when(() => argResults.wasParsed('dart-define')).thenReturn(true);
        when(() => argResults['dart-define']).thenReturn(['API_KEY=secret']);

        final result = runWithOverrides(releaser.assembleSupplementDirectory);

        final recorded = File(
          p.join(result!.path, 'build_flags.json'),
        ).readAsStringSync();
        expect(recorded, isNot(contains('secret')));
        expect(
          BuildFlags.fromJson(
            json.decode(recorded) as Map<String, dynamic>,
          ).dartDefines.keys,
          equals(['API_KEY']),
        );
      });

      test(
        "extracts each architecture's symbol index when crash reporting is on",
        () {
          releaser.crashReportingEnabled = true;
          setObfuscate(enabled: true);
          final debugInfo =
              File(
                  p.join(
                    projectRoot.path,
                    defaultSplitDebugInfoPath,
                    'app.test-arm64.symbols',
                  ),
                )
                ..createSync(recursive: true)
                ..writeAsStringSync('debug info');

          runWithOverrides(releaser.assembleSupplementDirectory);

          verify(
            () => symbolExtractor.writeIndex(
              debugInfo: any(
                named: 'debugInfo',
                that: isA<File>().having((f) => f.path, 'path', debugInfo.path),
              ),
              output: any(named: 'output'),
              image: SymbolImage.release,
            ),
          ).called(1);
        },
      );

      test('skips symbol extraction when crash reporting is off', () {
        setObfuscate(enabled: true);
        File(
            p.join(
              projectRoot.path,
              defaultSplitDebugInfoPath,
              'app.test-arm64.symbols',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('debug info');

        runWithOverrides(releaser.assembleSupplementDirectory);

        verifyNever(
          () => symbolExtractor.writeIndex(
            debugInfo: any(named: 'debugInfo'),
            output: any(named: 'output'),
            image: any(named: 'image'),
          ),
        );
      });

      test('removes a stale obfuscation map', () {
        File(p.join(supplementDir.path, 'obfuscation_map.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{"stale": true}');

        runWithOverrides(releaser.assembleSupplementDirectory);

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

    group('splitDebugInfoPath', () {
      test('is null when the build writes no symbols', () {
        expect(runWithOverrides(() => releaser.splitDebugInfoPath), isNull);
      });

      test("is Shorebird's default for an obfuscated release", () {
        setObfuscate(enabled: true);

        expect(
          runWithOverrides(() => releaser.splitDebugInfoPath),
          equals(defaultSplitDebugInfoPath),
        );
      });

      test('is the directory the user passed', () {
        when(() => argResults.wasParsed('split-debug-info')).thenReturn(true);
        when(() => argResults['split-debug-info']).thenReturn('my/symbols');

        expect(
          runWithOverrides(() => releaser.splitDebugInfoPath),
          equals('my/symbols'),
        );
      });
    });

    group('debugInfoFiles', () {
      setUp(() => setObfuscate(enabled: true));

      File debugInfo(String name) =>
          File(p.join(projectRoot.path, defaultSplitDebugInfoPath, name));

      test('is empty when the build wrote no symbols', () {
        setObfuscate(enabled: false);

        expect(runWithOverrides(() => releaser.debugInfoFiles), isEmpty);
      });

      test('defaults debugInfoFileNames to empty and skips unnamed archs', () {
        releaser
          ..testDebugInfoFileNames = null
          ..testBuiltArchitectures = const {Arch.arm64};

        expect(releaser.debugInfoFileNames, isEmpty);
        expect(runWithOverrides(() => releaser.debugInfoFiles), isEmpty);
      });

      test('holds only the architectures the build produced', () {
        debugInfo('app.test-arm64.symbols')
          ..createSync(recursive: true)
          ..writeAsStringSync('arm64 debug info');
        debugInfo('app.test-x64.symbols')
          ..createSync(recursive: true)
          ..writeAsStringSync('stale x64 debug info from an earlier build');
        releaser.testBuiltArchitectures = const {Arch.arm64};

        final files = runWithOverrides(() => releaser.debugInfoFiles);

        expect(files.keys, equals([Arch.arm64]));
        expect(
          files[Arch.arm64]!.path,
          equals(debugInfo('app.test-arm64.symbols').path),
        );
      });
    });

    group('extractSymbolIndexes', () {
      setUp(() {
        releaser.crashReportingEnabled = true;
        setObfuscate(enabled: true);
      });

      File debugInfo(String name) =>
          File(p.join(projectRoot.path, defaultSplitDebugInfoPath, name))
            ..createSync(recursive: true)
            ..writeAsStringSync('debug info');

      test("writes an index beside each architecture's debug info", () {
        final arm64 = debugInfo('app.test-arm64.symbols');
        final x64 = debugInfo('app.test-x64.symbols');

        runWithOverrides(releaser.extractSymbolIndexes);

        for (final file in [arm64, x64]) {
          verify(
            () => symbolExtractor.writeIndex(
              debugInfo: any(
                named: 'debugInfo',
                that: isA<File>().having((f) => f.path, 'path', file.path),
              ),
              output: any(
                named: 'output',
                that: isA<File>().having(
                  (f) => f.path,
                  'path',
                  p.setExtension(file.path, '.sbsymbols'),
                ),
              ),
              image: SymbolImage.release,
            ),
          ).called(1);
        }
      });

      test('extracts nothing when crash reporting is off', () {
        releaser.crashReportingEnabled = false;
        debugInfo('app.test-arm64.symbols');

        runWithOverrides(releaser.extractSymbolIndexes);

        verifyNever(
          () => symbolExtractor.writeIndex(
            debugInfo: any(named: 'debugInfo'),
            output: any(named: 'output'),
            image: any(named: 'image'),
          ),
        );
      });

      test('says so at --verbose when there is no index to extract', () {
        debugInfo('app.test-arm64.symbols');
        when(
          () => symbolExtractor.writeIndex(
            debugInfo: any(named: 'debugInfo'),
            output: any(named: 'output'),
            image: any(named: 'image'),
          ),
        ).thenReturn(null);

        runWithOverrides(releaser.extractSymbolIndexes);

        verify(
          () => logger.detail(
            any(that: contains('No symbol index extracted from')),
          ),
        ).called(1);
      });
    });

    group('uploadSymbolArtifacts', () {
      const releaseId = 42;

      setUp(() {
        releaser.crashReportingEnabled = true;
        setObfuscate(enabled: true);
        when(
          () => codePushClientWrapper.createReleaseSymbols(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            arch: any(named: 'arch'),
            format: any(named: 'format'),
            symbols: any(named: 'symbols'),
          ),
        ).thenAnswer((_) async {});
      });

      File debugInfo(String name) =>
          File(p.join(projectRoot.path, defaultSplitDebugInfoPath, name))
            ..createSync(recursive: true)
            ..writeAsStringSync('debug info');

      test('uploads each extracted SBSY v1 index without raw DWARF', () async {
        final arm64 = debugInfo('app.test-arm64.symbols');
        runWithOverrides(releaser.extractSymbolIndexes);

        await runWithOverrides(
          () => releaser.uploadSymbolArtifacts(
            appId: appId,
            releaseId: releaseId,
          ),
        );

        verify(
          () => codePushClientWrapper.createReleaseSymbols(
            appId: appId,
            releaseId: releaseId,
            platform: ReleasePlatform.linux,
            arch: 'aarch64',
            format: SymbolsFormat.sbsymbols,
            symbols: any(
              named: 'symbols',
              that: isA<File>().having(
                (f) => f.path,
                'path',
                p.setExtension(arm64.path, '.sbsymbols'),
              ),
            ),
          ),
        ).called(1);
      });

      test('uploads nothing when crash reporting is off', () async {
        debugInfo('app.test-arm64.symbols');
        runWithOverrides(releaser.extractSymbolIndexes);
        releaser.crashReportingEnabled = false;

        await runWithOverrides(
          () => releaser.uploadSymbolArtifacts(
            appId: appId,
            releaseId: releaseId,
          ),
        );

        verifyNever(
          () => codePushClientWrapper.createReleaseSymbols(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            arch: any(named: 'arch'),
            format: any(named: 'format'),
            symbols: any(named: 'symbols'),
          ),
        );
      });

      test('uploads nothing when no index was extracted', () async {
        debugInfo('app.test-arm64.symbols');

        await runWithOverrides(
          () => releaser.uploadSymbolArtifacts(
            appId: appId,
            releaseId: releaseId,
          ),
        );

        verifyNever(
          () => codePushClientWrapper.createReleaseSymbols(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            arch: any(named: 'arch'),
            format: any(named: 'format'),
            symbols: any(named: 'symbols'),
          ),
        );
      });

      test(
        "uploads nothing when the index on disk is a previous build's",
        () async {
          final arm64 = debugInfo('app.test-arm64.symbols');
          File(p.setExtension(arm64.path, '.sbsymbols'))
            ..createSync(recursive: true)
            ..writeAsStringSync('an index from an earlier build');
          when(
            () => symbolExtractor.writeIndex(
              debugInfo: any(named: 'debugInfo'),
              output: any(named: 'output'),
              image: any(named: 'image'),
            ),
          ).thenReturn(null);
          runWithOverrides(releaser.extractSymbolIndexes);

          await runWithOverrides(
            () => releaser.uploadSymbolArtifacts(
              appId: appId,
              releaseId: releaseId,
            ),
          );

          verifyNever(
            () => codePushClientWrapper.createReleaseSymbols(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              platform: any(named: 'platform'),
              arch: any(named: 'arch'),
              format: any(named: 'format'),
              symbols: any(named: 'symbols'),
            ),
          );
        },
      );

      test('uploads nothing when the build wrote no symbols', () async {
        setObfuscate(enabled: false);

        await runWithOverrides(
          () => releaser.uploadSymbolArtifacts(
            appId: appId,
            releaseId: releaseId,
          ),
        );

        verifyNever(
          () => codePushClientWrapper.createReleaseSymbols(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            arch: any(named: 'arch'),
            format: any(named: 'format'),
            symbols: any(named: 'symbols'),
          ),
        );
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
            signing: any(named: 'signing'),
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
        const signing = ArtifactSigningRequest(
          mode: ReleaseSigningMode.managed,
          keyId: 7,
        );
        releaser.signing = signing;

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
            signing: signing,
          ),
        ).called(1);
      });
    });
  });
}
