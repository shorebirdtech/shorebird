# Scoped

A simple dependency injection library built on Zones.

## Quick Start

```dart
import 'package:scoped/scoped.dart';

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
