import 'dart:io';

import 'package:shorebird_ci/src/package_description.dart';

/// A description of a Dart/Flutter repository's structure.
class RepositoryDescription {
  /// Creates a [RepositoryDescription].
  RepositoryDescription({
    required this.packages,
    required this.root,
    required this.hasCodecov,
    this.hasSubmodules = false,
    this.cspellConfig,
  });

  /// The packages in the repository.
  final List<PackageDescription> packages;

  /// The root directory of the repository.
  final Directory root;

  /// Whether the repository has codecov configured.
  final bool hasCodecov;

  /// Whether the repository has git submodules (`.gitmodules`).
  final bool hasSubmodules;

  /// The cspell configuration file, if one exists.
  final File? cspellConfig;
}
