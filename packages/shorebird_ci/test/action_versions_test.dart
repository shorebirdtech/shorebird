import 'package:shorebird_ci/src/action_versions.dart';
import 'package:test/test.dart';

// cspell:disable
const _oldSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
// cspell:enable

Future<String> _update(String input, {String tag = 'v5.1.0'}) =>
    updateActionVersions(
      input,
      resolveLatestRelease: (repo) async =>
          ActionRelease(tag: tag, sha: _newSha),
    );

void main() {
  group('updateActionVersions', () {
    test('returns unchanged content with no `uses:` references', () async {
      const input = '''
name: test
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
''';
      expect(await _update(input), equals(input));
    });

    test('leaves local action references alone', () async {
      // Local actions (`uses: ./...`) aren't on GitHub, so the
      // resolver shouldn't try to look them up.
      const input = '''
steps:
  - uses: ./.github/actions/my_local_action
''';
      expect(await _update(input), equals(input));
    });

    test('leaves SHA pins without a version comment alone', () async {
      // No version to compare against, so the pin may be deliberate.
      const input =
          '''
steps:
  - uses: actions/checkout@$_oldSha
''';
      expect(await _update(input), equals(input));
    });

    test('leaves branch-pinned actions alone', () async {
      const input = '''
steps:
  - uses: actions/checkout@main
''';
      expect(await _update(input), equals(input));
    });

    test('pins a major tag to the latest release by SHA', () async {
      const input = '''
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0
''';
      expect(
        await _update(input),
        equals('''
steps:
  - uses: actions/checkout@$_newSha # v5.1.0
    with:
      fetch-depth: 0
'''),
      );
    });

    test('pins a tag already at the latest release', () async {
      // Same version, but a tag can still be moved, so pin it.
      const input = '  - uses: actions/checkout@v5\n';
      expect(
        await _update(input),
        equals('  - uses: actions/checkout@$_newSha # v5.1.0\n'),
      );
    });

    test('leaves a tag newer than the latest release alone', () async {
      const input = '  - uses: actions/checkout@v5.2\n';
      expect(await _update(input), equals(input));
    });

    test('moves a SHA pin to a newer release', () async {
      const input = '  - uses: actions/checkout@$_oldSha # v5.0.0\n';
      expect(
        await _update(input),
        equals('  - uses: actions/checkout@$_newSha # v5.1.0\n'),
      );
    });

    test('does not follow a tag moved under the same version', () async {
      // releases/latest says v5.1.0 now points at a different commit
      // than the one pinned. That's what a hijacked tag looks like.
      const input = '  - uses: actions/checkout@$_oldSha # v5.1.0\n';
      expect(await _update(input), equals(input));
    });

    test('never moves a SHA pin to an older release', () async {
      const input = '  - uses: actions/checkout@$_oldSha # v6.0.0\n';
      expect(await _update(input), equals(input));
    });

    test('leaves refs alone when the resolver returns null', () async {
      const input = '  - uses: actions/checkout@v4\n';
      final result = await updateActionVersions(
        input,
        resolveLatestRelease: (repo) async => null,
      );
      expect(result, equals(input));
    });

    test('ignores pre-release-looking tags it cannot compare', () async {
      const input = '  - uses: actions/checkout@v4-beta\n';
      expect(await _update(input), equals(input));
    });

    test('resolves each repo once', () async {
      const input = '''
  - uses: actions/checkout@v4
  - uses: actions/checkout@v4
  - uses: dart-lang/setup-dart@v1
''';
      final calls = <String>[];
      await updateActionVersions(
        input,
        resolveLatestRelease: (repo) async {
          calls.add(repo);
          return const ActionRelease(tag: 'v9.0.0', sha: _newSha);
        },
      );
      expect(calls, equals(['actions/checkout', 'dart-lang/setup-dart']));
    });

    test('only rewrites uses: lines, not comments or run: strings', () async {
      // Regression: a previous version used String.replaceAll, which
      // would also rewrite `actions/checkout@v4` inside comments and
      // `run:` strings.
      const input = '''
# Pinned to actions/checkout@v4 — see release notes
steps:
  - uses: actions/checkout@v4
  - run: echo "we use actions/checkout@v4 here"
''';
      final result = await _update(input);
      // Only the uses: line gets pinned; comment and echo keep v4.
      expect(result, contains('# Pinned to actions/checkout@v4'));
      expect(result, contains('echo "we use actions/checkout@v4 here"'));
      expect(result, contains('uses: actions/checkout@$_newSha # v5.1.0'));
    });
  });
}
