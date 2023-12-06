// ignore_for_file: one_member_abstracts

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// All Shorebird artifacts used explicitly by Shorebird.
enum ShorebirdArtifact {
  /// The aot_tools executable.
  aotTools,

  /// The gen_snapshot executable.
  genSnapshot,

  /// The analyze_snapshot executable.
  analyzeSnapshot,
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
      case ShorebirdArtifact.aotTools:
        return _aotToolsFile.path;
      case ShorebirdArtifact.genSnapshot:
        return _genSnapshotFile.path;
      case ShorebirdArtifact.analyzeSnapshot:
        return _analyzeSnapshotFile.path;
    }
  }

  File get _aotToolsFile {
    const executableName = 'aot-tools';
    return File(
      p.join(
        cache.getArtifactDirectory(executableName).path,
        executableName,
      ),
    );
  }

  File get _genSnapshotFile {
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

  File get _analyzeSnapshotFile {
    return File(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ios-release',
        'darwin-x64',
        'analyze_snapshot',
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
      case ShorebirdArtifact.aotTools:
        return _aotToolsFile.path;
      case ShorebirdArtifact.genSnapshot:
        return _genSnapshotFile.path;
      case ShorebirdArtifact.analyzeSnapshot:
        return _analyzeSnapshotFile.path;
    }
  }

  File get _aotToolsFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'third_party',
        'dart',
        'pkg',
        'aot_tools',
        'bin',
        'aot_tools.dart',
      ),
    );
  }

  File get _genSnapshotFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        'ios_release',
        'clang_x64',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _analyzeSnapshotFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        'ios_release',
        'clang_x64',
        'analyze_snapshot_arm64',
      ),
    );
  }
}
