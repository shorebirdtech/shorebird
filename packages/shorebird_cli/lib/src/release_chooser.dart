import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// The maximum number of releases to display before offering to show all.
const maxDisplayedReleases = 10;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Sentinel release used to represent the "Show all releases" option.
///
/// We use a sentinel rather than `null` because `chooseOne` internally
/// performs a null check and does not support nullable types.
@visibleForTesting
final showAllReleaseSentinel = Release(
  id: -1,
  appId: '',
  version: '',
  flutterRevision: '',
  flutterVersion: null,
  displayName: null,
  platformStatuses: const {},
  createdAt: DateTime(0),
  updatedAt: DateTime(0),
);

/// Formats a [DateTime] as "Mon DD" (e.g. "Jan 28").
///
/// Could be replaced with `DateFormat('MMM d').format(date)` from
/// `package:intl` if we ever add that dependency.
String formatReleaseDate(DateTime date) {
  return '${_months[date.month - 1]} ${date.day}';
}

/// Formats a release for display in the chooser.
///
/// The [showAllReleaseSentinel] is rendered as "Show all N releases...".
String formatReleaseDisplay(Release r, {required int totalCount}) {
  if (identical(r, showAllReleaseSentinel)) {
    return '\u2193 Show all $totalCount releases...';
  }
  return '${r.version}  (${formatReleaseDate(r.createdAt)})';
}

/// Prompts the user to choose a release from [releases].
///
/// Releases are sorted by [Release.createdAt] descending (newest first).
/// If there are more than [maxDisplayedReleases], only the most recent
/// are shown initially with an option to show all.
///
/// The [action] parameter is used in the prompt message, e.g. "patch",
/// "preview", or "generate an apk for".
Release chooseRelease({
  required Iterable<Release> releases,
  required String action,
}) {
  final sorted = releases.sortedBy((r) => r.createdAt).reversed.toList();
  final prompt = 'Which release would you like to $action?';
  String display(Release r) =>
      formatReleaseDisplay(r, totalCount: sorted.length);

  if (sorted.length == 1) {
    logger.info('Using release ${display(sorted.single)}');
    return sorted.single;
  }

  // Only truncate when it actually saves lines (sentinel takes a line too).
  if (sorted.length > maxDisplayedReleases + 1) {
    final truncated = [
      ...sorted.take(maxDisplayedReleases),
      showAllReleaseSentinel, // "Show all releases..." option.
    ];

    final choice = logger.chooseOne<Release>(
      prompt,
      choices: truncated,
      display: display,
    );

    if (!identical(choice, showAllReleaseSentinel)) return choice;
  }

  return logger.chooseOne<Release>(
    prompt,
    choices: sorted,
    display: display,
  );
}
