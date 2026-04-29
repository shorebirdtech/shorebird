import 'package:shorebird_ci/src/package_description.dart';
import 'package:test/test.dart';

void main() {
  group('PackageDescription', () {
    const a = PackageDescription(name: 'foo', rootPath: '/repo/foo');
    const b = PackageDescription(name: 'foo', rootPath: '/repo/foo');
    const differentName = PackageDescription(
      name: 'bar',
      rootPath: '/repo/foo',
    );
    const differentPath = PackageDescription(
      name: 'foo',
      rootPath: '/other/foo',
    );

    test('is equal to itself', () {
      expect(a, equals(a));
    });

    test('is equal to another instance with the same fields', () {
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('is not equal when name differs', () {
      expect(a == differentName, isFalse);
    });

    test('is not equal when rootPath differs', () {
      expect(a == differentPath, isFalse);
    });

    test('is not equal to a non-PackageDescription value', () {
      // We're deliberately comparing across types to exercise the
      // `other is PackageDescription` short-circuit on the == operator.
      // ignore: unrelated_type_equality_checks
      expect(a == 'foo', isFalse);
    });

    test('containsPath returns true for paths inside the package root', () {
      expect(a.containsPath('/repo/foo/lib/main.dart'), isTrue);
      expect(a.containsPath('/repo/bar/lib/main.dart'), isFalse);
    });
  });
}
