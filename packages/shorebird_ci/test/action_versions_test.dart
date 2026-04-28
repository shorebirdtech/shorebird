import 'package:shorebird_ci/src/action_versions.dart';
import 'package:test/test.dart';

// Note: updateActionVersions hits GitHub's API to resolve latest
// versions. These tests only cover the paths that don't require
// network — content without any `uses:` lines, or content that matches
// nothing that would trigger a lookup.

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
      expect(await updateActionVersions(input), equals(input));
    });

    test('leaves local action references alone', () async {
      // Local actions (`uses: ./...`) aren't on GitHub, so the
      // resolver shouldn't try to look them up.
      const input = '''
steps:
  - uses: ./.github/actions/my_local_action
''';
      expect(await updateActionVersions(input), equals(input));
    });

    test('leaves SHA pins alone', () async {
      // `@<40-char hash>` isn't a version tag we'd bump.
      const input = '''
steps:
  - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
''';
      expect(await updateActionVersions(input), equals(input));
    });

    test('leaves branch-pinned actions alone', () async {
      const input = '''
steps:
  - uses: actions/checkout@main
''';
      expect(await updateActionVersions(input), equals(input));
    });

    test('only rewrites uses: lines, not comments or run: strings', () async {
      // Regression: a previous version used String.replaceAll, which
      // would also rewrite `actions/checkout@v4` inside comments and
      // `run: echo "..."` strings.
      const input = '''
# Pinned to actions/checkout@v4 — see release notes
steps:
  - uses: actions/checkout@v4
  - run: echo "we use actions/checkout@v4 here"
''';
      final result = await updateActionVersions(
        input,
        resolveLatestMajor: (repo) async => 'v5',
      );
      // Only the uses: line gets bumped; comment and echo keep v4.
      expect(result, contains('# Pinned to actions/checkout@v4'));
      expect(result, contains('echo "we use actions/checkout@v4 here"'));
      expect(result, contains('uses: actions/checkout@v5'));
    });
  });
}
