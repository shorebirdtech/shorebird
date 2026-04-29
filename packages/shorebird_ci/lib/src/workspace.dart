import 'dart:io';

import 'package:shorebird_ci/src/pubspec.dart';

/// Workspace detection for Dart packages.
///
/// A Dart workspace is a pubspec.yaml that lists members under a
/// `workspace:` key. Members opt in by setting `resolution: workspace`
/// in their own pubspec, after which their dependencies are resolved
/// against the workspace root rather than per-package.

/// Whether the pubspec at [packageDir] declares a workspace via a
/// non-empty `workspace:` list.
bool isDartWorkspace(String packageDir) {
  final pubspec = readPubspec(packageDir);
  if (pubspec == null) return false;
  final workspace = pubspec['workspace'];
  return workspace is List && workspace.isNotEmpty;
}

/// Whether the pubspec at [packageDir] is a workspace "stub" root
/// that should be skipped during package discovery.
///
/// Convention: a workspace root with no name or a name starting with
/// `_` (e.g., shorebird's `name: _`) is just a grouping mechanism
/// and isn't itself a package to test.
bool isWorkspaceStubRoot(String packageDir) {
  if (!isDartWorkspace(packageDir)) return false;
  final name = readPubspec(packageDir)?['name'] as String?;
  return name == null || name.startsWith('_');
}

/// Whether the pubspec at [packageDir] uses workspace resolution
/// (`resolution: workspace`).
bool usesWorkspaceResolution(String packageDir) {
  final pubspec = readPubspec(packageDir);
  return pubspec?['resolution'] == 'workspace';
}

/// Walks up from [packageDir] looking for the nearest ancestor whose
/// pubspec.yaml declares a non-empty `workspace:` list. Returns the
/// containing directory, or `null` if no workspace root is found.
Directory? findWorkspaceRoot(String packageDir) {
  var dir = Directory(packageDir);
  Directory? prev;
  while (prev?.path != dir.path) {
    if (isDartWorkspace(dir.path)) return dir;
    prev = dir;
    dir = dir.parent;
  }
  return null;
}
