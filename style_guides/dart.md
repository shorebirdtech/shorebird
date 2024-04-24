# Shorebird Dart Style Guide

This document outlines the style guide for all Shorebird Dart code.

This guide is a supplement to
[Effective Dart](https://dart.dev/guides/language/effective-dart) and should be
read in the same way. If there is a conflict between this guide and Effective
Dart, this guide takes precedence.

## AVOID mixins

Mixins are a powerful feature of Dart, but they can make code harder to
test. Mixins are effectively unmockable dependencies, and any code using them
will need to fully mock out all of the mixin's dependencies. Prefer creating a
new class as a `scoped` dependency instead.

## DO define one variable per line

```dart
// BAD
int a, b;

// GOOD
int a;
int b;
```

## PREFER nested `group`s for tests

These help to make the test structure clearer and easier to read, and result in
less duplicated code for tests that rely on the same setup.

```dart
// BAD
group('myFunction', () {

  setUp(() { ... });

  test('returns null when dep1.foo is true and dep2.bar is false', () {
    when(() => dep1.foo).thenReturn(true);
    when(() => dep2.bar).thenReturn(false);

    expect(myFunction(), isNull);
  });
});

// GOOD
group('myFunction', () {

  setUp(() { ... });

  group('when dep1.foo is true and dep2.bar is false', () {
    setUp(() {
      when(() => dep1.foo).thenReturn(true);
      when(() => dep2.bar).thenReturn(false);
    });

    test('returns null', () {
      expect(myFunction(), isNull);
    });
  });
});
```
