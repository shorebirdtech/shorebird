import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The workspace files every package's checks read: the workspace list and
/// SDK constraint, the resolved version of every hosted and git dependency,
/// and the lints most packages include.
const workspaceInputs = [
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
];

/// The paths, relative to [root], that format, analyze and test of the Dart
/// package at [package] read, sorted.
///
/// - [package] itself.
/// - Every package it reaches through `path:` dependencies, or through a
///   dependency named for a member of the root pubspec's `workspace:` list,
///   which pub resolves to that member whatever version it asks for,
///   transitively. Its own `dev_dependencies` count, since its tests import
///   them; theirs do not.
/// - [workspaceInputs]. Hosted and git dependencies are in `pubspec.lock`.
/// - What its pubspec lists under `verify_cache: inputs:`, relative to
///   [package]. That is for a test that reads a file outside its package,
///   such as a golden kept beside the TypeScript that also reads it. Nothing
///   finds those reads for you: a test reading an unlisted path passes from
///   the cache after that path changes, until CI, which caches nothing,
///   fails it.
///
/// Throws a [FormatException] when a pubspec does not parse, or a path it
/// names is outside [root].
List<String> dartPackageInputs(String root, String package) {
  String inRoot(String from, String path) {
    final resolved = p.normalize(p.join(from, path));
    if (resolved == '..' || resolved.startsWith('../') || p.isAbsolute(path)) {
      throw FormatException('$path, from $from, is outside $root');
    }
    return resolved;
  }

  final start = inRoot('.', package);
  final members = _workspaceMembers(root, inRoot);
  final inputs = <String>{...workspaceInputs, start};
  final queue = [start];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    final pubspec = _pubspec(root, current);
    final sections = ['dependencies', if (current == start) 'dev_dependencies'];
    for (final section in sections) {
      final dependencies = pubspec[section];
      if (dependencies is! YamlMap) continue;
      for (final MapEntry(key: name, value: spec) in dependencies.entries) {
        final String? dependency;
        if (spec is YamlMap && spec['path'] is String) {
          dependency = inRoot(current, spec['path'] as String);
        } else {
          dependency = members[name];
        }
        if (dependency != null && inputs.add(dependency)) {
          queue.add(dependency);
        }
      }
    }
  }

  final config = _pubspec(root, start)['verify_cache'];
  final extra = config is YamlMap ? config['inputs'] : null;
  if (extra is YamlList) {
    for (final path in extra) {
      inputs.add(inRoot(start, '$path'));
    }
  }
  return inputs.toList()..sort();
}

/// The root pubspec's `workspace:` members, by package name.
Map<String, String> _workspaceMembers(
  String root,
  String Function(String from, String path) inRoot,
) {
  final workspace = _pubspec(root, '.')['workspace'];
  if (workspace is! YamlList) return const {};
  return {
    for (final path in workspace)
      if (_pubspec(root, inRoot('.', '$path'))['name'] case final String name)
        name: inRoot('.', '$path'),
  };
}

YamlMap _pubspec(String root, String package) {
  final file = File(p.join(root, package, 'pubspec.yaml'));
  if (!file.existsSync()) return YamlMap();
  final yaml = loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
  if (yaml is! YamlMap) {
    throw FormatException('${file.path} is not a map');
  }
  return yaml;
}
