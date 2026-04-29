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
// up"), we need to do it ourselves. This is ~80 lines of "scan for
// `uses:` references, hit /releases/latest, rewrite major version."
//
// If GitHub (or anyone else) ships a proper CLI for this, delete this
// file and use that instead.

/// Resolves the latest major version tag (e.g. `'v5'`) for the action
/// at `<owner>/<repo>` on GitHub. Returns `null` if no version can be
/// determined (network failure, missing release, malformed tag, etc.).
typedef LatestMajorResolver = Future<String?> Function(String repo);

/// Scans [workflowContent] for GitHub Actions `uses:` references and
/// returns a copy with each version bumped to the current latest major
/// (e.g., `@v4` becomes `@v5` if v5 is the latest major release).
///
/// Only `uses:` references themselves are rewritten — mentions of the
/// same `owner/repo@vN` string in YAML comments or `run:` shell strings
/// are left alone.
///
/// Queries `repos/<owner>/<repo>/releases/latest` on GitHub's public API.
/// If the lookup fails for a given action (network down, not found,
/// rate limited), that action's version is left unchanged.
///
/// [resolveLatestMajor] is exposed for testing — production callers should
/// leave it `null` to use the default GitHub API resolver.
///
/// Returns the updated content. If nothing changed, the return value is
/// identical to the input.
Future<String> updateActionVersions(
  String workflowContent, {
  LatestMajorResolver? resolveLatestMajor,
}) async {
  final actions = _extractActions(workflowContent);
  if (actions.isEmpty) return workflowContent;

  final resolver = resolveLatestMajor ?? _defaultResolver;
  final latestByRepo = <String, String?>{};
  for (final action in actions) {
    latestByRepo[action.repo] ??= await resolver(action.repo);
  }

  // Replace at regex match positions only, so mentions in comments or
  // `run:` strings (e.g. `echo "see actions/checkout@v4"`) are left alone.
  return workflowContent.replaceAllMapped(_usesRegex, (match) {
    final whole = match.group(0)!;
    final repo = match.group(1)!;
    final version = match.group(2)!;
    if (repo.startsWith('./')) return whole;
    final latest = latestByRepo[repo];
    if (latest == null || latest == version) return whole;
    return 'uses: $repo@$latest';
  });
}

// coverage:ignore-start
// Wraps the GitHub API call and is exercised end-to-end by the
// `generate` workflow at runtime. The resolver indirection above lets
// tests cover the version-bumping logic without touching the network.
Future<String?> _defaultResolver(String repo) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    return await _latestMajor(client, repo);
  } finally {
    client.close();
  }
}
// coverage:ignore-end

class _ActionRef {
  _ActionRef(this.repo, this.version);
  final String repo;
  final String version;
}

/// Matches `uses: owner/repo@version` where version starts with `v`
/// followed by a digit. Deliberately skips SHA pins and `@main`/`@master`.
final _usesRegex = RegExp(
  r'uses:\s+([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)@(v\d+(?:\.\d+)*)',
);

Set<_ActionRef> _extractActions(String content) {
  final refs = <String, _ActionRef>{};
  for (final match in _usesRegex.allMatches(content)) {
    final repo = match.group(1)!;
    final version = match.group(2)!;
    // Skip local action references (they start with ./ or are single-segment).
    if (repo.startsWith('./')) continue;
    refs['$repo@$version'] = _ActionRef(repo, version);
  }
  return refs.values.toSet();
}

// coverage:ignore-start
Future<String?> _latestMajor(HttpClient client, String repo) async {
  final uri = Uri.parse(
    'https://api.github.com/repos/$repo/releases/latest',
  );

  try {
    final request = await client.getUrl(uri);
    request.headers
      ..add('Accept', 'application/vnd.github+json')
      ..add('User-Agent', 'shorebird_ci');
    final response = await request.close();
    if (response.statusCode != 200) return null;

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = json['tag_name'] as String?;
    if (tag == null) return null;

    final match = RegExp(r'^v?(\d+)').firstMatch(tag);
    if (match == null) return null;
    return 'v${match.group(1)}';
  } on Exception {
    return null;
  }
}

// coverage:ignore-end
