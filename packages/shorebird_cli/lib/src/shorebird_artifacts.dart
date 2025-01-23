// Allowing one member abstracts for consistency/namespace/ease of testing.
// ignore_for_file: one_member_abstracts

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// All Shorebird artifacts used explicitly by Shorebird.
enum ShorebirdArtifact {
  /// The iOS analyze_snapshot executable.
  analyzeSnapshotIos,

  /// The macOS analyze_snapshot executable.
  analyzeSnapshotMacOS,

  /// The aot_tools executable or kernel file.
  aotTools,

  /// The gen_snapshot executable for iOS.
  genSnapshotIos,

  /// The gen_snapshot executable for macOS.
  genSnapshotMacOS,
}

/// A reference to a [ShorebirdArtifacts] instance.
final shorebirdArtifactsRef = create<ShorebirdArtifacts>(
  ShorebirdCachedArtifacts.new,
);

/// The [ShorebirdArtifacts] instance available in the current zone.
ShorebirdArtifacts get shorebirdArtifacts => read(shorebirdArtifactsRef);

/// {@template shorebird_artifacts}
/// A class that provides access to Shorebird artifacts.
/// {@endtemplate}
abstract class ShorebirdArtifacts {
  /// Returns the path to the given [artifact].
  String getArtifactPath({required ShorebirdArtifact artifact});
}

/// {@template shorebird_cached_artifacts}
/// A class that provides access to cached Shorebird artifacts.
/// {@endtemplate}
class ShorebirdCachedArtifacts implements ShorebirdArtifacts {
  /// {@macro shorebird_cached_artifacts}
  const ShorebirdCachedArtifacts();

  @override
  String getArtifactPath({
    required ShorebirdArtifact artifact,
  }) {
    switch (artifact) {
      case ShorebirdArtifact.analyzeSnapshotIos:
        return _analyzeSnapshotIosFile.path;
      case ShorebirdArtifact.analyzeSnapshotMacOS:
        return _analyzeSnapshotMacosFile.path;
      case ShorebirdArtifact.aotTools:
        return _aotToolsFile.path;
      case ShorebirdArtifact.genSnapshotIos:
        return _genSnapshotIosFile.path;
      case ShorebirdArtifact.genSnapshotMacOS:
        return _genSnapshotMacOSFile.path;
    }
  }

  File get _analyzeSnapshotIosFile {
    return File(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ios-release',
        'analyze_snapshot_arm64',
      ),
    );
  }

  File get _analyzeSnapshotMacosFile {
    return File(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'analyze_snapshot',
      ),
    );
  }

  File get _aotToolsFile {
    const executableName = 'aot-tools';
    final kernelFile = File(
      p.join(
        cache.getArtifactDirectory(executableName).path,
        shorebirdEnv.shorebirdEngineRevision,
        '$executableName.dill',
      ),
    );
    if (kernelFile.existsSync()) {
      return kernelFile;
    }

    // We shipped aot-tools as an executable in the past, so we return that if
    // no kernel file is found.
    return File(
      p.join(
        cache.getArtifactDirectory(executableName).path,
        shorebirdEnv.shorebirdEngineRevision,
        executableName,
      ),
    );
  }

  File get _genSnapshotIosFile {
    return File(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ios-release',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacOSFile {
    return File(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'gen_snapshot',
      ),
    );
  }
}

/// {@template shorebird_local_engine_artifacts}
/// A class that provides access to locally built Shorebird artifacts.
/// {@endtemplate}
class ShorebirdLocalEngineArtifacts implements ShorebirdArtifacts {
  /// {@macro shorebird_local_engine_artifacts}
  const ShorebirdLocalEngineArtifacts();

  @override
  String getArtifactPath({required ShorebirdArtifact artifact}) {
    switch (artifact) {
      case ShorebirdArtifact.analyzeSnapshotIos:
        return _analyzeSnapshotIosFile.path;
      case ShorebirdArtifact.analyzeSnapshotMacOS:
        return _analyzeSnapshotMacosFile.path;
      case ShorebirdArtifact.aotTools:
        return _aotToolsFile.path;
      case ShorebirdArtifact.genSnapshotIos:
        return _genSnapshotIosFile.path;
      case ShorebirdArtifact.genSnapshotMacOS:
        return _genSnapshotMacosFile.path;
    }
  }

  File get _analyzeSnapshotIosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'analyze_snapshot_arm64',
      ),
    );
  }

  File get _analyzeSnapshotMacosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'analyze_snapshot',
      ),
    );
  }

  File get _aotToolsFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'flutter',
        'third_party',
        'dart',
        'pkg',
        'aot_tools',
        'bin',
        'aot_tools.dart',
      ),
    );
  }

  File get _genSnapshotIosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        // 'clang_x64',
        'artifacts_x64',
        // 'gen_snapshot',
        'gen_snapshot_x64',
      ),
    );
  }
}
