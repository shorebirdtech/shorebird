import 'package:collection/collection.dart';

/// Maps file paths to SHA-256 hash digests.
typedef PathHashes = Map<String, String>;

/// Sets of [PathHashes] that represent changes between two sets of files.
class FileSetDiff {
  FileSetDiff({
    required this.addedPaths,
    required this.removedPaths,
    required this.changedPaths,
  });

  /// Creates a [FileSetDiff] showing added, changed, and removed file sets
  factory FileSetDiff.fromPathHashes({
    required PathHashes oldPathHashes,
    required PathHashes newPathHashes,
  }) {
    final oldPaths = oldPathHashes.keys.toSet();
    final newPaths = newPathHashes.keys.toSet();
    return FileSetDiff(
      addedPaths: newPaths.difference(oldPaths),
      removedPaths: oldPaths.difference(newPaths),
      changedPaths: oldPaths
          .intersection(newPaths)
          .where((name) => oldPathHashes[name] != newPathHashes[name])
          .toSet(),
    );
  }

  FileSetDiff.empty()
      : addedPaths = {},
        removedPaths = {},
        changedPaths = {};

  /// File paths that were added.
  final Set<String> addedPaths;

  /// File paths that were removed.
  final Set<String> removedPaths;

  /// File paths that were changed.
  final Set<String> changedPaths;

  Set<String> get allPaths => {
        ...addedPaths,
        ...removedPaths,
        ...changedPaths,
      };

  /// Whether all path sets are empty.
  bool get isEmpty => !isNotEmpty;

  /// Whether any files were added, changed, or removed.
  bool get isNotEmpty =>
      addedPaths.isNotEmpty ||
      removedPaths.isNotEmpty ||
      changedPaths.isNotEmpty;

  /// A printable string representation of this [FileSetDiff].
  String get prettyString => [
        if (addedPaths.isNotEmpty)
          _prettyFileSetString(title: 'Added files', paths: addedPaths),
        if (changedPaths.isNotEmpty)
          _prettyFileSetString(title: 'Changed files', paths: changedPaths),
        if (removedPaths.isNotEmpty)
          _prettyFileSetString(title: 'Removed files', paths: removedPaths),
      ].join('\n');

  static String _prettyFileSetString({
    required String title,
    required Set<String> paths,
  }) {
    const padding = '    ';
    return '''
$padding$title:
${paths.sorted().map((p) => '${padding * 2}$p').join('\n')}''';
  }
}
