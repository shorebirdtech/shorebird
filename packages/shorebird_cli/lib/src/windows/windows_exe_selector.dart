import 'dart:io';
import 'package:path/path.dart' as p;

/// Selects the most likely application executable from a Windows release
/// directory.
///
/// Selects the application executable by preferring matches based on
/// [projectName]. Falls back to the first `.exe` to preserve legacy
/// behavior when no projectName match is found.
File selectWindowsAppExe(
  Directory releaseDir, {
  String? projectName,
}) {
  final exes = releaseDir
      .listSync()
      .whereType<File>()
      .where((f) => p.extension(f.path).toLowerCase() == '.exe')
      .toList();

  if (exes.isEmpty) {
    throw Exception('No .exe found in release artifact');
  }

  final candidates = exes;

  if (projectName != null && projectName.trim().isNotEmpty) {
    final name = projectName.toLowerCase();

    File? exact;
    File? contains;

    for (final f in candidates) {
      final base = p.basename(f.path).toLowerCase();
      if (base == '$name.exe') {
        exact = f;
        break;
      }
      if (base.contains(name)) {
        contains ??= f;
      }
    }

    if (exact != null) return exact;
    if (contains != null) return contains;
  }

  return candidates.first;
}
