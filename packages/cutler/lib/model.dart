import 'package:meta/meta.dart';

enum Repo {
  shorebird(
    name: 'shorebird',
    path: '_shorebird/shorebird',
    url: 'https://github.com/shorebirdtech/shorebird.git',
    upstreamBranch: 'origin/main',
  ),
  flutter(
    name: 'flutter',
    path: 'flutter',
    url: 'https://github.com/shorebirdtech/flutter.git',
    upstreamBranch: 'upstream/stable',
  ),
  engine(
    name: 'engine',
    path: 'engine/src/flutter',
    url: 'https://github.com/shorebirdtech/engine.git',
    upstreamBranch: 'upstream/master',
  ),
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

  final String name;
  final String path;
  final String url;
  final String upstreamBranch;
}

@immutable
class Version {
  const Version({
    required this.hash,
    required this.repo,
    this.aliases = const [],
  });

  final String hash;
  final List<String> aliases;
  final Repo repo;

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

class VersionSet {
  const VersionSet({
    required this.engine,
    required this.flutter,
    required this.buildroot,
  });
  final Version engine;
  final Version flutter;
  final Version buildroot;

  Version operator [](Repo repo) => {
        Repo.engine: engine,
        Repo.flutter: flutter,
        Repo.buildroot: buildroot,
      }[repo]!;

  VersionSet copyWith({Version? engine, Version? flutter, Version? buildroot}) {
    return VersionSet(
      engine: engine ?? this.engine,
      flutter: flutter ?? this.flutter,
      buildroot: buildroot ?? this.buildroot,
    );
  }
}
