import 'dart:convert';
import 'dart:io';

// Why does this exist?
//
// Dependabot handles action version bumps over time, but there's no
// first-party way to say "update my action versions right now." It runs
// on GitHub's schedule (daily/weekly) and can only be nudged via the
// "Check for updates" button in the UI. No `gh` subcommand, no local
// CLI — the closest is an experimental dependabot-cli in Go that isn't
// widely used, or third-party tools like pinact and renovate.
//
// Since `shorebird_ci generate` wants to emit current versions the
// moment a user runs it (not "eventually, after Dependabot catches
// up"), we need to do it ourselves: scan for `uses:` references, hit
// /releases/latest, resolve that tag to a commit, and rewrite the ref
// as `<sha> # <tag>`, the form Dependabot keeps updating afterwards.
//
// If GitHub (or anyone else) ships a proper CLI for this, delete this
// file and use that instead.

/// The action refs `generate` writes, each pinned to a commit with its
/// release tag in a trailing comment. A tag can be moved to new code by
/// whoever controls the action's repo; a commit can't. `generate` then
/// moves each to the action's latest release unless
/// `--no-update-actions` is passed.
const checkoutAction =
    'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1';

/// See [checkoutAction].
const setupDartAction =
    'dart-lang/setup-dart@6afc89df92d6eb3834022f73cd65adc8cdfcb92d # v1.8.1';

/// See [checkoutAction].
const pathsFilterAction =
    'dorny/paths-filter@ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d # v4.0.3';

/// See [checkoutAction].
const codecovAction =
    'codecov/codecov-action@303a32d7a59b442fa8d48b6a1cc6825c09c847a5 # v7.1.1';

/// See [checkoutAction].
const flutterAction =
    'subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2.23.0';

/// See [checkoutAction].
const setupBlocToolsAction =
    'felangel/setup-bloc-tools@7be2b47e63c845e5a92032c6ff2243f42cda65f3 # v0.1.1';

/// See [checkoutAction].
const cspellAction =
    'streetsidesoftware/cspell-action@ce1816e4ce36532956ac6e983737392774b6e169 # v9.2.0';

/// An action release: its tag (e.g. `'v5.1.0'`) and the commit [sha] the
/// tag points at.
class ActionRelease {
  /// Creates an [ActionRelease].
  const ActionRelease({required this.tag, required this.sha});

  /// The release's tag, e.g. `'v5.1.0'`.
  final String tag;

  /// The full 40-character commit SHA [tag] points at.
  final String sha;
}

/// Resolves the latest release of the action at `<owner>/<repo>` on
/// GitHub. Returns `null` if it can't be determined (network failure,
/// missing release, malformed tag, etc.).
typedef LatestReleaseResolver = Future<ActionRelease?> Function(String repo);

/// Scans [workflowContent] for GitHub Actions `uses:` references and
/// returns a copy with each pinned to its action's latest release, as
/// `owner/repo@<sha> # <tag>`.
///
/// Rewrites two forms:
/// - a version tag (`@v4`, `@v4.1.0`): pinned to the latest release
///   unless that release is older than the tag.
/// - a SHA pin with a version comment (`@<sha> # v4.1.0`): moved to the
///   latest release only if it's newer than the comment. A tag that was
///   moved to a different commit under the same version isn't followed.
///
/// A SHA pin without a version comment, a branch (`@main`) and a local
/// action (`./...`) are left alone, as are mentions of `owner/repo@vN` in
/// YAML comments or `run:` strings.
///
/// Queries GitHub's public API. If the lookup fails for a given action
/// (network down, not found, rate limited), its ref is left unchanged.
///
/// [resolveLatestRelease] is exposed for testing — production callers
/// should leave it `null` to use the default GitHub API resolver.
///
/// Returns the updated content. If nothing changed, the return value is
/// identical to the input.
Future<String> updateActionVersions(
  String workflowContent, {
  LatestReleaseResolver? resolveLatestRelease,
}) async {
  final matches = _usesRegex.allMatches(workflowContent).toList();
  if (matches.isEmpty) return workflowContent;

  final resolver = resolveLatestRelease ?? _defaultResolver;
  final latestByRepo = <String, ActionRelease?>{};
  for (final match in matches) {
    final repo = match.group(1)!;
    if (!latestByRepo.containsKey(repo)) {
      latestByRepo[repo] = await resolver(repo);
    }
  }

  // Replace at regex match positions only, so mentions in comments or
  // `run:` strings (e.g. `echo "see actions/checkout@v4"`) are left alone.
  return workflowContent.replaceAllMapped(_usesRegex, (match) {
    final whole = match.group(0)!;
    final repo = match.group(1)!;
    final latest = latestByRepo[repo];
    if (latest == null || _parseVersion(latest.tag) == null) return whole;
    final tag = match.group(2);
    final pinnedVersion = match.group(4);
    final cmp = _compareVersions(latest.tag, tag ?? pinnedVersion!);
    final update = tag != null ? cmp >= 0 : cmp > 0;
    if (!update) return whole;
    return 'uses: $repo@${latest.sha} # ${latest.tag}';
  });
}

