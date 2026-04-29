import 'package:shorebird_ci/shorebird_ci.dart';
import 'package:test/test.dart';

void main() {
  group('extractDornyFilterNames', () {
    test('extracts filter names from a standard dorny block', () {
      const workflow = '''
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            foo:
              - packages/foo/**
            bar:
              - packages/bar/**
              - packages/shared/**
''';

      expect(
        extractDornyFilterNames(workflow),
        equals({'foo', 'bar'}),
      );
    });

    test('returns empty set when no dorny block', () {
      const workflow = '''
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
''';

      expect(extractDornyFilterNames(workflow), isEmpty);
    });

    test('extracts from multiple dorny blocks', () {
      const workflow = '''
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v3
        id: first
        with:
          filters: |
            alpha:
              - packages/alpha/**
      - uses: dorny/paths-filter@v3
        id: second
        with:
          filters: |
            beta:
              - packages/beta/**
''';

      expect(
        extractDornyFilterNames(workflow),
        equals({'alpha', 'beta'}),
      );
    });

    test('handles non-standard indentation', () {
      // Same structure but with different (larger) nesting indent.
      const workflow = '''
on:
  push:
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v3
        with:
          filters: |
                foo:
                  - packages/foo/**
                bar:
                  - packages/bar/**
''';

      expect(
        extractDornyFilterNames(workflow),
        equals({'foo', 'bar'}),
      );
    });

    test('stops at end of filter block', () {
      const workflow = '''
      - uses: dorny/paths-filter@v3
        with:
          filters: |
            foo:
              - packages/foo/**
      - name: Other step
        run: echo done
''';

      expect(extractDornyFilterNames(workflow), equals({'foo'}));
    });

    test('ignores deeply indented content (path entries)', () {
      const workflow = '''
      - uses: dorny/paths-filter@v3
        with:
          filters: |
            foo:
              - packages/foo/**
              - packages/shared/**
            bar:
              - packages/bar/**
''';

      // Should extract foo and bar, not the path entries.
      expect(
        extractDornyFilterNames(workflow),
        equals({'foo', 'bar'}),
      );
    });
  });
}
