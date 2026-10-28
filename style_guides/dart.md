# Shorebird Dart Style Guide

This document outlines the style guide for all Shorebird Dart code.

This guide is a supplement to
[Effective Dart](https://dart.dev/guides/language/effective-dart) and should be
read in the same way. If there is a conflict between this guide and Effective
Dart, this guide takes precedence.

This style guide only defines rules which are not enforced via lint rules. If
possible, prefer using lint rules to enforce style.

## AVOID mixins

Mixins are a powerful feature of Dart, but they make code harder to test:

1. Mixins cannot be tested directly and must be tested through the classes they
   are mixed into.
2. Mixins are effectively unmockable dependencies of the classes they are mixed
   into, meaning every class that uses the mixin will need to set up and mock
   the mixin's dependencies in its own tests.

Prefer creating a new class as a `scoped` dependency instead, or adding the code
to an existing `scoped` dependency.

## PREFER nested `group`s for tests

These help to make the test structure clearer and easier to read, and result in
less duplicated code for tests that rely on the same setup.

```dart
// BAD
group('myFunction', () {
  test('returns null when dep1.foo is true and dep2.bar is false', () {
    when(() => dep1.foo).thenReturn(true);
    when(() => dep2.bar).thenReturn(false);

    expect(myFunction(), isNull);
  });
});

// GOOD
group('myFunction', () {
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

## PREFER to use multiline string literals for long strings

This makes the string easier to read, and reduces the chance of accidentally
including too few or too many spaces in the string.

```dart
// BAD
final longString = 'This is a string longer than the eighty character '
  'limit that our lint rules enforce.';

// GOOD
final longString = '''This is a string longer than the eighty character limit that our lint rules enforce.'''
```

## AVOID the null-assertion operator `!`

`!` crashes at runtime when the value is null, and every reader has to work out
again why it's safe. Pull the nullable expression into a local, check it, and
let flow analysis promote the local. Flag a `!` that could be rewritten this
way in review. Where the analyzer can't follow (for example a field you know is
initialized), a `!` is acceptable with a comment saying why.

```dart
// BAD
if (release.flutterVersion != null) {
  use(release.flutterVersion!);
}

// GOOD
final flutterVersion = release.flutterVersion;
if (flutterVersion != null) {
  use(flutterVersion);
}
```
