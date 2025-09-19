import 'dart:io';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Helpers for selecting the application executable from a Windows release
/// directory.
///
/// Selection prefers [projectName] when provided; otherwise falls back to the
/// first `.exe` found. Only top-level files in the directory are considered
/// (non-recursive).
bool _pathMatchesName(String path, String projectName) =>
    // Treat both `<name>.exe` and `<name>_win64.exe` as exact matches.
    // The `_win64` variant is included for compatibility with some naming
    // schemes; if unused in your builds, it simply won't match.
    p.basename(path) == '$projectName.exe';

/// Returns the selected application `.exe` from [releaseDir].
///
/// Selection order when [projectName] is provided:
/// 1) exact match on `<projectName>.exe`
/// 2) first basename containing `<projectName>`
/// 3) first `.exe`
///
/// When [projectName] is null, returns the first `.exe`.
/// Only top-level files in [releaseDir] are considered (non-recursive).
File windowsAppExe(Directory releaseDir, {String? projectName}) {
  final exes = releaseDir
      .listSync()
      .whereType<File>()
      .where((f) => p.extension(f.path).toLowerCase() == '.exe')
      .toList();
  if (exes.isEmpty) {
    throw Exception('No .exe found in release artifact');
  }
  
  if (projectName == null) {
    return exes.first;
  }

  final exactMatch = exes.firstWhereOrNull(
    (f) => _pathMatchesName(f.path, projectName),
  );

  if (exactMatch != null) {
    return exactMatch;
  }

  final fuzzyMatch = exes.firstWhereOrNull(
    (f) => p.basename(f.path).contains(projectName),
  );

  if (fuzzyMatch != null) {
    return fuzzyMatch;
  }

  return exes.first;
}
