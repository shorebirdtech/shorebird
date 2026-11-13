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
    this.ciConfig = const RepositoryCiConfig(),
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

  /// Repository-wide CI configuration declared in the root `pubspec.yaml`.
  final RepositoryCiConfig ciConfig;
}

/// Declarative repository-wide CI configuration from `shorebird_ci:` in
/// the repository root's `pubspec.yaml`.
///
/// Each key mirrors a `generate` flag whose value is a choice about the
/// repository rather than a fact `generate` can read out of it. Declaring
/// them here is what lets `verify` rebuild the workflows `generate`
/// writes: a flag passed on the command line leaves nothing behind, so
/// the next regeneration drops it and no check notices.
class RepositoryCiConfig {
  /// Creates a [RepositoryCiConfig].
  const RepositoryCiConfig({
    this.emitRequiredJob = false,
    this.fatalInfos = false,
    this.codecovTokenSecret,
  });

  /// Whether to emit the `required` aggregator job. Mirrors `--required`.
  final bool emitRequiredJob;

  /// Whether analyze steps pass `--fatal-infos` rather than
  /// `--fatal-warnings`. Mirrors `--fatal-infos`.
  final bool fatalInfos;

  /// Name of the Actions secret holding the Codecov upload token.
  /// Mirrors `--codecov-token-secret`.
  final String? codecovTokenSecret;
}
