// ignore_for_file: prefer_const_constructors
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';

void main() {
  group('Scoped', () {
    test('read throws StateError when ref is not available', () {
      final value = create(() => 42);
      expect(() => read(value), throwsStateError);
    });

    test('read uses orElse when ref is not available', () {
      final value = create(() => 42);
      expect(read(value, orElse: () => 0), equals(0));
    });

    test('calls onError when uncaught exception occurs', () {
      final value = create(() => 42);
      late final Object exception;
      runScopedGuarded(
        () => read(value),
        onError: (error, _) => exception = error,
      );
      expect(exception, isNotNull);
    });

    test('read accesses the value when ref is available', () {
      final value = create(() => 42);
      runScoped(
        () => expect(read(value), equals(42)),
        values: {value},
      );
    });

    test('value is computed lazily and cached', () {
      var createCallCount = 0;
      final value = create(() {
        createCallCount++;
        return 42;
      });

      expect(createCallCount, equals(0));

      runScoped(
        () {
          expect(read(value), equals(42));
          expect(read(value), equals(42));
          expect(read(value), equals(42));
        },
        values: {value},
      );

      expect(createCallCount, equals(1));
    });

    test('value can be overridden', () {
      final value = create(() => 42);

      runScoped(
        () {
          expect(read(value), equals(42));

          runScoped(
            () => expect(read(value), equals(0)),
            values: {value.overrideWith(() => 0)},
          );
        },
        values: {value},
      );
    });

    test('overrides are considered equal', () {
      final value = create(() => 42);
      final override = value.overrideWith(() => 0);
      expect(value, equals(override));
      expect(value.hashCode, equals(override.hashCode));
    });

    test('same instance is equal', () {
      final value = create(() => 42);
      expect(value, equals(value));
    });

    test('different instances are not equal', () {
      final valueA = create(() => 42);
      final valueB = create(() => 42);
      expect(valueA, isNot(equals(valueB)));
      expect(valueA.hashCode, isNot(equals(valueB.hashCode)));
    });
  });
}
