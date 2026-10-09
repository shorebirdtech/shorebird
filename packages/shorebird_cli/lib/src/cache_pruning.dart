/// Shared pieces for pruning per-revision cache directories that have gone
/// unused.
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/logging/logging.dart';

/// Marker whose modification time records when a cached, per-revision
/// directory (a Flutter install, or an engine revision's artifacts) was last
/// used.
///
/// Untracked in a Flutter checkout, and `git status` is run there with
/// `--untracked-files=no`, so its presence does not make the checkout look
/// dirty.
const lastUsedStampName = '.shorebird_last_used';

/// How long a per-revision cache directory can go unused before Shorebird
/// removes it.
const unusedCacheMaxAge = Duration(days: 30);

/// Names the per-revision cache directories Shorebird owns: one per full git
/// revision. Anything else is never a pruning candidate.
final revisionDirectoryPattern = RegExp(r'^[0-9a-f]{40}$');

/// Records that [directory] was used just now.
///
/// Best effort: a directory whose use goes unrecorded is at worst pruned and
/// downloaded again on its next use.
void markUsed(Directory directory) {
  try {
    File(p.join(directory.path, lastUsedStampName))
      ..createSync()
      ..setLastModifiedSync(clock.now());
  } on FileSystemException catch (error) {
    logger.detail('Failed to record use of ${directory.path}: $error');
  }
}

/// When [directory] was last used.
///
/// Directories written by versions that predate [lastUsedStampName] fall back
/// to their own mtime, which approximates when they were created.
DateTime lastUsed(Directory directory) {
  final stamp = File(p.join(directory.path, lastUsedStampName)).statSync();
  if (stamp.type != FileSystemEntityType.notFound) return stamp.modified;
  return directory.statSync().modified;
}

/// Whether [directory] is a per-revision cache directory that has gone unused
/// for longer than [unusedCacheMaxAge].
bool isUnusedRevisionDirectory(Directory directory) {
  if (!revisionDirectoryPattern.hasMatch(p.basename(directory.path))) {
    return false;
  }
  final cutoff = clock.now().subtract(unusedCacheMaxAge);
  return !lastUsed(directory).isAfter(cutoff);
}

/// Deletes [directory], returning whether it is gone.
///
/// A failure is logged rather than thrown: every caller is cleaning up, and
/// what it leaves behind is retried by a later sweep.
bool deleteIgnoringErrors(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
    return true;
  } on FileSystemException catch (error) {
    logger.detail('Failed to remove ${directory.path}: $error');
    return false;
  }
}
