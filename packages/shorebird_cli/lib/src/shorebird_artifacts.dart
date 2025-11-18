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

  /// The gen_snapshot executable for macOS that creates arm64 snapshots.
  genSnapshotMacosArm64,

  /// The gen_snapshot executable for macOS that creates x64 snapshots.
  genSnapshotMacosX64,
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
      case ShorebirdArtifact.genSnapshotMacosArm64:
        return _genSnapshotMacOsArm64File.path;
      case ShorebirdArtifact.genSnapshotMacosX64:
        return _genSnapshotMacOsX64File.path;
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

  File get _genSnapshotMacOsArm64File => _resolveMacOsGenSnapshot(
    preferredDirs: const [
      'darwin-arm64',
      'darwin-arm64-release',
      'darwin-x64',
      'darwin-x64-release',
    ],
    candidateNames: const ['gen_snapshot_arm64', 'gen_snapshot'],
  );

  File get _genSnapshotMacOsX64File => _resolveMacOsGenSnapshot(
    preferredDirs: const [
      'darwin-x64',
      'darwin-x64-release',
      'darwin-arm64',
      'darwin-arm64-release',
    ],
    candidateNames: const ['gen_snapshot_x64', 'gen_snapshot'],
  );

  File _resolveMacOsGenSnapshot({
    required List<String> preferredDirs,
    required List<String> candidateNames,
  }) {
    for (final dir in preferredDirs) {
      for (final fileName in candidateNames) {
        final file = File(
          p.join(
            shorebirdEnv.flutterDirectory.path,
            'bin',
            'cache',
            'artifacts',
            'engine',
            dir,
            fileName,
          ),
        );
        if (file.existsSync()) {
          return file;
        }
      }
    }

    return File(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        preferredDirs.first,
        candidateNames.first,
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
      case ShorebirdArtifact.genSnapshotMacosArm64:
        return _genSnapshotMacosArm64File.path;
      case ShorebirdArtifact.genSnapshotMacosX64:
        return _genSnapshotMacosX64File.path;
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

  File get _genSnapshotMacosArm64File {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'artifacts_arm64',
        'gen_snapshot',
      ),
    );
  }

  File get _genSnapshotMacosX64File {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'artifacts_x64',
        'gen_snapshot',
      ),
    );
  }
}
