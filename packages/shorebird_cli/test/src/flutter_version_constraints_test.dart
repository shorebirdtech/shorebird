import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/flutter_version_constraints.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  group('satisfiesFloor', () {
    test('a side version clears the floor its upstream version clears', () {
      final sideVersion = Version.parse('3.32.6-sb.1');

      expect(sideVersion, lessThan(minimumSupportedWindowsFlutterVersion));
      expect(
        sideVersion.satisfiesFloor(minimumSupportedWindowsFlutterVersion),
        isTrue,
      );
    });

    test('a side version below the floor stays below it', () {
      expect(
        Version.parse('3.32.5-sb.1').satisfiesFloor(
          minimumSupportedWindowsFlutterVersion,
        ),
        isFalse,
      );
    });

    test("an upstream pre-release stays below its release's floor", () {
      expect(
        Version.parse('3.32.6-0.1.pre').satisfiesFloor(
          minimumSupportedWindowsFlutterVersion,
        ),
        isFalse,
      );
    });

    test('a plain version compares as it always did', () {
      expect(
        Version(3, 32, 6).satisfiesFloor(
          minimumSupportedWindowsFlutterVersion,
        ),
        isTrue,
      );
      expect(
        Version(3, 32, 5).satisfiesFloor(
          minimumSupportedWindowsFlutterVersion,
        ),
        isFalse,
      );
    });
  });

  group(FlutterSupportConstraint, () {
    const revision = 'd4b5c1a0e9f8d7c6b5a4938271605f4e3d2c1b0a';

    test('a side version of the floor satisfies arm64 patch support', () {
      expect(
        arm64PatchSupportConstraint.isSatisfiedBy(
          version: Version.parse('3.41.7-sb.1'),
          revision: revision,
        ),
        isTrue,
      );
    });

    test('a side version of the floor satisfies build trace support', () {
      expect(
        buildTraceSupportConstraint.isSatisfiedBy(
          version: Version.parse('3.41.7-sb.1'),
          revision: revision,
        ),
        isTrue,
      );
    });

    test('a side version below the floor is still refused', () {
      expect(
        arm64PatchSupportConstraint.isSatisfiedBy(
          version: Version.parse('3.41.6-sb.1'),
          revision: revision,
        ),
        isFalse,
      );
    });

    test('an allowed revision below the floor still satisfies', () {
      expect(
        updaterPatchErrorFixConstraint.isSatisfiedBy(
          version: Version(3, 24, 1),
          revision: 'a25b7cdfb9ef79f7d6dae48a6334a415f024a0a8',
        ),
        isTrue,
      );
    });
  });
}
