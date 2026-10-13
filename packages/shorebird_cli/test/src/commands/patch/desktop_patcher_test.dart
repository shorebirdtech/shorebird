import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/linux_bundle_differ.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

/// A [DesktopPatcher] whose platform-specific parts are test doubles, so the
/// shared behavior can be tested without either real platform.
class _TestDesktopPatcher extends DesktopPatcher {
  _TestDesktopPatcher({
    required super.argParser,
    required super.argResults,
    required this.appDirectory,
    required this.builtDirectory,
    required this.validators,
    super.target,
  }) : super(flavor: null);

  @override
  final Directory appDirectory;

  /// What [buildApp] returns. Deliberately not [appDirectory], so tests can
  /// tell which one the patch archive is made from.
  final Directory builtDirectory;

  final List<Validator> validators;

  Exception? buildError;
  List<String>? builtWithArgs;
  String? builtWithPublicKey;
  Directory? versionReadFrom;

  @override
  List<Validator> get commandValidators => validators;

  @override
  String get hostOperatingSystem => 'test-os';

  @override
  LinuxBundleDiffer get archiveDiffer => const LinuxBundleDiffer();

  @override
  List<String> get dartLibraryPathSegments => const ['lib', 'app.so'];

  @override
  Future<Directory> buildApp({
    required List<String> args,
    String? base64PublicKey,
  }) async {
    if (buildError != null) throw buildError!;
    builtWithArgs = args;
    builtWithPublicKey = base64PublicKey;
    return builtDirectory;
  }

  @override
  Future<String> versionFromAppDirectory(Directory appDirectory) async {
    versionReadFrom = appDirectory;
    return '1.2.3';
  }

  @override
  String get primaryReleaseArtifactArch => 'test';

  @override
  ReleaseType get releaseType => ReleaseType.linux;
}

