import 'package:shorebird_cli/src/extensions/iterable.dart';
import 'package:test/test.dart';

void main() {
  group('containsAnyOf', () {
    test('returns true when any element is in the iterable', () {
      final iterable = [1, 2, 3];
      final elements = [3, 4, 5];
      expect(iterable.containsAnyOf(elements), isTrue);
    });

    test('returns false when no element is in the iterable', () {
      final iterable = [1, 2, 3];
      final elements = [4, 5, 6];
      expect(iterable.containsAnyOf(elements), isFalse);
    });
  });
}
