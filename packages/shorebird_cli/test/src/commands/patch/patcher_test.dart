import 'dart:io';

import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_code_push_protocol/src/models/create_patch_metadata.dart';
import 'package:shorebird_code_push_protocol/src/models/release_artifact.dart';
import 'package:test/test.dart';

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
      test('has no validations by default', () {
        expect(
          _TestPatcher(
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
  });
}

class _TestPatcher extends Patcher {
  _TestPatcher({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

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
