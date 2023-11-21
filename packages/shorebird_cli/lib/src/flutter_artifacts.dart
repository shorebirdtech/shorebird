import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// All Flutter artifacts used explicitly by Shorebird.
enum FlutterArtifact {
  /// The gen_snapshot executable.
  genSnapshot,

  /// The analyze_snapshot executable.
  analyzeSnapshot,
}

// A reference to a [FlutterArtifacts] instance.
final flutterArtifactsRef = create<FlutterArtifacts>(
  () => const FlutterCachedArtifacts(),
);

// The [FlutterArtifacts] instance available in the current zone.
FlutterArtifacts get flutterArtifacts => read(flutterArtifactsRef);

/// {@template flutter_artifacts}
/// A class that provides access to Flutter artifacts.
/// {@endtemplate}
abstract class FlutterArtifacts {
  /// {@macro flutter_artifacts}
  const FlutterArtifacts();

  /// Returns the path to the given [artifact].
  String getArtifactPath({required FlutterArtifact artifact});
}

/// {@template flutter_cached_artifacts}
/// A class that provides access to cached Flutter artifacts.
/// {@endtemplate}
class FlutterCachedArtifacts implements FlutterArtifacts {
  /// {@macro flutter_cached_artifacts}
  const FlutterCachedArtifacts();

  @override
  String getArtifactPath({
    required FlutterArtifact artifact,
  }) {
    switch (artifact) {
      case FlutterArtifact.genSnapshot:
        return _genSnapshotFile.path;
      case FlutterArtifact.analyzeSnapshot:
        return _analyzeSnapshotFile.path;
    }
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
        'analyze_snapshot_arm64',
      ),
    );
  }
}

/// {@template flutter_local_engine_artifacts}
/// A class that provides access to locally built Flutter artifacts.
/// {@endtemplate}
class FlutterLocalEngineArtifacts implements FlutterArtifacts {
  /// {@macro flutter_local_engine_artifacts}
  const FlutterLocalEngineArtifacts();

  @override
  String getArtifactPath({required FlutterArtifact artifact}) {
    switch (artifact) {
      case FlutterArtifact.genSnapshot:
        return _genSnapshotFile.path;
      case FlutterArtifact.analyzeSnapshot:
        return _analyzeSnapshotFile.path;
    }
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
