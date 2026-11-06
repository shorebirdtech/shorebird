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

  group('extractDornyFilters', () {
    test('maps each filter to its paths, across blocks', () {
      const workflow = '''
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            foo:
              - packages/foo/**
              - './packages/shared/**'
            bar:
              - "packages/bar/**" # the bar package
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            foo:
              - packages/extra/**
''';

      expect(
        extractDornyFilters(workflow),
        equals({
          'foo': {
            'packages/foo/**',
            './packages/shared/**',
            'packages/extra/**',
          },
          'bar': {'packages/bar/**'},
        }),
      );
    });
  });

  group('updateDornyFilters', () {
    test('returns null when workflow has no filters block', () {
      const workflow = '''
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
''';
      expect(
        updateDornyFilters(workflow, {
          'foo': ['packages/foo/**'],
        }),
        isNull,
      );
    });

    test(
      'updates package filters in place and adds missing packages in a '
      'single-block workflow',
      () {
        const workflow = '''
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v4
        id: filter
        with:
          filters: |
            # initial comment
            foo:
              - .github/workflows/custom.yaml
              - packages/foo/**

  custom_job:
    runs-on: ubuntu-latest
''';

        final updated = updateDornyFilters(workflow, {
          'foo': ['packages/bar/**', 'packages/foo/**'],
          'bar': ['packages/bar/**'],
        });

        expect(
          updated,
          equals('''
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v4
        id: filter
        with:
          filters: |
            bar:
              - packages/bar/**
            foo:
              - .github/workflows/custom.yaml
              - packages/bar/**
              - packages/foo/**

  custom_job:
    runs-on: ubuntu-latest
'''),
        );
      },
    );

    test(
      'preserves non-package filter blocks and custom filter entries in '
      'multi-block workflows',
      () {
        const workflow = '''
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v4
        id: docs_only
        with:
          filters: |
            all:
              - '**'
            docs:
              - '*.md'
      - uses: dorny/paths-filter@v4
        id: server_build
        with:
          filters: |
            # server comment
            server_a:
              - ./.github/actions/custom/**
              - packages/server_a/**
            # custom entry comment
            custom_non_pkg:
              - tools/custom/**
      - uses: dorny/paths-filter@v4
        id: lib_build
        with:
          filters: |
            lib_b:
              - packages/lib_b/**
''';

        final updated = updateDornyFilters(workflow, {
          'server_a': ['packages/lib_b/**', 'packages/server_a/**'],
          'lib_b': ['packages/lib_b/**', 'pubspec.lock'],
        });

        expect(
          updated,
          equals('''
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v4
        id: docs_only
        with:
          filters: |
            all:
              - '**'
            docs:
              - '*.md'
      - uses: dorny/paths-filter@v4
        id: server_build
        with:
          filters: |
            server_a:
              - ./.github/actions/custom/**
              - packages/lib_b/**
              - packages/server_a/**
            # custom entry comment
            custom_non_pkg:
              - tools/custom/**
      - uses: dorny/paths-filter@v4
        id: lib_build
        with:
          filters: |
            lib_b:
              - packages/lib_b/**
              - pubspec.lock
'''),
        );
      },
    );
  });
}
