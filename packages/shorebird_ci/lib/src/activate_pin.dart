/// What a workflow's `dart pub global activate shorebird_ci` lines ask for.
class ActivatePins {
  /// Creates an [ActivatePins].
  const ActivatePins({required this.versions, required this.hasUnpinned});

  /// The exact versions named on activate lines, such as `0.2.5`.
  final Set<String> versions;

  /// Whether some activate line names no exact version, which leaves CI on
  /// whatever a constraint resolves to at the time the job runs.
  final bool hasUnpinned;
}

final _activateRegex = RegExp(r'dart\s+pub\s+global\s+activate\s+(.*)$');

/// An exact version, as `pub global activate` takes one. A constraint
/// (`^0.2.5`) is deliberately not one: it leaves CI free to resolve to
/// something the developer is not running, which is what the comparison
/// exists to catch rather than to assert.
final _exactVersionRegex = RegExp(r'^\d[\w.+-]*$');

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

    // Flags may sit on either side of the package name, and the version is
    // whatever argument follows it. Quotes are the author's, not pub's.
    final args = [
      for (final arg in match.group(1)!.trim().split(RegExp(r'\s+')))
        if (!arg.startsWith('-')) _unquote(arg),
    ];
    final at = args.indexOf('shorebird_ci');
    if (at < 0) continue;

    final version = at + 1 < args.length ? args[at + 1] : null;
    if (version != null && _exactVersionRegex.hasMatch(version)) {
      versions.add(version);
    } else {
      hasUnpinned = true;
    }
  }
  return ActivatePins(versions: versions, hasUnpinned: hasUnpinned);
}

String _unquote(String arg) {
  for (final quote in const ['"', "'"]) {
    if (arg.length > 1 && arg.startsWith(quote) && arg.endsWith(quote)) {
      return arg.substring(1, arg.length - 1);
    }
  }
  return arg;
}
