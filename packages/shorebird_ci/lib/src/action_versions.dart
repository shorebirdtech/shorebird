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
/// - a version tag (`@v4`, `@v4.1.0`, `@2`): pinned to the commit the
///   latest release points at now, unless that release is older than the
///   tag.
/// - a SHA pin with a version comment (`@<sha> # v4.1.0`): moved to the
///   latest release only if it's newer than the comment, compared at the
///   comment's precision (`# v5` moves to v6.0.0, not v5.0.1). The same
///   version resolving to a different commit (a moved tag) isn't
///   followed. This doesn't vet a new release itself: Dependabot's
///   cooldown and review of its PR are what catch a malicious release.
///
/// A SHA pin without a version comment, a branch (`@main`), a local
/// action (`./...`), a ref with anything but a comment after it on the
/// line (YAML flow style), and `uses:` text that doesn't start its line
/// (inside comments or `run:` strings) are left alone. Use
/// [unpinnedActionRefs] to list what's still on a tag afterwards.
///
/// Queries GitHub's public API. If the lookup fails for a given action
/// (network down, no GitHub release, rate limited), its ref is left
/// unchanged.
///
/// [resolveLatestRelease] is exposed for testing — production callers
/// should leave it `null` to use the default GitHub API resolver, which
/// remembers each repo's answer for the life of the process, so one run
/// over several files looks each action up once.
///
/// Returns the updated content. If nothing changed, the return value is
/// identical to the input.
Future<String> updateActionVersions(
  String workflowContent, {
  LatestReleaseResolver? resolveLatestRelease,
}) async {
  final matches = _usesRegex.allMatches(workflowContent).toList();
  if (matches.isEmpty) return workflowContent;

  final resolver = resolveLatestRelease ?? _cachedDefaultResolver;
  final latestByRepo = <String, ActionRelease?>{};
  for (final match in matches) {
    final repo = match.namedGroup('repo')!;
    if (!latestByRepo.containsKey(repo)) {
      latestByRepo[repo] = await resolver(repo);
    }
  }

  return workflowContent.replaceAllMapped(_usesRegex, (m) {
    final match = m as RegExpMatch;
    final whole = match.group(0)!;
    final latest = latestByRepo[match.namedGroup('repo')!];
    final latestVersion = latest == null ? null : _parseVersion(latest.tag);
    if (latestVersion == null) return whole;
    final tag = match.namedGroup('tag');
    final current = _parseVersion(tag ?? match.namedGroup('pinned')!);
    if (current == null) return whole;
    final update = tag != null
        ? _compare(latestVersion, current) >= 0
        : _compare(latestVersion.take(current.length).toList(), current) > 0;
    if (!update) return whole;
    final action = '${match.namedGroup('repo')}${match.namedGroup('path')}';
    return '${match.namedGroup('prefix')}$action@${latest!.sha} '
        '# ${latest.tag}';
  });
}

/// The `uses:` refs in [workflowContent] that aren't pinned to a commit
/// SHA, e.g. `actions/checkout@v4`. Local actions and `docker://` images
/// aren't listed.
List<String> unpinnedActionRefs(String workflowContent) => [
  for (final match in _anyUsesRegex.allMatches(workflowContent))
    if (!RegExp(r'@[0-9a-f]{40}$').hasMatch(match.group(1)!) &&
        !match.group(1)!.startsWith('./') &&
        !match.group(1)!.startsWith('docker://'))
      match.group(1)!,
];

final _anyUsesRegex = RegExp(
  r'''^[ \t]*(?:-[ \t]+)?uses:[ \t]+["']?([^\s"'#]+)''',
  multiLine: true,
);

/// Matches a `uses:` line whose ref is `owner/repo[/path]@<version tag>`
/// or `owner/repo[/path]@<sha> # <version>`, followed by nothing but an
/// optional comment. The value may be quoted.
final _usesRegex = RegExp(
  r'''(?<prefix>^[ \t]*(?:-[ \t]+)?uses:[ \t]+)(?<q>["']?)'''
  '(?<repo>[a-zA-Z0-9_-][a-zA-Z0-9_.-]*/[a-zA-Z0-9_.-]+)'
  '(?<path>(?:/[a-zA-Z0-9_.-]+)*)@'
  r'(?:(?<sha>[0-9a-f]{40})\k<q>[ \t]+#[ \t]*(?<pinned>v?\d+(?:\.\d+)*)'
  r'|(?<tag>v?\d+(?:\.\d+)*)\k<q>)'
  r'(?=[ \t]*(?:#[^\r\n]*)?\r?$)',
  multiLine: true,
);

List<int>? _parseVersion(String tag) {
  final match = RegExp(r'^v?(\d+(?:\.\d+)*)$').firstMatch(tag);
  if (match == null) return null;
  final parts = match.group(1)!.split('.').map(int.tryParse).toList();
  return parts.contains(null) ? null : parts.cast<int>();
}

/// Compares two versions, padding the shorter with zeros, so `7` sorts
/// as `7.0.0`.
int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

// coverage:ignore-start
// Wraps the GitHub API calls and is exercised end-to-end by the
// `generate` workflow at runtime. The resolver indirection above lets
// tests cover the pinning logic without touching the network.
final _releaseCache = <String, Future<ActionRelease?>>{};

Future<ActionRelease?> _cachedDefaultResolver(String repo) =>
    _releaseCache[repo] ??= _defaultResolver(repo);

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
  // Optional: lifts the unauthenticated limit of 60 requests an hour.
  final token = Platform.environment['GITHUB_TOKEN'];
  if (token != null && token.isNotEmpty) {
    request.headers.add('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return response.statusCode == 200 ? body : null;
}

// coverage:ignore-end
