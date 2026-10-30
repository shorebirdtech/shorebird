// cspell:words shivammathur codeql
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

    test('compares a major-only comment at its own precision', () async {
      // `# v5` may be any v5.x; don't move it "forward" to v5.1.0.
      const input = '  - uses: actions/checkout@$_oldSha # v5\n';
      expect(await _update(input), equals(input));
      expect(
        await _update(input, tag: 'v6.0.0'),
        equals('  - uses: actions/checkout@$_newSha # v6.0.0\n'),
      );
    });

    test('handles release tags without a v', () async {
      const input = '  - uses: shivammathur/setup-php@v2\n';
      final pinned = await _update(input, tag: '2.40.0');
      expect(
        pinned,
        equals('  - uses: shivammathur/setup-php@$_newSha # 2.40.0\n'),
      );
      // The next run reads the comment back and moves it.
      expect(
        await _update(pinned, tag: '2.41.0'),
        equals('  - uses: shivammathur/setup-php@$_newSha # 2.41.0\n'),
      );
    });

    test('pins actions in a subdirectory of their repo', () async {
      final calls = <String>[];
      final result = await updateActionVersions(
        '  - uses: github/codeql-action/init@v3\n',
        resolveLatestRelease: (repo) async {
          calls.add(repo);
          return const ActionRelease(tag: 'v3.2.0', sha: _newSha);
        },
      );
      expect(calls, equals(['github/codeql-action']));
      expect(
        result,
        equals('  - uses: github/codeql-action/init@$_newSha # v3.2.0\n'),
      );
    });

    test('pins quoted refs', () async {
      expect(
        await _update('  - uses: "actions/checkout@v4"\n'),
        equals('  - uses: actions/checkout@$_newSha # v5.1.0\n'),
      );
    });

    test('keeps an existing trailing comment valid YAML', () async {
      expect(
        await _update('  - uses: actions/checkout@v4 # keep\n'),
        equals('  - uses: actions/checkout@$_newSha # v5.1.0 # keep\n'),
      );
    });

    test('leaves flow-style refs alone', () async {
      // A trailing comment would swallow the rest of the mapping.
      const input = '  - {uses: actions/checkout@v4, with: {fetch-depth: 0}}\n';
      expect(await _update(input), equals(input));
    });

    test('keeps CRLF line endings', () async {
      expect(
        await _update('  - uses: actions/checkout@v4\r\n'),
        equals('  - uses: actions/checkout@$_newSha # v5.1.0\r\n'),
      );
    });

    test('ignores versions too large to compare', () async {
      const input = '  - uses: actions/checkout@v99999999999999999999\n';
      expect(await _update(input), equals(input));
    });

    test('only rewrites uses: lines, not comments or run: strings', () async {
      // Regression: a previous version used String.replaceAll, which
      // would also rewrite `actions/checkout@v4` inside comments and
      // `run:` strings.
      const input = '''
# Pinned to actions/checkout@v4 — see release notes
# uses: actions/checkout@v4
steps:
  - uses: actions/checkout@v4
  - run: echo "we use actions/checkout@v4 here"
  - run: |
      echo uses: actions/checkout@v4
''';
      final result = await _update(input);
      // Only the uses: line gets pinned; comments and echoes keep v4.
      expect(result, contains('# Pinned to actions/checkout@v4'));
      expect(result, contains('# uses: actions/checkout@v4\n'));
      expect(result, contains('echo "we use actions/checkout@v4 here"'));
      expect(result, contains('echo uses: actions/checkout@v4\n'));
      expect(result, contains('uses: actions/checkout@$_newSha # v5.1.0'));
    });
  });

  test('unpinnedActionRefs lists refs not pinned to a SHA', () {
    const content =
        '''
steps:
  - uses: actions/checkout@$_oldSha # v4.0.0
  - uses: github/codeql-action/init@v3
  - uses: "actions/cache@v4"
  - uses: ./.github/actions/local
  - uses: docker://alpine:3
  - uses: some/action@main
''';
    expect(
      unpinnedActionRefs(content),
      equals([
        'github/codeql-action/init@v3',
        'actions/cache@v4',
        'some/action@main',
      ]),
    );
  });
}
