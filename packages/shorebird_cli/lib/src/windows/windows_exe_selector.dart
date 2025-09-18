import 'dart:io';
import 'package:path/path.dart' as p;

/// Selects the most likely application executable from a Windows release
/// directory.
///
/// Excludes known helper binaries (e.g. crashpad handlers) and selects the
/// application executable. When multiple candidates remain, uses
/// [projectNameHint] to break ties; otherwise falls back to the first `.exe`
/// to preserve legacy behavior.
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

  const excludedNames = <String>{
    'crashpad_handler.exe',
    'crashpad_wer.exe',
    'dump_syms.exe',
    'symupload.exe',
    'flutter_tester.exe',
  };

  var candidates = exes
      .where((f) => !excludedNames.contains(p.basename(f.path).toLowerCase()))
      .toList();

  if (candidates.isEmpty) {
    candidates = exes;
  }

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
