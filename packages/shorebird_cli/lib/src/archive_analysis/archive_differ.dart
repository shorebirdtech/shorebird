import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';

/// Thrown when an [ArchiveDiffer] fails to generate a [FileSetDiff].
class DiffFailedException implements Exception {}

/// Computes content differences between two archives.
abstract class ArchiveDiffer {
  /// Files that have been added, removed, or that have changed between the
  /// archives at the two provided paths.
  FileSetDiff changedFiles(String oldArchivePath, String newArchivePath);

  /// Whether there are asset differences between the archives that may cause
  /// issues when patching a release.
  bool containsPotentiallyBreakingAssetDiffs(FileSetDiff fileSetDiff);

  /// Whether there are native code differences between the archives that may
  /// cause issues when patching a release.
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff);
}
