import 'package:meta/meta.dart';

/// Configuration information for each of our repos.
enum Repo {
  /// Repo configuration representing the Shorebird repo.
  shorebird(
    name: 'shorebird',
    path: '_shorebird/shorebird',
    url: 'https://github.com/shorebirdtech/shorebird.git',
    upstreamBranch: 'origin/main',
  ),

  /// Repo configuration representing the Flutter repo.
  flutter(
    name: 'flutter',
    path: 'flutter',
    url: 'https://github.com/shorebirdtech/flutter.git',
    upstreamBranch: 'upstream/stable',
  ),

  /// Repo configuration representing the engine repo.
  engine(
    name: 'engine',
    path: 'engine/src/flutter',
    url: 'https://github.com/shorebirdtech/engine.git',
    upstreamBranch: 'upstream/master',
  ),

  /// Repo configuration representing the buildroot repo.
  buildroot(
    name: 'buildroot',
    path: 'engine/src',
    url: 'https://github.com/shorebirdtech/builddoor.git',
    upstreamBranch: 'upstream/master',
  );

  const Repo({
    required this.name,
    required this.path,
    required this.url,
    required this.upstreamBranch,
  });

  /// Returns the name (e.g. 'engine') of the repo.
  final String name;

  /// Returns the path (e.g. 'engine/src/flutter') of the repo.
  final String path;

  /// Returns the URL the repo is cloned from.
  final String url;

  /// Returns the name of the upstream branch.
  final String upstreamBranch;
}

/// Paths to version files in each repo.
enum Paths {
  /// Path to the engine DEPS file in the engine repo.
  engineDEPS('DEPS'),

  /// Path to the flutter engine version file in the flutter repo.
  flutterEngineVersion('bin/internal/engine.version'),

  /// Path to the flutter version file in the shorebird repo.
  shorebirdFlutterVersion('bin/internal/flutter.version');

  const Paths(this.path);

  /// Returns the path (e.g. 'DEPS') of the file.
  final String path;
}

/// An object to pair a [hash] with a [repo].
@immutable
class Version {
  /// Constructs a new [Version] object for a given [hash] and [repo]
  /// with optionally provided [aliases] for the hash (typically tag names).
  const Version({
    required this.hash,
    required this.repo,
    this.aliases = const [],
  });

  /// The hash of the version.
  final String hash;

  /// Aliaes for the hash (typically tag names).
  final List<String> aliases;

  /// The repo the version is from.
  final Repo repo;

  /// Returns the first alias for the hash, or the hash if there are no aliases.
  String get ref => aliases.isEmpty ? hash : aliases.first;

  @override
  String toString() {
    final aliasesString = aliases.isEmpty ? '' : " (${aliases.join(', ')})";
    return '$hash$aliasesString';
  }

  @override
  bool operator ==(Object other) {
    if (other is! Version) {
      return false;
    }
    return other.hash == hash && other.repo == repo;
  }

  @override
  int get hashCode => Object.hashAll([hash, repo]);
}

/// An object to hold a set of versions that make up a Flutter release.
class VersionSet {
  /// Constructs a new [VersionSet] with a given [engine], [flutter], and
  /// [buildroot] version.
  const VersionSet({
    required this.engine,
    required this.flutter,
    required this.buildroot,
  });

  /// The engine version.
  final Version engine;

  /// The flutter version.
  final Version flutter;

  /// The buildroot version.
  final Version buildroot;

  /// Returns the version for a given [repo].
  Version operator [](Repo repo) => {
        Repo.engine: engine,
        Repo.flutter: flutter,
        Repo.buildroot: buildroot,
      }[repo]!;

  /// Copies the VersionSet replacing any provided values.
  VersionSet copyWith({Version? engine, Version? flutter, Version? buildroot}) {
    return VersionSet(
      engine: engine ?? this.engine,
      flutter: flutter ?? this.flutter,
      buildroot: buildroot ?? this.buildroot,
    );
  }
}
