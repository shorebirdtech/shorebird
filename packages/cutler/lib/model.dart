enum Repo {
  shorebird(
    name: 'shorebird',
    path: '_shorebird/shorebird',
    releaseBranch: 'origin/stable',
    upstreamBranch: 'origin/main',
  ),
  flutter(
    name: 'flutter',
    path: 'flutter',
    releaseBranch: 'origin/stable',
    upstreamBranch: 'upstream/stable',
  ),
  engine(
    name: 'engine',
    path: 'engine/src/flutter',
    releaseBranch: 'origin/stable_codepush',
    upstreamBranch: 'upstream/master',
  ),
  buildroot(
    name: 'buildroot',
    path: 'engine/src',
    releaseBranch: 'origin/stable_codepush',
    upstreamBranch: 'upstream/master',
  );

  const Repo(
      {required this.name,
      required this.path,
      required this.releaseBranch,
      required this.upstreamBranch});

  final String name;
  final String path;
  final String releaseBranch;
  final String upstreamBranch;
}

class Version {
  final String hash;
  final List<String> aliases;
  final Repo repo;
  const Version(
      {required this.hash, required this.repo, this.aliases = const []});

  String get ref => aliases.isEmpty ? hash : aliases.first;

  @override
  String toString() {
    final aliasesString = aliases.isEmpty ? "" : " (${aliases.join(', ')})";
    return "$hash$aliasesString";
  }

  @override
  bool operator ==(Object other) {
    if (other is! Version) {
      return false;
    }
    return other.hash == hash && other.repo == repo;
  }

  @override
  int get hashCode => hash.hashCode ^ repo.hashCode;
}

class VersionSet {
  final Version engine;
  final Version flutter;
  final Version buildroot;

  Version operator [](Repo repo) => {
        Repo.engine: engine,
        Repo.flutter: flutter,
        Repo.buildroot: buildroot,
      }[repo]!;

  const VersionSet(
      {required this.engine, required this.flutter, required this.buildroot});

  VersionSet copyWith({Version? engine, Version? flutter, Version? buildroot}) {
    return VersionSet(
      engine: engine ?? this.engine,
      flutter: flutter ?? this.flutter,
      buildroot: buildroot ?? this.buildroot,
    );
  }
}
