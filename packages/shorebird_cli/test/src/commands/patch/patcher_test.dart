import 'dart:io';

import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

class FakeFile extends Fake implements File {}

void main() {
  group(Patcher, () {
    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(DeploymentTrack.stable);
      registerFallbackValue(FakeFile());
    });

    group('linkPercentage', () {
      test('defaults to null', () {
        expect(
          _TestPatcher(
            argParser: MockArgParser(),
            argResults: MockArgResults(),
            flavor: null,
            target: null,
          ).linkPercentage,
          isNull,
        );
      });
    });

    group('supplementaryReleaseArtifactArch', () {
      test('defaults to null', () {
        expect(
          _TestPatcher(
            argParser: MockArgParser(),
            argResults: MockArgResults(),
            flavor: null,
            target: null,
          ).supplementaryReleaseArtifactArch,
          isNull,
        );
      });
    });

    group('assertArgsAreValid', () {
      test('has no validations by default', () {
        expect(
          _TestPatcher(
            argParser: MockArgParser(),
            argResults: MockArgResults(),
            flavor: null,
            target: null,
          ).assertArgsAreValid,
          returnsNormally,
        );
      });
    });

    group('buildNameAndNumberArgsFromReleaseVersion', () {
      late ArgResults argResults;
      setUp(() {
        argResults = MockArgResults();
        when(() => argResults.options).thenReturn([]);
      });

      group('when releaseVersion is not specified', () {
        test('returns an empty list', () {
          expect(
            _TestPatcher(
              argParser: MockArgParser(),
              argResults: MockArgResults(),
              flavor: null,
              target: null,
            ).buildNameAndNumberArgsFromReleaseVersion(null),
            isEmpty,
          );
        });
      });

      group('when an invalid --release-version is specified', () {
        test('returns an empty list', () {
          expect(
            _TestPatcher(
              argParser: MockArgParser(),
              argResults: argResults,
              flavor: null,
              target: null,
            ).buildNameAndNumberArgsFromReleaseVersion('invalid'),
            isEmpty,
          );
        });
      });

      group('when a valid --release-version is specified', () {
        group('when --build-name is specified', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['--build-name=foo']);
          });

          test('returns an empty list', () {
            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              isEmpty,
            );
          });
        });

        group('when --build-number is specified', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['--build-number=42']);
          });

          test('returns an empty list', () {
            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              isEmpty,
            );
          });
        });

        group('when neither --build-name nor --build-number are specified', () {
          test('returns --build-name and --build-number', () {
            when(() => argResults.rest).thenReturn([]);

            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              equals(['--build-name=1.2.3', '--build-number=4']),
            );
          });
        });

        group('when build-name and build-number were parsed as options', () {
          setUp(() {
            when(
              () => argResults.wasParsed(CommonArguments.buildNameArg.name),
            ).thenReturn(true);
            when(
              () => argResults.wasParsed(CommonArguments.buildNumberArg.name),
            ).thenReturn(true);
            when(() => argResults.options).thenReturn([
              'release-version',
              'build-name',
              'build-number',
              'platforms',
            ]);
          });

          test('returns an empty list', () {
            expect(
              _TestPatcher(
                argParser: MockArgParser(),
                argResults: argResults,
                flavor: null,
                target: null,
              ).buildNameAndNumberArgsFromReleaseVersion('1.2.3+4'),
              isEmpty,
            );
          });
        });
      });
    });

    group('uploadPatchArtifacts', () {
      test('calls codePushClientWrapper.publishPatch '
          'with correct args', () async {
        final args = MockArgResults();
        final patcher = _TestPatcher(
          argParser: MockArgParser(),
          argResults: args,
          flavor: null,
          target: null,
          releaseType: ReleaseType.android,
        );
        const appId = 'test_app_id';
        const releaseId = 42;
        const metadata = <String, String>{};
        const artifacts = <Arch, PatchArtifactBundle>{};
        const track = DeploymentTrack.stable;
        final codePushClientWrapper = MockCodePushClientWrapper();
        when(
          () => codePushClientWrapper.publishPatch(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            metadata: any(named: 'metadata'),
            platform: any(named: 'platform'),
            track: any(named: 'track'),
            patchArtifactBundles: any(named: 'patchArtifactBundles'),
          ),
        ).thenAnswer((_) async {});
        await runScoped(
          () async {
            await patcher.uploadPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              metadata: metadata,
              artifacts: artifacts,
              track: track,
            );
          },
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          },
        );
        verify(
          () => codePushClientWrapper.publishPatch(
            appId: appId,
            releaseId: releaseId,
            metadata: metadata,
            platform: ReleaseType.android.releasePlatform,
            track: track,
            patchArtifactBundles: artifacts,
          ),
        ).called(1);
      });
    });

    group('signHash', () {
      final cryptoFixturesBasePath = p.join('test', 'fixtures', 'crypto');
      final privateKeyFile = File(
        p.join(cryptoFixturesBasePath, 'private.pem'),
      );

      late ArgParser argParser;
      late ArgResults argResults;
      late CodeSigner codeSigner;
      late ShorebirdLogger logger;
      late File publicKeyTempFile;

      setUp(() {
        argParser = ArgParser()
          ..addOption(CommonArguments.publicKeyArg.name)
          ..addOption(CommonArguments.privateKeyArg.name)
          ..addOption(CommonArguments.publicKeyCmd.name)
          ..addOption(CommonArguments.signCmd.name);
        codeSigner = MockCodeSigner();
        logger = MockShorebirdLogger();
        publicKeyTempFile = File(
          p.join(
            Directory.systemTemp.createTempSync().path,
            'public.pem',
          ),
        )..writeAsStringSync('fake-public-key-pem');
      });

      test('returns null when no signing is configured', () async {
        argResults = argParser.parse([]);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, isNull);
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test('returns signature from file-based signing', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyArg.name}=${publicKeyTempFile.path}',
          '--${CommonArguments.privateKeyArg.name}=${privateKeyFile.path}',
        ]);

        when(
          () => codeSigner.sign(
            message: any(named: 'message'),
            privateKeyPemFile: any(named: 'privateKeyPemFile'),
          ),
        ).thenReturn('file-signature');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(true);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, equals('file-signature'));
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test(
        'throws ProcessExit when signer present but no public key',
        () async {
          argResults = argParser.parse([
            '--${CommonArguments.privateKeyArg.name}=${privateKeyFile.path}',
          ]);

          when(
            () => codeSigner.sign(
              message: any(named: 'message'),
              privateKeyPemFile: any(named: 'privateKeyPemFile'),
            ),
          ).thenReturn('file-signature');

          final patcher = _TestPatcher(
            argParser: argParser,
            argResults: argResults,
            flavor: null,
            target: null,
          );

          await runScoped(
            () async {
              await expectLater(
                () => patcher.signHash('test-hash'),
                throwsA(isA<ProcessExit>()),
              );
              verify(
                () => logger.err(
                  any(that: contains('public key is required')),
                ),
              ).called(1);
            },
            values: {
              codeSignerRef.overrideWith(() => codeSigner),
              loggerRef.overrideWith(() => logger),
            },
          );
        },
      );

      test('returns signature from command-based signing when valid', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=get-key-cmd',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'cmd-signature');
        when(
          () => codeSigner.runPublicKeyCmd(any()),
        ).thenAnswer((_) async => 'pem-public-key');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(true);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, equals('cmd-signature'));
            verify(
              () => codeSigner.signWithCmd(
                data: 'test-hash',
                command: 'sign-cmd',
              ),
            ).called(1);
            verify(() => codeSigner.runPublicKeyCmd('get-key-cmd')).called(1);
            verify(
              () => codeSigner.verify(
                message: 'test-hash',
                signature: 'cmd-signature',
                publicKeyPem: 'pem-public-key',
              ),
            ).called(1);
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test('throws ProcessExit when sign-cmd fails', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=get-key-cmd',
          '--${CommonArguments.signCmd.name}=bad-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenThrow(
          const ProcessException('bad-cmd', [], 'command not found', 127),
        );

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            await expectLater(
              () => patcher.signHash('test-hash'),
              throwsA(isA<ProcessExit>()),
            );
            verify(
              () => logger.err(any(that: contains('--sign-cmd'))),
            ).called(1);
          },
          values: {
            codeSignerRef.overrideWith(() => codeSigner),
            loggerRef.overrideWith(() => logger),
          },
        );
      });

      test('throws ProcessExit when public-key-cmd fails', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=bad-key-cmd',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'signature');
        when(
          () => codeSigner.runPublicKeyCmd(any()),
        ).thenThrow(
          const ProcessException(
            'bad-key-cmd',
            [],
            'command not found',
            127,
          ),
        );

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            await expectLater(
              () => patcher.signHash('test-hash'),
              throwsA(isA<ProcessExit>()),
            );
            verify(
              () => logger.err(any(that: contains('--public-key-cmd'))),
            ).called(1);
          },
          values: {
            codeSignerRef.overrideWith(() => codeSigner),
            loggerRef.overrideWith(() => logger),
          },
        );
      });

      test('supports mixed signing (public key file + sign cmd)', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyArg.name}=${publicKeyTempFile.path}',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'cmd-signature');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(true);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            final result = await patcher.signHash('test-hash');
            expect(result, equals('cmd-signature'));
            verifyNever(() => codeSigner.runPublicKeyCmd(any()));
            verify(
              () => codeSigner.verify(
                message: 'test-hash',
                signature: 'cmd-signature',
                publicKeyPem: any(named: 'publicKeyPem'),
              ),
            ).called(1);
          },
          values: {codeSignerRef.overrideWith(() => codeSigner)},
        );
      });

      test('throws ProcessExit when signature verification fails', () async {
        argResults = argParser.parse([
          '--${CommonArguments.publicKeyCmd.name}=get-key-cmd',
          '--${CommonArguments.signCmd.name}=sign-cmd',
        ]);

        when(
          () => codeSigner.signWithCmd(
            data: any(named: 'data'),
            command: any(named: 'command'),
          ),
        ).thenAnswer((_) async => 'bad-signature');
        when(
          () => codeSigner.runPublicKeyCmd(any()),
        ).thenAnswer((_) async => 'pem-public-key');
        when(
          () => codeSigner.verify(
            message: any(named: 'message'),
            signature: any(named: 'signature'),
            publicKeyPem: any(named: 'publicKeyPem'),
          ),
        ).thenReturn(false);

        final patcher = _TestPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );

        await runScoped(
          () async {
            await expectLater(
              () => patcher.signHash('test-hash'),
              throwsA(isA<ProcessExit>()),
            );
          },
          values: {
            codeSignerRef.overrideWith(() => codeSigner),
            loggerRef.overrideWith(() => logger),
          },
        );
      });
    });
  });
}

class _TestPatcher extends Patcher {
  _TestPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
    ReleaseType? releaseType,
  }) : _releaseType = releaseType;

  final ReleaseType? _releaseType;

  @override
  Future<void> assertPreconditions() {
    throw UnimplementedError();
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    File? supplementArtifact,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    throw UnimplementedError();
  }

  @override
  String get primaryReleaseArtifactArch => throw UnimplementedError();

  @override
  ReleaseType get releaseType {
    if (_releaseType != null) return _releaseType;
    throw UnimplementedError();
  }
}
