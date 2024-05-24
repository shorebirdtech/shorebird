import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_protocol/src/models/create_patch_metadata.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(Patcher, () {
    group('linkPercentage', () {
      test('defaults to null', () {
        expect(
          _TestPatcher(
            argResults: MockArgResults(),
            flavor: null,
            target: null,
          ).linkPercentage,
          isNull,
        );
      });
    });

    group('assertArgsAreValid', () {
      late _TestPatcher patcher;
      late ArgResults argResults;
      late ShorebirdLogger logger;

      R runWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            loggerRef.overrideWith(() => logger),
          },
        );
      }

      setUp(() {
        setExitFunctionForTests();
        argResults = MockArgResults();
        logger = MockShorebirdLogger();
        patcher = _TestPatcher(
          argResults: argResults,
          flavor: null,
          target: null,
        );

        when(() => argResults.wasParsed(CommonArguments.publicKeyArg.name))
            .thenReturn(false);

        when(() => argResults.wasParsed(CommonArguments.privateKeyArg.name))
            .thenReturn(false);
      });

      group('when no key pair is provided', () {
        test('is valid', () {
          expect(
            runWithOverrides(patcher.assertArgsAreValid),
            completes,
          );
        });
      });

      group(
        'when given existing private and public key files',
        () {
          test('is valid', () async {
            when(
              () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
            ).thenReturn(true);
            when(() => argResults.wasParsed(CommonArguments.publicKeyArg.name))
                .thenReturn(true);
            when(() => argResults[CommonArguments.privateKeyArg.name])
                .thenReturn(createTempFile('private.pem').path);
            when(() => argResults[CommonArguments.publicKeyArg.name])
                .thenReturn(createTempFile('public.pem').path);

            expect(
              runWithOverrides(patcher.assertArgsAreValid),
              completes,
            );
          });
        },
      );

      group(
        'when given an existing private key and nonexistent public key',
        () {
          test('logs error and exits with usage code', () async {
            when(
              () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
            ).thenReturn(true);
            when(() => argResults.wasParsed(CommonArguments.publicKeyArg.name))
                .thenReturn(false);
            when(() => argResults[CommonArguments.privateKeyArg.name])
                .thenReturn(createTempFile('private.pem').path);

            await expectLater(
              () => runWithOverrides(patcher.assertArgsAreValid),
              exitsWithCode(ExitCode.usage),
            );
            verify(
              () => logger.err(
                'Both public and private keys must be provided or absent.',
              ),
            ).called(1);
          });
        },
      );

      group(
        'when given an existing public key and nonexistent private key',
        () {
          test('fails and logs the err', () async {
            when(
              () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
            ).thenReturn(false);
            when(() => argResults.wasParsed(CommonArguments.publicKeyArg.name))
                .thenReturn(true);
            when(() => argResults[CommonArguments.publicKeyArg.name])
                .thenReturn(createTempFile('public.pem').path);

            await expectLater(
              () => runWithOverrides(patcher.assertArgsAreValid),
              exitsWithCode(ExitCode.usage),
            );
            verify(
              () => logger.err(
                'Both public and private keys must be provided or absent.',
              ),
            ).called(1);
          });
        },
      );
    });
  });
}

class _TestPatcher extends Patcher {
  _TestPatcher({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ArchiveDiffer get archiveDiffer => throw UnimplementedError();

  @override
  Future<void> assertPreconditions() {
    throw UnimplementedError();
  }

  @override
  Future<File> buildPatchArtifact() {
    throw UnimplementedError();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CreatePatchMetadata> createPatchMetadata(DiffStatus diffStatus) {
    throw UnimplementedError();
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    throw UnimplementedError();
  }

  @override
  String get primaryReleaseArtifactArch => throw UnimplementedError();

  @override
  ReleaseType get releaseType => throw UnimplementedError();
}
