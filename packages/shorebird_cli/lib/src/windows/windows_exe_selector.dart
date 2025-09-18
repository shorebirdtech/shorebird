import 'dart:io';
import 'package:path/path.dart' as p;

/// Selects the most likely application executable from a Windows release
/// directory.
///
/// Selects the application executable by preferring matches based on
/// [projectNameHint]. Falls back to the first `.exe` to preserve legacy
/// behavior when no hint match is found.
File selectWindowsAppExe(
  Directory releaseDir, {
  String? projectNameHint,
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

  if (projectNameHint != null && projectNameHint.trim().isNotEmpty) {
    final hint = projectNameHint.toLowerCase();

    File? exact;
    File? contains;

    for (final f in candidates) {
      final base = p.basename(f.path).toLowerCase();
      if (base == '$hint.exe' || base == '${hint}_win64.exe') {
        exact = f;
        break;
      }
      if (base.contains(hint)) {
        contains ??= f;
      }
    }

    if (exact != null) return exact;
    if (contains != null) return contains;
  }

  return candidates.first;
}
