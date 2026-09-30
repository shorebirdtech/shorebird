// cspell:words stdlib varint
import 'dart:convert';
import 'dart:typed_data';

import 'package:shorebird_cli/src/archive_analysis/bundle_dependencies.dart';
import 'package:test/test.dart';

import 'bundle_dependencies_helpers.dart';

void main() {
  group(parseBundleDependencies, () {
    test('reads maven library versions', () {
      final bytes = appDependencies([
        mavenLibrary('io.branch.sdk.android', 'library', '5.21.3'),
        mavenLibrary('org.jetbrains.kotlin', 'kotlin-stdlib', '1.8.22'),
      ]);
      expect(parseBundleDependencies(bytes), {
        'io.branch.sdk.android:library': '5.21.3',
        'org.jetbrains.kotlin:kotlin-stdlib': '1.8.22',
      });
    });

    test('includes the classifier in the name when present', () {
      final bytes = appDependencies([
        mavenLibrary('com.example', 'native', '1.0.0', classifier: 'arm64'),
        mavenLibrary('com.example', 'plain', '1.0.0', classifier: ''),
      ]);
      expect(parseBundleDependencies(bytes), {
        'com.example:native:arm64': '1.0.0',
        'com.example:plain': '1.0.0',
      });
    });

    test('skips fields and libraries it does not understand', () {
      final bytes = appDependencies([
        // A varint field, a 64-bit field and a 32-bit field at the top level.
        [...protoVarint(6 << 3), 1],
        [...protoVarint(7 << 3 | 1), ...List.filled(8, 0)],
        [...protoVarint(8 << 3 | 5), ...List.filled(4, 0)],
        // Library dependency graph (field 2), which is not a library.
        protoField(2, [1, 2, 3]),
        // A library that isn't a Maven library.
        protoField(1, protoField(2, [1, 2, 3])),
        // A Maven library missing its version.
        protoField(1, protoField(1, protoField(1, utf8.encode('com.example')))),
        mavenLibrary('com.example', 'lib', '2.0.0'),
      ]);
      expect(parseBundleDependencies(bytes), {'com.example:lib': '2.0.0'});
    });

    test('returns an empty map for empty metadata', () {
      expect(parseBundleDependencies(Uint8List(0)), isEmpty);
    });

    test('throws a FormatException for truncated input', () {
      final bytes = mavenLibrary('com.example', 'lib', '1.0.0');
      expect(
        () => parseBundleDependencies(
          Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
        ),
        throwsFormatException,
      );
      expect(
        () => parseBundleDependencies(Uint8List.fromList([0x80])),
        throwsFormatException,
      );
      expect(
        () => parseBundleDependencies(Uint8List.fromList([7 << 3 | 1, 0])),
        throwsFormatException,
      );
    });

    test('throws a FormatException for unsupported wire types', () {
      expect(
        () => parseBundleDependencies(Uint8List.fromList([1 << 3 | 3])),
        throwsFormatException,
      );
    });
  });

  group(diffDependencyVersions, () {
    test('returns changed, added and removed libraries sorted by name', () {
      final changes = diffDependencyVersions(
        {'b:changed': '1.0.0', 'c:removed': '1.0.0', 'd:same': '1.0.0'},
        {'b:changed': '1.0.1', 'a:added': '2.0.0', 'd:same': '1.0.0'},
      );
      expect(changes, const [
        DependencyVersionChange(
          name: 'a:added',
          oldVersion: null,
          newVersion: '2.0.0',
        ),
        DependencyVersionChange(
          name: 'b:changed',
          oldVersion: '1.0.0',
          newVersion: '1.0.1',
        ),
        DependencyVersionChange(
          name: 'c:removed',
          oldVersion: '1.0.0',
          newVersion: null,
        ),
      ]);
    });

    test('returns nothing when versions match', () {
      expect(diffDependencyVersions({'a:b': '1'}, {'a:b': '1'}), isEmpty);
    });
  });

  group(DependencyVersionChange, () {
    test('describe', () {
      expect(
        const DependencyVersionChange(
          name: 'a:b',
          oldVersion: '1.0.0',
          newVersion: '1.0.1',
        ).describe(),
        'a:b 1.0.0 -> 1.0.1',
      );
      expect(
        const DependencyVersionChange(
          name: 'a:b',
          oldVersion: null,
          newVersion: '1.0.1',
        ).describe(),
        'a:b 1.0.1 (added)',
      );
      expect(
        const DependencyVersionChange(
          name: 'a:b',
          oldVersion: '1.0.0',
          newVersion: null,
        ).describe(),
        'a:b 1.0.0 (removed)',
      );
    });
  });
}
