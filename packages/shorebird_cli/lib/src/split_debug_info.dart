import 'package:path/path.dart' as p;

/// Where Shorebird puts Dart program symbols when it adds `--split-debug-info`
/// on the user's behalf.
final defaultSplitDebugInfoPath = p.join('build', 'shorebird', 'symbols');

/// The `--split-debug-info` argument to add to a Flutter build, or null if
/// none is needed.
///
/// Flutter requires `--split-debug-info` with `--obfuscate`, so when
/// [obfuscate] is true and the user hasn't set it ([hasSplitDebugInfo]), this
/// returns one pointing at [defaultSplitDebugInfoPath]. Releases and patches
/// both use this, so a patch's symbols land where its release's did.
String? splitDebugInfoDefault({
  required bool obfuscate,
  required bool hasSplitDebugInfo,
}) {
  if (!obfuscate || hasSplitDebugInfo) return null;
  return '--split-debug-info=$defaultSplitDebugInfoPath';
}
