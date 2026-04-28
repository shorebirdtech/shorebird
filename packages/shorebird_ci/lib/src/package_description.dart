import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A description of a Dart package discovered in a repository.
@immutable
class PackageDescription {
  /// Creates a [PackageDescription].
  const PackageDescription({required this.name, required this.rootPath});

  /// The name of the package from pubspec.yaml.
  final String name;

  /// The absolute path to the root directory of the package.
  final String rootPath;

  /// The root directory of the package.
  Directory get root => Directory(rootPath);

  /// Whether the given [path] is within the package's directory structure.
  bool containsPath(String path) => p.isWithin(rootPath, path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackageDescription &&
          name == other.name &&
          rootPath == other.rootPath;

  @override
  int get hashCode => Object.hash(name, rootPath);
}
