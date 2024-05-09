import 'dart:io';

import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_code_push_protocol/src/models/release.dart';
import 'package:shorebird_code_push_protocol/src/models/update_release_metadata.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(Releaser, () {
    group('requiresReleaseVersionArg', () {
      test('defaults to false', () {
        final releaser = FakeReleaser(
          argResults: MockArgResults(),
          flavor: 'flavor',
          target: 'target',
        );
        expect(releaser.requiresReleaseVersionArg, false);
      });
    });
  });
}

class FakeReleaser extends Releaser {
  FakeReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() {
    throw UnimplementedError();
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) {
    throw UnimplementedError();
  }

  @override
  String get postReleaseInstructions => throw UnimplementedError();

  @override
  Future<UpdateReleaseMetadata> releaseMetadata() => throw UnimplementedError();

  @override
  ReleaseType get releaseType => throw UnimplementedError();

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> assertArgsAreValid() {
    throw UnimplementedError();
  }

  @override
  Future<void> assertPreconditions() {
    throw UnimplementedError();
  }
}
