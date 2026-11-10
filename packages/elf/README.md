<!-- cspell:words dynsym dynstr libnative rodata -->
# elf

ELF shared object parser and semantic differ for Android native libraries.

## Usage

### Parsing

```dart
import 'package:elf/elf.dart';

final bytes = File('libnative.so').readAsBytesSync();
final elf = const ElfParser().parse(bytes);

print('${elf.symbols.length} dynamic symbols');
print('Needed libraries: ${elf.neededLibraries}');
```

### Diffing

```dart
import 'package:elf/elf.dart';

const parser = ElfParser();
final oldElf = parser.parse(oldBytes);
final newElf = parser.parse(newBytes);

final result = const ElfDiffer().diff(oldElf, newElf);

if (result.isSafe) {
  print('Only safe differences (e.g. .note.gnu.build-id or debug sections)');
} else {
  print(result.describe());
}
```
