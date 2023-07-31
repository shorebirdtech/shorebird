import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';

/// {@template missing_ios_project_exception}
/// Thrown when the Flutter project does not have iOS configured as a platform.
/// {@endtemplate}
class MissingIOSProjectException implements Exception {
  /// {@macro missing_ios_project_exception}
  const MissingIOSProjectException(this.projectPath);

  final String projectPath;

  @override
  String toString() {
    return '''
Could not find an iOS project in $projectPath.
To add iOS, run "flutter create . --platforms ios"''';
  }
}

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

  /// Return Xcode project build info returned by `xcodebuild -list`
  /// for the app at [projectPath].
  Future<XcodeProjectBuildInfo> list(String projectPath) async {
    // Flutter apps have ios files in root/ios
    // Flutter modules have ios files in root/.ios
    final iosRoot = [
      Directory(p.join(projectPath, 'ios')),
      Directory(p.join(projectPath, '.ios')),
    ].firstWhereOrNull((dir) => dir.existsSync());

    if (iosRoot == null) throw MissingIOSProjectException(projectPath);

    const arguments = ['-list'];
    final result = await process.run(
      executable,
      arguments,
      workingDirectory: iosRoot.path,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(executable, arguments, '${result.stderr}');
    }

    final lines = '${result.stdout}'.split('\n');
    final targets = <String>{};
    final buildConfigurations = <String>{};
    final schemes = <String>{};
    Set<String>? bucket;

    for (final line in lines) {
      if (line.isEmpty) {
        bucket = null;
        continue;
      }
      if (line.endsWith('Targets:')) {
        bucket = targets;
        continue;
      }
      if (line.endsWith('Build Configurations:')) {
        bucket = buildConfigurations;
        continue;
      }
      if (line.endsWith('Schemes:')) {
        bucket = schemes;
        continue;
      }
      bucket?.add(line.trim());
    }
    if (schemes.isEmpty) schemes.add('Runner');

    return XcodeProjectBuildInfo(
      targets: targets,
      buildConfigurations: buildConfigurations,
      schemes: schemes,
    );
  }
}
