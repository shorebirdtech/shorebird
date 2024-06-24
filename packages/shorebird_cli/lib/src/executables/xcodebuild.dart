import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// {@template xcode_project_build_info}
/// Xcode project build information returned by `xcodebuild -list`
/// {@endtemplate}
class XcodeProjectBuildInfo {
  /// {@macro xcode_project_build_info}
  const XcodeProjectBuildInfo({
    this.targets = const {},
    this.buildConfigurations = const {},
    this.schemes = const {},
  });

  /// Set of targets configured for the project.
  final Set<String> targets;

  /// Set of build configurations configured for the project.
  final Set<String> buildConfigurations;

  /// Set of schemes configured for the project.
  final Set<String> schemes;
}

/// A reference to a [XcodeBuild] instance.
final xcodeBuildRef = create(XcodeBuild.new);

/// The [XcodeBuild] instance available in the current zone.
XcodeBuild get xcodeBuild => read(xcodeBuildRef);

/// A wrapper around the `xcodebuild` command.
class XcodeBuild {
  /// Name of the executable.
  static const executable = 'xcodebuild';

  /// Get the current Xcode version.
  Future<String> version() async {
    final result = await process.run(executable, ['-version']);
    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(executable, ['-version'], '${result.stderr}');
    }

    final lines = LineSplitter.split('${result.stdout}').map((e) => e.trim());
    return lines.join(' ');
  }
}
