<!-- cspell:words Angelov mrgnhnt -->

# Scoped Deps

A simple dependency injection library built on Zones.

## Status: vendored, no longer published by Shorebird

Felix Angelov wrote this package in 2023 (originally `package:scoped`) so that
our packages could share one dependency-injection mechanism. We published it to
pub.dev in 2024 in case it was useful to others, then never needed to change it
again.

In 2026, Morgan Hunt ([`mrgnhnt96/scoped_deps`][mrgnhnt_repo]) approached us
about taking over the pub.dev package and continuing to improve it, and we
accepted. **[`scoped_deps` on pub.dev][pub_package] is now his**, and its
versions have diverged from this directory.

Shorebird packages keep using this vendored copy, resolved through the Dart
workspace rather than from pub.dev. The code hasn't meaningfully changed in two
years, so there's nothing to gain from moving right now. At some point we should
look at where the pub.dev package has evolved to and consider deleting this copy
in favor of it.

[mrgnhnt_repo]: https://github.com/mrgnhnt96/scoped_deps
[pub_package]: https://pub.dev/packages/scoped_deps

## Quick Start

```dart
import 'package:scoped_deps/scoped_deps.dart';

final value = create(() => 42);

void main() {
  runScoped(scopeA, values: {value});
}

void scopeA() {
  print(read(value)); // 42
  runScoped(scopeB, values: {value.overrideWith(() => 0)});
}

void scopeB() {
  print(read(value)); // 0
}
```