void main() {
  useTempWorkingDirectory();
  group(DesktopPatcher, () {
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late CodeSigner codeSigner;
    late Directory appDirectory;
    late Directory builtDirectory;
    late ShorebirdLogger logger;
    late PatchDiffChecker patchDiffChecker;
    late Progress progress;
    late ShorebirdValidator shorebirdValidator;
    late Validator validator;
    late _TestDesktopPatcher patcher;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactManagerRef.overrideWith(() => artifactManager),
          codeSignerRef.overrideWith(() => codeSigner),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(const LinuxBundleDiffer());
    });

    setUp(() {
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      codeSigner = MockCodeSigner();
      logger = MockShorebirdLogger();
      patchDiffChecker = MockPatchDiffChecker();
      progress = MockProgress();
      shorebirdValidator = MockShorebirdValidator();
      validator = MockValidator();
      appDirectory = Directory.systemTemp.createTempSync();
      builtDirectory = Directory.systemTemp.createTempSync();

      when(() => argParser.options).thenReturn({});
      when(() => argResults.options).thenReturn([]);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => logger.progress(any())).thenReturn(progress);

      patcher = _TestDesktopPatcher(
        argParser: argParser,
        argResults: argResults,
        appDirectory: appDirectory,
        builtDirectory: builtDirectory,
        validators: [validator],
      );
    });

    group('assertPreconditions', () {
      group('when validation succeeds', () {
        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(named: 'validators'),
              supportedOperatingSystems: any(
                named: 'supportedOperatingSystems',
              ),
            ),
          ).thenAnswer((_) async {});
        });

        test("validates with the platform's validators and OS", () async {
          await runWithOverrides(patcher.assertPreconditions);
          verify(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
              checkShorebirdInitialized: true,
              validators: [validator],
              supportedOperatingSystems: {'test-os'},
            ),
          ).called(1);
        });
      });

      group('when validation fails', () {
        final exception = ValidationFailedException();

        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(named: 'validators'),
              supportedOperatingSystems: any(
                named: 'supportedOperatingSystems',
              ),
            ),
          ).thenThrow(exception);
        });

        test('exits with the validation exit code', () async {
          await expectLater(
            () => runWithOverrides(patcher.assertPreconditions),
            exitsWithCode(exception.exitCode),
          );
        });
      });
    });

    group('assertUnpatchableDiffs', () {
      test("checks diffs with the platform's archive differ", () async {
        const diffStatus = DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: false,
        );
        final tempDir = Directory.systemTemp.createTempSync();
        final releaseArchive = File(p.join(tempDir.path, 'release.zip'));
        final patchArchive = File(p.join(tempDir.path, 'patch.zip'));
        when(
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArchive: any(named: 'localArchive'),
            releaseArchive: any(named: 'releaseArchive'),
            archiveDiffer: any(named: 'archiveDiffer'),
            allowAssetChanges: any(named: 'allowAssetChanges'),
            allowNativeChanges: any(named: 'allowNativeChanges'),
          ),
        ).thenAnswer((_) async => diffStatus);

        final result = await runWithOverrides(
          () => patcher.assertUnpatchableDiffs(
            releaseArtifact: MockReleaseArtifact(),
            releaseArchive: releaseArchive,
            patchArchive: patchArchive,
          ),
        );

        expect(result, equals(diffStatus));
        verify(
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArchive: patchArchive,
            releaseArchive: releaseArchive,
            archiveDiffer: const LinuxBundleDiffer(),
            allowAssetChanges: false,
            allowNativeChanges: false,
          ),
        ).called(1);
      });
    });

    group('buildPatchArtifact', () {
      group('when the build fails', () {
        test('throws the build error', () async {
          final exception = Exception('Failed to build app');
          patcher.buildError = exception;
          await expectLater(
            () => runWithOverrides(() => patcher.buildPatchArtifact()),
            throwsA(exception),
          );
        });
      });

      group('when the build succeeds', () {
        test('returns a zip of the directory the build returned', () async {
          File(p.join(builtDirectory.path, 'built.txt')).createSync();
          File(p.join(appDirectory.path, 'app.txt')).createSync();

          final zip = await runWithOverrides(
            () => patcher.buildPatchArtifact(),
          );

          expect(zip.path, endsWith('.zip'));
          final names = ZipDecoder()
              .decodeBytes(zip.readAsBytesSync())
              .files
              .map((f) => f.name);
          expect(names, contains('built.txt'));
          expect(names, isNot(contains('app.txt')));
        });

        test('passes the encoded public key to the build', () async {
          final keyDir = Directory.systemTemp.createTempSync();
          addTearDown(() => keyDir.deleteSync(recursive: true));
          final publicKeyFile = File(p.join(keyDir.path, 'key.pem'))
            ..writeAsStringSync('pem-from-file');
          when(
            () => argResults[CommonArguments.publicKeyArg.name],
          ).thenReturn(publicKeyFile.path);
          when(
            () => codeSigner.base64PublicKeyFromPem(any()),
          ).thenReturn('encoded-public-key');

          await runWithOverrides(() => patcher.buildPatchArtifact());

          expect(patcher.builtWithPublicKey, equals('encoded-public-key'));
          verify(
            () => codeSigner.base64PublicKeyFromPem('pem-from-file'),
          ).called(1);
        });

        test(
          'passes a public key from --public-key-cmd to the build',
          () async {
            when(
              () => argResults[CommonArguments.publicKeyCmd.name],
            ).thenReturn('print-key');
            when(
              () => argResults.wasParsed(CommonArguments.publicKeyCmd.name),
            ).thenReturn(true);
            when(
              () => codeSigner.runPublicKeyCmd('print-key'),
            ).thenAnswer((_) async => 'pem-from-cmd');
            when(
              () => codeSigner.base64PublicKeyFromPem('pem-from-cmd'),
            ).thenReturn('encoded-from-cmd');

            await runWithOverrides(() => patcher.buildPatchArtifact());

            expect(patcher.builtWithPublicKey, equals('encoded-from-cmd'));
          },
        );

        test('forwards additional args', () async {
          when(
            () => argResults.rest,
          ).thenReturn(['--build-name=1.2.3', '--build-number=4']);
          await runWithOverrides(() => patcher.buildPatchArtifact());
          expect(
            patcher.builtWithArgs,
            containsAll(['--build-name=1.2.3', '--build-number=4']),
          );
        });

        test('passes extraBuildArgs', () async {
          patcher.extraBuildArgs = [
            '--obfuscate',
            '--split-debug-info=build/shorebird/symbols',
          ];
          await runWithOverrides(() => patcher.buildPatchArtifact());
          expect(
            patcher.builtWithArgs,
            containsAll([
              '--obfuscate',
              '--split-debug-info=build/shorebird/symbols',
            ]),
          );
        });
      });
    });

    group('createPatchArtifacts', () {
      late File releaseArtifact;
      late File patchArtifact;
      late File diffFile;
      Directory? extractedReleaseTo;

      setUp(() {
        extractedReleaseTo = null;
        final tempDir = Directory.systemTemp.createTempSync();
        releaseArtifact = File(p.join(tempDir.path, 'release.zip'))
          ..createSync(recursive: true);
        diffFile = File(p.join(tempDir.path, 'diff.so'))
          ..createSync(recursive: true);
        patchArtifact = File(p.join(appDirectory.path, 'lib', 'app.so'))
          ..createSync(recursive: true)
          ..writeAsStringSync('patch');

        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((invocation) async {
          extractedReleaseTo =
              (invocation.namedArguments[#outputDirectory] as Directory)
                ..createSync(recursive: true);
        });
      });

      group('when creating the diff fails', () {
        setUp(() {
          when(
            () => artifactManager.createDiff(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
            ),
          ).thenThrow(Exception('Failed to create diff'));
        });

        test('exits with software error code', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'app-id',
                releaseId: 42,
                releaseArtifact: releaseArtifact,
              ),
            ),
            throwsA(
              isA<ProcessExit>().having((e) => e.exitCode, 'exitCode', 70),
            ),
          );
        });

        test('deletes the extracted release', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'app-id',
                releaseId: 42,
                releaseArtifact: releaseArtifact,
              ),
            ),
            throwsA(isA<ProcessExit>()),
          );

          expect(extractedReleaseTo, isNotNull);
          expect(extractedReleaseTo!.existsSync(), isFalse);
        });
      });

      group('when creating the diff succeeds', () {
        setUp(() {
          when(
            () => artifactManager.createDiff(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
            ),
          ).thenAnswer((_) async => diffFile.path);
        });

        test('diffs the Dart library of the release and the patch', () async {
          await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: 'app-id',
              releaseId: 42,
              releaseArtifact: releaseArtifact,
            ),
          );
          final captured = verify(
            () => artifactManager.createDiff(
              releaseArtifactPath: captureAny(named: 'releaseArtifactPath'),
              patchArtifactPath: captureAny(named: 'patchArtifactPath'),
            ),
          ).captured;
          final releasePath = captured[0] as String;
          final patchPath = captured[1] as String;

          // The release side must come from the extracted release artifact,
          // and the patch side from the freshly built app.
          expect(extractedReleaseTo, isNotNull);
          expect(
            releasePath,
            equals(p.join(extractedReleaseTo!.path, 'lib', 'app.so')),
          );
          expect(p.isWithin(appDirectory.path, releasePath), isFalse);
          expect(patchPath, equals(patchArtifact.path));
          expect(p.isWithin(appDirectory.path, patchPath), isTrue);
        });

        test('deletes the extracted release', () async {
          await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: 'app-id',
              releaseId: 42,
              releaseArtifact: releaseArtifact,
            ),
          );

          expect(extractedReleaseTo, isNotNull);
          expect(extractedReleaseTo!.existsSync(), isFalse);
          expect(releaseArtifact.existsSync(), isTrue);
        });

        test('returns an x86_64 patch artifact', () async {
          final patchArtifacts = await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: 'app-id',
              releaseId: 42,
              releaseArtifact: releaseArtifact,
              supplementDirectory: Directory('supplement'),
            ),
          );

          expect(
            patchArtifacts,
            equals({
              Arch.x86_64: PatchArtifactBundle(
                arch: Arch.x86_64.arch,
                path: diffFile.path,
                hash: sha256
                    .convert(patchArtifact.readAsBytesSync())
                    .toString(),
                size: diffFile.lengthSync(),
              ),
            }),
          );
        });

        group('when signing keys are provided', () {
          setUp(() {
            final publicKeyFile = File(
              p.join(
                Directory.systemTemp.createTempSync().path,
                'public-key.pem',
              ),
            )..createSync();
            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(publicKeyFile.path);
            when(
              () => argResults[CommonArguments.privateKeyArg.name],
            ).thenReturn('private-key.pem');
            when(
              () => codeSigner.sign(
                message: any(named: 'message'),
                privateKeyPemFile: any(named: 'privateKeyPemFile'),
              ),
            ).thenReturn('signature');
            when(
              () => codeSigner.verify(
                message: any(named: 'message'),
                signature: any(named: 'signature'),
                publicKeyPem: any(named: 'publicKeyPem'),
              ),
            ).thenReturn(true);
          });

          test('signs the patch', () async {
            final result = await runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'app-id',
                releaseId: 42,
                releaseArtifact: releaseArtifact,
              ),
            );

            expect(result[Arch.x86_64]!.hashSignature, equals('signature'));
            verify(
              () => codeSigner.sign(
                message: any(named: 'message'),
                privateKeyPemFile: any(
                  named: 'privateKeyPemFile',
                  that: isA<File>().having(
                    (f) => f.path,
                    'path',
                    equals(File('private-key.pem').path),
                  ),
                ),
              ),
            ).called(1);
          });
        });
      });
    });

    group('extractReleaseVersionFromArtifact', () {
      test('reads the version from the extracted release', () async {
        Directory? extractedTo;
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((invocation) async {
          extractedTo =
              invocation.namedArguments[#outputDirectory] as Directory;
        });

        final version = await runWithOverrides(
          () => patcher.extractReleaseVersionFromArtifact(File('app.zip')),
        );

        expect(version, equals('1.2.3'));
        expect(patcher.versionReadFrom, equals(extractedTo));
      });

      test('deletes the extracted release', () async {
        Directory? extractedTo;
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((invocation) async {
          extractedTo =
              (invocation.namedArguments[#outputDirectory] as Directory)
                ..createSync(recursive: true);
        });

        await runWithOverrides(
          () => patcher.extractReleaseVersionFromArtifact(File('app.zip')),
        );

        expect(extractedTo, isNotNull);
        expect(extractedTo!.existsSync(), isFalse);
      });
    });
  });
}
