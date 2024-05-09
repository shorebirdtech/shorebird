import 'dart:io';

import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_code_push_protocol/src/models/create_patch_metadata.dart';
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
