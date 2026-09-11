import 'dart:io';

import 'package:shorebird_ci/src/package_description.dart';

/// A description of a Dart/Flutter repository's structure.
class RepositoryDescription {
  /// Creates a [RepositoryDescription].
  RepositoryDescription({
    required this.packages,
    required this.root,
    required this.hasCodecov,
    this.cspellConfig,
  });

  /// The packages in the repository.
  final List<PackageDescription> packages;

  /// The root directory of the repository.
  final Directory root;

  /// Whether the repository has codecov configured.
  final bool hasCodecov;

  /// The cspell configuration file, if one exists.
  final File? cspellConfig;
}
