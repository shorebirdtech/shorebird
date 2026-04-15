import 'dart:io';

import 'package:path/path.dart' as p;

/// Lightweight, privacy-safe snapshot of the build environment that's
/// emitted into the build trace summary. Only booleans, small integer
/// counts, and a categorical CI-provider enum — no paths, no project or
/// user identifiers, no URLs.
///
/// Field-data goal: with this we can tell apart "build was slow because
/// no caching is configured" from "build was slow despite caching being
/// on", which is the question that decides whether Shorebird should
/// invest in build-caching products.
class BuildEnvironment {
  /// Creates a [BuildEnvironment] directly from already-detected fields.
  /// Tests use this; production code uses [BuildEnvironment.detect].
  BuildEnvironment({
    required this.isCi,
    required this.ciProvider,
    required this.gradleBuildCacheEnabled,
    required this.gradleConfigurationCacheEnabled,
    required this.gradleParallelEnabled,
    required this.gradleDaemonEnabled,
    required this.gradleDevelocityDetected,
    required this.gradleInitScriptCount,
    required this.iosCcacheAvailable,
  });

  /// Detect everything about the current process's environment that's
  /// relevant to build-caching analysis. [projectRoot] is the Flutter
  /// project root (used for `gradle.properties` / `settings.gradle*`
  /// detection); when null, only env vars and `~/`-scoped detection runs.
  factory BuildEnvironment.detect({
    required Map<String, String> environment,
    Directory? homeDir,
    Directory? projectRoot,
  }) {
    final ciProvider = _detectCiProvider(environment);
    final isCi = ciProvider != null || environment['CI'] == 'true';

    // Gradle properties: user-global first, project-local overrides last.
    File? prop(String? base, List<String> rest) {
      if (base == null) return null;
      return File(p.joinAll([base, ...rest]));
    }

    final gradleProps = <String, String>{
      ..._readPropsFile(
        prop(homeDir?.path, const ['.gradle', 'gradle.properties']),
      ),
      ..._readPropsFile(
        prop(projectRoot?.path, const ['android', 'gradle.properties']),
      ),
      ..._readPropsFile(
        prop(projectRoot?.path, const ['gradle.properties']),
      ),
    };

    bool propBool(String key, {required bool defaultValue}) {
      final v = gradleProps[key];
      if (v == null) return defaultValue;
      return v.trim().toLowerCase() == 'true';
    }

    return BuildEnvironment(
      isCi: isCi,
      ciProvider: ciProvider,
      // Gradle build cache: opt-in, default off in vanilla Gradle.
      gradleBuildCacheEnabled: propBool(
        'org.gradle.caching',
        defaultValue: false,
      ),
      // Gradle configuration cache: opt-in.
      gradleConfigurationCacheEnabled: propBool(
        'org.gradle.configuration-cache',
        defaultValue: false,
      ),
      // Parallel project execution: default off.
      gradleParallelEnabled: propBool(
        'org.gradle.parallel',
        defaultValue: false,
      ),
      // Daemon: default ON (skip false-positive when explicitly disabled).
      gradleDaemonEnabled: propBool(
        'org.gradle.daemon',
        defaultValue: true,
      ),
      gradleDevelocityDetected: _detectDevelocity(projectRoot, homeDir),
      gradleInitScriptCount: _countInitScripts(homeDir),
      iosCcacheAvailable: _detectCcache(environment),
    );
  }

  /// CI environment indicator. Aggregated; we don't care which run.
  final bool isCi;

  /// Categorical CI provider — null when not on CI or unknown.
  final String? ciProvider;

  /// `org.gradle.caching=true` present in user-global or project-level
  /// `gradle.properties`. The single most actionable bit: a team without
  /// this on is leaving the easiest cache win on the table.
  final bool gradleBuildCacheEnabled;

  /// `org.gradle.configuration-cache=true` — Gradle's newer config-time
  /// cache. Less impactful than build cache but adds up.
  final bool gradleConfigurationCacheEnabled;

  /// `org.gradle.parallel=true`.
  final bool gradleParallelEnabled;

  /// `org.gradle.daemon`. Default on; explicit-false would surface here.
  final bool gradleDaemonEnabled;

  /// Develocity (formerly Gradle Enterprise) plugin detected in
  /// `settings.gradle{.kts}` or via a user-global init script.
  final bool gradleDevelocityDetected;

