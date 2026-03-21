# dex

DEX binary parser and semantic differ for Android Dalvik Executable files.

## Usage

### Parsing

```dart
import 'package:dex/dex.dart';

final bytes = File('classes.dex').readAsBytesSync();
final dex = const DexParser().parse(bytes);

print('${dex.strings.length} strings');
print('${dex.classDefs.length} classes');

for (final classDef in dex.classDefs) {
  print('${classDef.className} extends ${classDef.superclass}');
}
```

### Diffing

```dart
import 'package:dex/dex.dart';

const parser = DexParser();
final oldDex = parser.parse(oldBytes);
final newDex = parser.parse(newBytes);

final result = const DexDiffer().diff(oldDex, newDex);

if (result.isSafe) {
  print('Only safe differences (e.g. source file paths)');
} else {
  print(result.describe());
}
```

## What gets compared

The differ compares DEX files structurally with full index remapping to
handle string table reordering caused by build path differences.

| Layer | What's checked |
|-------|---------------|
| Classes | Added/removed classes, access flags, superclass, interfaces |
| Methods | Added/removed methods, access flags |
| Fields | Added/removed fields, access flags |
| Bytecode | Instruction-by-instruction comparison with pool-index remapping |
| Try/catch | Handler types and addresses |
| Annotations | Class, field, method, and parameter annotations |
| Static values | Static field initial values |

Only `source_file` attributes and `debug_info` offsets are classified as
safe to differ. Everything else is treated as breaking.
