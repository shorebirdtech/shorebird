import 'dart:io';

import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive_analysis/linux_bundle_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/commands/patch/desktop_patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// {@template linux_patcher}
/// Functions to create a linux patch.
/// {@endtemplate}
class LinuxPatcher extends DesktopPatcher {
  /// {@macro linux_patcher}
  LinuxPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.linux;

  @override
  List<Validator> get commandValidators => doctor.linuxCommandValidators;

  @override
  String get hostOperatingSystem => NativePlatform.linux;

  @override
  LinuxBundleDiffer get archiveDiffer => const LinuxBundleDiffer();

  /// The release artifact is the zipped directory at
  /// build/linux/x64/release/bundle.
  @override
  Directory get appDirectory => artifactManager.linuxBundleDirectory;

  @override
  List<String> get dartLibraryPathSegments => const ['lib', 'libapp.so'];

  @override
  Future<Directory> buildApp({
    required List<String> args,
    String? base64PublicKey,
  }) async {
    await artifactBuilder.buildLinuxApp(
      target: target,
      args: args,
      base64PublicKey: base64PublicKey,
    );
    return appDirectory;
  }

  @override
  Future<String> versionFromAppDirectory(Directory appDirectory) async =>
      linux.versionFromLinuxBundle(bundleRoot: appDirectory);
}