  /// Number of `*.gradle{.kts}` files in `~/.gradle/init.d/`. Init scripts
  /// are how teams typically auto-apply remote-cache plugins.
  final int gradleInitScriptCount;

  /// `ccache` binary available on PATH — could front xcodebuild's clang.
  final bool iosCcacheAvailable;

  /// JSON form. All fields are upload-safe (booleans, small ints, a
  /// categorical enum).
  Map<String, Object?> toJson() => <String, Object?>{
    'isCi': isCi,
    'ciProvider': ciProvider,
    'gradle': <String, Object?>{
      'buildCacheEnabled': gradleBuildCacheEnabled,
      'configurationCacheEnabled': gradleConfigurationCacheEnabled,
      'parallelEnabled': gradleParallelEnabled,
      'daemonEnabled': gradleDaemonEnabled,
      'develocityDetected': gradleDevelocityDetected,
      'initScriptCount': gradleInitScriptCount,
    },
    'ios': <String, Object?>{'ccacheAvailable': iosCcacheAvailable},
  };

  static String? _detectCiProvider(Map<String, String> env) {
    if (env['GITHUB_ACTIONS'] == 'true') return 'github';
    if (env['GITLAB_CI'] == 'true') return 'gitlab';
    if (env['CIRCLECI'] == 'true') return 'circle';
    if (env['BITRISE_IO'] == 'true') return 'bitrise';
    if (env['JENKINS_URL'] != null) return 'jenkins';
    if (env['BUILDKITE'] == 'true') return 'buildkite';
    if (env['TF_BUILD'] == 'True') return 'azure';
    if (env['CODEBUILD_BUILD_ID'] != null) return 'codebuild';
    if (env['BITBUCKET_BUILD_NUMBER'] != null) return 'bitbucket';
    if (env['TEAMCITY_VERSION'] != null) return 'teamcity';
    if (env['CI'] == 'true') return 'other';
    return null;
  }

  /// Reads a `key=value` properties file, returning empty when missing.
  static Map<String, String> _readPropsFile(File? file) {
    if (file == null || !file.existsSync()) return const <String, String>{};
    final out = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#') || t.startsWith('!')) continue;
      final eq = t.indexOf('=');
      if (eq <= 0) continue;
      out[t.substring(0, eq).trim()] = t.substring(eq + 1).trim();
    }
    return out;
  }

  /// Detect Develocity (or its predecessor "Gradle Enterprise") via
  /// `settings.gradle{.kts}` plugin block or a user-global init script
  /// referencing the plugin id. Best-effort substring match.
  static bool _detectDevelocity(Directory? projectRoot, Directory? homeDir) {
    bool fileMentionsDevelocity(File f) {
      if (!f.existsSync()) return false;
      final content = f.readAsStringSync();
      return content.contains('com.gradle.develocity') ||
          content.contains('com.gradle.enterprise') ||
          content.contains('develocity {') ||
          content.contains('gradleEnterprise {');
    }

    if (projectRoot != null) {
      final candidates = <File>[
        File(p.join(projectRoot.path, 'android', 'settings.gradle')),
        File(p.join(projectRoot.path, 'android', 'settings.gradle.kts')),
      ];
      for (final f in candidates) {
        if (fileMentionsDevelocity(f)) return true;
      }
    }
    if (homeDir != null) {
      final initDir = Directory(p.join(homeDir.path, '.gradle', 'init.d'));
      if (initDir.existsSync()) {
        for (final entry in initDir.listSync()) {
          if (entry is File &&
              (entry.path.endsWith('.gradle') ||
                  entry.path.endsWith('.gradle.kts'))) {
            if (fileMentionsDevelocity(entry)) return true;
          }
        }
      }
    }
    return false;
  }

  static int _countInitScripts(Directory? homeDir) {
    if (homeDir == null) return 0;
    final initDir = Directory(p.join(homeDir.path, '.gradle', 'init.d'));
    if (!initDir.existsSync()) return 0;
    return initDir
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.gradle') || f.path.endsWith('.gradle.kts'),
        )
        .length;
  }

  static bool _detectCcache(Map<String, String> env) {
    final pathEnv = env['PATH'];
    if (pathEnv == null) return false;
    for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final candidate = File(p.join(dir, 'ccache'));
      if (candidate.existsSync()) return true;
    }
    return false;
  }
}