/// Matches `uses: owner/repo@vN[.N...]`, or
/// `uses: owner/repo@<sha> # vN[.N...]`. Group 1 is the repo, group 2 the tag, groups 3 and 4 the
/// SHA and its version comment. Doesn't match `./` local actions,
/// branches, or SHA pins without a version comment.
final _usesRegex = RegExp(
  r'uses:\s+([a-zA-Z0-9_-][a-zA-Z0-9_.-]*/[a-zA-Z0-9_.-]+)@'
  r'(?:(v\d+(?:\.\d+)*)\b(?![.\w-])|'
  r'([0-9a-f]{40})[ \t]+#[ \t]*(v\d+(?:\.\d+)*)\b(?![.\w-]))',
);

List<int>? _parseVersion(String tag) {
  final match = RegExp(r'^v?(\d+(?:\.\d+)*)$').firstMatch(tag);
  return match?.group(1)!.split('.').map(int.parse).toList();
}

/// Compares two version tags, padding the shorter with zeros, so `v7`
/// sorts as `v7.0.0`.
int _compareVersions(String a, String b) {
  final va = _parseVersion(a)!;
  final vb = _parseVersion(b)!;
  for (var i = 0; i < va.length || i < vb.length; i++) {
    final x = i < va.length ? va[i] : 0;
    final y = i < vb.length ? vb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

// coverage:ignore-start
// Wraps the GitHub API calls and is exercised end-to-end by the
// `generate` workflow at runtime. The resolver indirection above lets
// tests cover the pinning logic without touching the network.
Future<ActionRelease?> _defaultResolver(String repo) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    return await _latestRelease(client, repo);
  } finally {
    client.close();
  }
}

Future<ActionRelease?> _latestRelease(HttpClient client, String repo) async {
  try {
    final release = await _get(
      client,
      'repos/$repo/releases/latest',
      accept: 'application/vnd.github+json',
    );
    if (release == null) return null;
    final json = jsonDecode(release) as Map<String, dynamic>;
    final tag = json['tag_name'] as String?;
    if (tag == null || _parseVersion(tag) == null) return null;

    // The `sha` media type returns the commit the ref resolves to, with
    // annotated tags peeled, as a bare 40-character string.
    final sha = (await _get(
      client,
      'repos/$repo/commits/${Uri.encodeComponent(tag)}',
      accept: 'application/vnd.github.sha',
    ))?.trim();
    if (sha == null || !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) return null;
    return ActionRelease(tag: tag, sha: sha);
  } on Exception {
    return null;
  }
}

Future<String?> _get(
  HttpClient client,
  String path, {
  required String accept,
}) async {
  final request = await client.getUrl(
    Uri.parse('https://api.github.com/$path'),
  );
  request.headers
    ..add('Accept', accept)
    ..add('User-Agent', 'shorebird_ci');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return response.statusCode == 200 ? body : null;
}

// coverage:ignore-end
