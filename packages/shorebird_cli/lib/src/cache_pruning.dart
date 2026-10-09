/// Shared pieces for pruning cached Flutter installs, engine artifacts and
/// previews that have gone unused.
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

/// How long a cached Flutter install, engine artifact or preview can go
/// unused before Shorebird removes it.
const unusedCacheMaxAge = Duration(days: 30);

/// Names the per-revision cache directories Shorebird owns: one per full git
/// revision. Anything else is never a pruning candidate.
final revisionDirectoryPattern = RegExp(r'^[0-9a-f]{40}$');

/// Records that [directory] was used just now.
void markUsed(Directory directory) =>
    touchStamp(File(p.join(directory.path, lastUsedStampName)));

/// Sets [stamp]'s mtime to now, creating it if needed.
///
/// Best effort: a use that goes unrecorded is at worst pruned and downloaded
/// again on its next use.
void touchStamp(File stamp) {
  try {
    stamp
      // A preview's use is recorded before its download creates the app's
      // directory.
      ..createSync(recursive: true)
      ..setLastModifiedSync(clock.now());
  } on FileSystemException catch (error) {
    logger.detail('Failed to record use in ${stamp.path}: $error');
  }
}

/// When [directory] was last used.
DateTime lastUsed(Directory directory) => stampedTime(
  stamp: File(p.join(directory.path, lastUsedStampName)),
  fallback: directory,
);

/// The time [stamp] records, or [fallback]'s mtime if there is no stamp.
///
/// Entries written by versions that predate these stamps have none, and their
/// own mtime approximates when they were created.
DateTime stampedTime({
  required File stamp,
  required FileSystemEntity fallback,
}) {
  final stat = stamp.statSync();
  if (stat.type != FileSystemEntityType.notFound) return stat.modified;
  return fallback.statSync().modified;
}

/// Whether something last used at [time] has gone unused for longer than
/// [unusedCacheMaxAge].
bool isUnusedSince(DateTime time) =>
    !time.isAfter(clock.now().subtract(unusedCacheMaxAge));

/// Whether [directory] is a per-revision cache directory that has gone unused
/// for longer than [unusedCacheMaxAge].
bool isUnusedRevisionDirectory(Directory directory) {
  if (!revisionDirectoryPattern.hasMatch(p.basename(directory.path))) {
    return false;
  }
  return isUnusedSince(lastUsed(directory));
}

/// Deletes [entity], returning whether it is gone.
///
/// A failure is logged rather than thrown: every caller is cleaning up, and
/// what it leaves behind is retried by a later sweep.
bool deleteIgnoringErrors(FileSystemEntity entity) {
  try {
    entity.deleteSync(recursive: true);
    return true;
  } on FileSystemException catch (error) {
    logger.detail('Failed to remove ${entity.path}: $error');
    return false;
  }
}
