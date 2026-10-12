import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/apple_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

/// A patcher that uses the real [ApplePatcherMixin] and
/// [AppleLinkerPatcherMixin], so the shared Apple link step can be tested
/// without either real platform. Members the link step doesn't use throw.
class _TestApplePatcher extends Patcher
    with ApplePatcherMixin, AppleLinkerPatcherMixin {
  _TestApplePatcher({required super.argParser, required super.argResults})
    : super(flavor: null, target: null);

  @override
  List<Validator> get applePlatformValidators => const [];

  @override
  String get primaryReleaseArtifactArch => 'test';

  @override
  ReleaseType get releaseType => ReleaseType.ios;

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) => throw UnimplementedError();

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) =>
      throw UnimplementedError();

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
  }) => throw UnimplementedError();

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) =>
      throw UnimplementedError();
}

void main() {
  useTempWorkingDirectory();
  group(AppleLinkerPatcherMixin, () {
    const postLinkerFlutterRevision = // cspell: disable-next-line
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
    const preLinkerFlutterRevision = // cspell: disable-next-line
        '83305b5088e6fe327fb3334a73ff190828d85713';
    const linkPercentage = 95.0;
    const analyzeSnapshotPath = 'path/to/analyze_snapshot';
    const diffPath = 'path/to/diff';

    late AotTools aotTools;
    late Apple apple;
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late CodeSigner codeSigner;
    late EngineConfig engineConfig;
    late ShorebirdLogger logger;
    late Progress progress;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdEnv shorebirdEnv;
    late Directory buildDirectory;
    late Directory patchSupplementDirectory;
    late Directory releaseSupplementDirectory;
    late File releaseArtifactFile;
    late _TestApplePatcher patcher;
    TestNativePlatform? testPlatform;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          aotToolsRef.overrideWith(() => aotTools),
          appleRef.overrideWith(() => apple),
          artifactManagerRef.overrideWith(() => artifactManager),
          codeSignerRef.overrideWith(() => codeSigner),
          engineConfigRef.overrideWith(() => engineConfig),
          loggerRef.overrideWith(() => logger),
          if (testPlatform != null)
            platformRef.overrideWith(() => testPlatform!),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    Future<Map<Arch, PatchArtifactBundle>> linkAndBundle({
      String? podfileLockHash,
    }) => runWithOverrides(
      () => patcher.linkAndBundlePatch(
        releaseArtifactFile: releaseArtifactFile,
        releaseSupplementDir: releaseSupplementDirectory,
        podfileLockHash: podfileLockHash,
      ),
    );

    void stubLinkResult(LinkResult result) {
      when(
        () => apple.runLinker(
          kernelFile: any(named: 'kernelFile'),
          releaseArtifact: any(named: 'releaseArtifact'),
          splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
          aotOutputFile: any(named: 'aotOutputFile'),
          vmCodeFile: any(named: 'vmCodeFile'),
          ddMaxBytes: any(named: 'ddMaxBytes'),
        ),
      ).thenAnswer((_) async => result);
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
    });

    setUp(() {
      testPlatform = null;
      aotTools = MockAotTools();
      apple = MockApple();
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      codeSigner = MockCodeSigner();
      engineConfig = MockEngineConfig();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();

      final projectRoot = Directory.systemTemp.createTempSync();
      addTearDown(() => projectRoot.deleteSync(recursive: true));
      buildDirectory = Directory(p.join(projectRoot.path, 'build'))
        ..createSync();
      patchSupplementDirectory = Directory(
        p.join(buildDirectory.path, 'ios', 'shorebird'),
      );
      releaseSupplementDirectory = Directory(
        p.join(projectRoot.path, 'release_supplement'),
      )..createSync();
      releaseArtifactFile = File(
        p.join(projectRoot.path, 'release', 'App.framework', 'App'),
      )..createSync(recursive: true);
      File(p.join(buildDirectory.path, 'out.aot')).writeAsStringSync('aot');
      File(
        p.join(buildDirectory.path, 'out.vmcode'),
      ).writeAsStringSync('vmcode');

      when(() => argParser.options).thenReturn({});
      when(() => argResults.options).thenReturn([]);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

      when(() => engineConfig.localEngine).thenReturn(null);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => shorebirdEnv.buildDirectory).thenReturn(buildDirectory);
      when(
        () => shorebirdEnv.iosSupplementDirectory,
      ).thenReturn(patchSupplementDirectory);
      when(
        () => shorebirdEnv.flutterRevision,
      ).thenReturn(postLinkerFlutterRevision);
      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.analyzeSnapshotIos,
        ),
      ).thenReturn(analyzeSnapshotPath);
      when(
        aotTools.isGeneratePatchDiffBaseSupported,
      ).thenAnswer((_) async => false);
      stubLinkResult(const LinkResult.success(linkPercentage: linkPercentage));

      patcher = _TestApplePatcher(argParser: argParser, argResults: argResults);
    });

    group('linkPercentage', () {
      test('is null before linking', () {
        expect(patcher.linkPercentage, isNull);
        expect(patcher.linkMetadata, isNull);
      });

      test('is the last build link percentage', () {
        patcher.lastBuildLinkPercentage = 42.1337;
        expect(patcher.linkPercentage, equals(42.1337));
      });
    });

    group('linkAndBundlePatch', () {
      group('when the linker is used', () {
        test('copies the supplement files to the snapshot dirs', () async {
          await linkAndBundle();

          Matcher hasPath(String path) =>
              isA<Directory>().having((d) => d.path, 'path', path);
          verify(
            () => apple.copySupplementFilesToSnapshotDirs(
              releaseSupplementDir: any(
                named: 'releaseSupplementDir',
                that: hasPath(releaseSupplementDirectory.path),
              ),
              releaseSnapshotDir: any(
                named: 'releaseSnapshotDir',
                that: hasPath(releaseArtifactFile.parent.path),
              ),
              patchSupplementDir: any(
                named: 'patchSupplementDir',
                that: hasPath(patchSupplementDirectory.path),
              ),
              patchSnapshotDir: any(
                named: 'patchSnapshotDir',
                that: hasPath(buildDirectory.path),
              ),
            ),
          ).called(1);
        });

        test('links the patch against the release', () async {
          await linkAndBundle();

          verify(
            () => apple.runLinker(
              kernelFile: any(
                named: 'kernelFile',
                that: isA<File>().having(
                  (f) => f.path,
                  'path',
                  p.join(buildDirectory.path, 'app.dill'),
                ),
              ),
              releaseArtifact: releaseArtifactFile,
              splitDebugInfoArgs: [],
              aotOutputFile: any(
                named: 'aotOutputFile',
                that: isA<File>().having(
                  (f) => f.path,
                  'path',
                  p.join(buildDirectory.path, 'out.aot'),
                ),
              ),
              vmCodeFile: any(
                named: 'vmCodeFile',
                that: isA<File>().having(
                  (f) => f.path,
                  'path',
                  p.join(buildDirectory.path, 'out.vmcode'),
                ),
              ),
            ),
          ).called(1);
        });

        test(
          'passes the obfuscation gen_snapshot args to the linker',
          () async {
            final obfuscationMapPath = p.join(
              buildDirectory.path,
              'obfuscation_map.json',
            );
            patcher
              ..obfuscate = true
              ..obfuscationMapPath = obfuscationMapPath;

            await linkAndBundle();

            final args =
                verify(
                      () => apple.runLinker(
                        kernelFile: any(named: 'kernelFile'),
                        releaseArtifact: any(named: 'releaseArtifact'),
                        splitDebugInfoArgs: captureAny(
                          named: 'splitDebugInfoArgs',
                        ),
                        aotOutputFile: any(named: 'aotOutputFile'),
                        vmCodeFile: any(named: 'vmCodeFile'),
                      ),
                    ).captured.single
                    as List<String>;
            expect(args, contains('--obfuscate'));
            expect(
              args,
              contains('--load-obfuscation-map=$obfuscationMapPath'),
            );
          },
        );

        test('passes no ddMaxBytes to the linker by default', () async {
          await linkAndBundle();

          final captured = verify(
            () => apple.runLinker(
              kernelFile: any(named: 'kernelFile'),
              releaseArtifact: any(named: 'releaseArtifact'),
              splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
              aotOutputFile: any(named: 'aotOutputFile'),
              vmCodeFile: any(named: 'vmCodeFile'),
              ddMaxBytes: captureAny(named: 'ddMaxBytes'),
            ),
          ).captured;
          expect(captured, equals([null]));
        });

        test(
          'passes SHOREBIRD_PATCH_DD_MAX_BYTES to the linker when set',
          () async {
            testPlatform = TestNativePlatform(
              environment: {'SHOREBIRD_PATCH_DD_MAX_BYTES': '4096'},
            );

            await linkAndBundle();

            verify(
              () => apple.runLinker(
                kernelFile: any(named: 'kernelFile'),
                releaseArtifact: any(named: 'releaseArtifact'),
                splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
                aotOutputFile: any(named: 'aotOutputFile'),
                vmCodeFile: any(named: 'vmCodeFile'),
                ddMaxBytes: 4096,
              ),
            ).called(1);
          },
        );

        test('passes --dd-max-bytes to the linker', () async {
          when(
            () => argResults[CommonArguments.ddMaxBytesArg.name],
          ).thenReturn('0');

          await linkAndBundle();

          verify(
            () => apple.runLinker(
              kernelFile: any(named: 'kernelFile'),
              releaseArtifact: any(named: 'releaseArtifact'),
              splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
              aotOutputFile: any(named: 'aotOutputFile'),
              vmCodeFile: any(named: 'vmCodeFile'),
              ddMaxBytes: 0,
            ),
          ).called(1);
        });

        test(
          'prefers --dd-max-bytes over SHOREBIRD_PATCH_DD_MAX_BYTES',
          () async {
            testPlatform = TestNativePlatform(
              environment: {'SHOREBIRD_PATCH_DD_MAX_BYTES': '4096'},
            );
            when(
              () => argResults[CommonArguments.ddMaxBytesArg.name],
            ).thenReturn('8192');

            await linkAndBundle();

            verify(
              () => apple.runLinker(
                kernelFile: any(named: 'kernelFile'),
                releaseArtifact: any(named: 'releaseArtifact'),
                splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
                aotOutputFile: any(named: 'aotOutputFile'),
                vmCodeFile: any(named: 'vmCodeFile'),
                ddMaxBytes: 8192,
              ),
            ).called(1);
          },
        );

        test('records the link percentage and metadata', () async {
          const linkMetadata = {'link': 'metadata'};
          stubLinkResult(
            const LinkResult.success(
              linkPercentage: linkPercentage,
              linkMetadata: linkMetadata,
            ),
          );

          await linkAndBundle();

          expect(patcher.linkPercentage, equals(linkPercentage));
          expect(patcher.linkMetadata, equals(linkMetadata));
          verifyNever(() => logger.warn(any()));
        });

        test('warns when the link percentage is low', () async {
          stubLinkResult(const LinkResult.success(linkPercentage: 50));

          await linkAndBundle();

          verify(
            () => logger.warn(Patcher.lowLinkPercentageWarning(50)),
          ).called(1);
        });

        test('exits with the linker exit code when linking fails', () async {
          stubLinkResult(const LinkResult.failure());

          await expectLater(linkAndBundle, exitsWithCode(ExitCode.software));
          expect(patcher.linkPercentage, isNull);
        });

        group('when generating a patch diff base is supported', () {
          late File diffBaseFile;

          setUp(() {
            when(
              aotTools.isGeneratePatchDiffBaseSupported,
            ).thenAnswer((_) async => true);
            when(
              () => aotTools.generatePatchDiffBase(
                analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
                releaseSnapshot: any(named: 'releaseSnapshot'),
                outputDirectory: any(named: 'outputDirectory'),
              ),
            ).thenAnswer((invocation) async {
              final outputDirectory =
                  invocation.namedArguments[#outputDirectory] as Directory;
              return diffBaseFile = File(
                p.join(outputDirectory.path, 'diff_base'),
              )..writeAsStringSync('base');
            });
            when(
              () => artifactManager.createDiff(
                releaseArtifactPath: any(named: 'releaseArtifactPath'),
                patchArtifactPath: any(named: 'patchArtifactPath'),
              ),
            ).thenAnswer((_) async => diffPath);
          });

          test('diffs the linked patch against the diff base', () async {
            final bundles = await linkAndBundle();

            verify(
              () => aotTools.generatePatchDiffBase(
                analyzeSnapshotPath: analyzeSnapshotPath,
                releaseSnapshot: releaseArtifactFile,
                outputDirectory: any(named: 'outputDirectory'),
              ),
            ).called(1);
            verify(
              () => artifactManager.createDiff(
                releaseArtifactPath: diffBaseFile.path,
                patchArtifactPath: p.join(buildDirectory.path, 'out.vmcode'),
              ),
            ).called(1);
            verify(progress.complete).called(1);
            expect(bundles[Arch.arm64]!.path, equals(File(diffPath).path));
          });

          test('deletes the diff base directory after diffing', () async {
            await linkAndBundle();

            expect(diffBaseFile.parent.existsSync(), isFalse);
          });

          group('when generating the diff base fails', () {
            setUp(() {
              when(
                () => aotTools.generatePatchDiffBase(
                  analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
                  releaseSnapshot: any(named: 'releaseSnapshot'),
                  outputDirectory: any(named: 'outputDirectory'),
                ),
              ).thenThrow(Exception('oops'));
            });

            test('fails progress and exits with code 70', () async {
              await expectLater(
                linkAndBundle,
                exitsWithCode(ExitCode.software),
              );

              verify(() => progress.fail('Exception: oops')).called(1);
              verifyNever(
                () => artifactManager.createDiff(
                  releaseArtifactPath: any(named: 'releaseArtifactPath'),
                  patchArtifactPath: any(named: 'patchArtifactPath'),
                ),
              );
            });

            test('deletes the diff base directory', () async {
              await expectLater(
                linkAndBundle,
                exitsWithCode(ExitCode.software),
              );

              final outputDirectory =
                  verify(
                        () => aotTools.generatePatchDiffBase(
                          analyzeSnapshotPath: any(
                            named: 'analyzeSnapshotPath',
                          ),
                          releaseSnapshot: any(named: 'releaseSnapshot'),
                          outputDirectory: captureAny(named: 'outputDirectory'),
                        ),
                      ).captured.single
                      as Directory;
              expect(outputDirectory.existsSync(), isFalse);
            });
          });
        });

        group('when generating a patch diff base is not supported', () {
          test('uses the linked vmcode as the patch', () async {
            final bundles = await linkAndBundle();

            expect(
              bundles[Arch.arm64]!.path,
              equals(p.join(buildDirectory.path, 'out.vmcode')),
            );
            verifyNever(
              () => artifactManager.createDiff(
                releaseArtifactPath: any(named: 'releaseArtifactPath'),
                patchArtifactPath: any(named: 'patchArtifactPath'),
              ),
            );
          });
        });
      });

      group('when the linker is not used', () {
        setUp(() {
          when(
            () => shorebirdEnv.flutterRevision,
          ).thenReturn(preLinkerFlutterRevision);
          // Even if supported, a diff base is only generated when linking.
          when(
            aotTools.isGeneratePatchDiffBaseSupported,
          ).thenAnswer((_) async => true);
        });

        test('uses the AOT snapshot as the patch without linking', () async {
          final bundles = await linkAndBundle();

          expect(
            bundles[Arch.arm64]!.path,
            equals(p.join(buildDirectory.path, 'out.aot')),
          );
          verifyNever(
            () => apple.copySupplementFilesToSnapshotDirs(
              releaseSupplementDir: any(named: 'releaseSupplementDir'),
              releaseSnapshotDir: any(named: 'releaseSnapshotDir'),
              patchSupplementDir: any(named: 'patchSupplementDir'),
              patchSnapshotDir: any(named: 'patchSnapshotDir'),
            ),
          );
          verifyNever(
            () => apple.runLinker(
              kernelFile: any(named: 'kernelFile'),
              releaseArtifact: any(named: 'releaseArtifact'),
              splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
              aotOutputFile: any(named: 'aotOutputFile'),
              vmCodeFile: any(named: 'vmCodeFile'),
              ddMaxBytes: any(named: 'ddMaxBytes'),
            ),
          );
          verifyNever(
            () => aotTools.generatePatchDiffBase(
              analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
              releaseSnapshot: any(named: 'releaseSnapshot'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          );
          expect(patcher.linkPercentage, isNull);
        });
      });

      group('the returned bundle', () {
        test('describes the arm64 patch', () async {
          final bundles = await linkAndBundle();

          expect(bundles.keys, equals([Arch.arm64]));
          final bundle = bundles[Arch.arm64]!;
          expect(bundle.arch, equals('aarch64'));
          expect(
            bundle.hash,
            equals(sha256.convert('vmcode'.codeUnits).toString()),
          );
          expect(bundle.size, equals('vmcode'.length));
          expect(bundle.hashSignature, isNull);
          expect(bundle.podfileLockHash, isNull);
        });

        test('carries the given podfile lock hash', () async {
          final bundles = await linkAndBundle(
            podfileLockHash: 'podfile-lock-hash',
          );

          expect(
            bundles[Arch.arm64]!.podfileLockHash,
            equals('podfile-lock-hash'),
          );
        });

        test('is signed when a signing key is configured', () async {
          final keyDirectory = Directory.systemTemp.createTempSync();
          addTearDown(() => keyDirectory.deleteSync(recursive: true));
          final privateKey = File(p.join(keyDirectory.path, 'private.pem'))
            ..createSync();
          final publicKey = File(p.join(keyDirectory.path, 'public.pem'))
            ..writeAsStringSync('public-key-pem');
          when(
            () => argResults[CommonArguments.privateKeyArg.name],
          ).thenReturn(privateKey.path);
          when(
            () => argResults[CommonArguments.publicKeyArg.name],
          ).thenReturn(publicKey.path);
          when(
            () => codeSigner.sign(
              message: any(named: 'message'),
              privateKeyPemFile: any(named: 'privateKeyPemFile'),
            ),
          ).thenAnswer(
            (invocation) =>
                '${invocation.namedArguments[#message] as String}-signature',
          );
          when(
            () => codeSigner.verify(
              message: any(named: 'message'),
              signature: any(named: 'signature'),
              publicKeyPem: any(named: 'publicKeyPem'),
            ),
          ).thenReturn(true);

          final bundles = await linkAndBundle();

          expect(
            bundles[Arch.arm64]!.hashSignature,
            equals('${sha256.convert('vmcode'.codeUnits)}-signature'),
          );
        });
      });
    });
  });
}
