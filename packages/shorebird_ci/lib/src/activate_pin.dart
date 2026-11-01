/// What a workflow's `dart pub global activate shorebird_ci` lines ask for.
class ActivatePins {
  /// Creates an [ActivatePins].
  const ActivatePins({required this.versions, required this.hasUnpinned});

  /// The versions named on activate lines, such as `0.2.5`.
  final Set<String> versions;

  /// Whether some activate line names no version at all, which leaves CI
  /// on whatever was published last.
  final bool hasUnpinned;
}

/// A version has to start with a digit, which is what keeps a flag such as
/// `--overwrite` from reading as one.
final _activateRegex = RegExp(
  r'''dart\s+pub\s+global\s+activate\s+shorebird_ci\b\s*([0-9][^\s'"]*)?''',
);

/// Reads the `dart pub global activate shorebird_ci <version>` lines out of
/// a workflow YAML file.
///
/// `generate` writes one such line per workflow, pinned to the version that
/// wrote it. Comparing it against the running version is what tells a
/// developer whether a local `verify` asks the same question CI will.
ActivatePins findActivatePins(String workflowContent) {
  final versions = <String>{};
  var hasUnpinned = false;
  for (final line in workflowContent.split('\n')) {
    // A commented-out activate line is not one CI runs.
    final code = line.split('#').first;
    final match = _activateRegex.firstMatch(code);
    if (match == null) continue;
    final version = match.group(1);
    if (version == null) {
      hasUnpinned = true;
    } else {
      versions.add(version);
    }
  }
  return ActivatePins(versions: versions, hasUnpinned: hasUnpinned);
}
