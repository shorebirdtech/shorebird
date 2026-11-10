<!-- cspell:words objc -->
# macho

Mach-O binary parser and semantic differ for Apple executable and framework files.

## Usage

### Parsing

```dart
import 'package:macho/macho.dart';

final bytes = File('Runner').readAsBytesSync();
final macho = const MachOParser().parse(bytes);

for (final slice in macho.slices) {
  print('${slice.symbols.length} symbols');
  print('${slice.objcClassNames.length} Objective-C classes');
}
```

### Diffing

```dart
import 'package:macho/macho.dart';

const parser = MachOParser();
final oldMachO = parser.parse(oldBytes);
final newMachO = parser.parse(newBytes);

final result = const MachODiffer().diff(oldMachO, newMachO);

if (result.isSafe) {
  print('Only safe differences (e.g. LC_UUID or signature padding)');
} else {
  print(result.describe());
}
```
