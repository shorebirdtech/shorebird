import 'dart:io';

import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template macos_patcher}
/// Functions to create and apply patches to a macOS release.
/// {@endtemplate}
class MacosPatcher extends Patcher {
  /// {@macro macos_patcher}
  MacosPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  @override
  String get primaryReleaseArtifactArch => '';

  @override
  Future<void> assertPreconditions() async {
    // TODO: implement assertPreconditions
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) async {
    // return DiffStatus({
    //   hasAssetChanges: false,
    //   hasNativeChanges: false,
    // });
    // TODO: implement assertUnpatchableDiffs
    throw UnimplementedError();
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    // TODO: implement buildPatchArtifact
    throw UnimplementedError();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
  }) async {
    // TODO: implement createPatchArtifacts
    throw UnimplementedError();
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    // TODO: implement extractReleaseVersionFromArtifact
    throw UnimplementedError();
  }
}
