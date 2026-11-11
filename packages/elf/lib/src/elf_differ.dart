// cspell:words aarch debuglink dynsym dynstr entsize execinstr fini funcs
// cspell:words ifunc insn insns nobits notype progbits riscv rodata shdr shndx
// cspell:words shstrtab soname strtab symtab undetailed undef
import 'dart:typed_data';

import 'package:elf/src/elf_parser.dart';
import 'package:meta/meta.dart';

/// The classification of a semantic difference between two ELF binaries.
enum ElfDifferenceKind {
  /// `.note.gnu.build-id` payload changed (safe — regenerated per build).
  buildIdChanged,

  /// `.gnu_debuglink`, `.debug_*` sections, or section header ordering changed
  /// while runtime payloads match (safe — debug/layout metadata noise).
  debugInfoChanged,

  /// An exported or imported dynamic symbol in `.dynsym` was added.
  symbolAdded,

  /// An exported or imported dynamic symbol in `.dynsym` was removed.
  symbolRemoved,

  /// A symbol's binding, type, visibility, size, or defining section changed.
  symbolBindingChanged,

  /// Machine code instructions in `.text` or `.plt` changed.
  functionCodeChanged,

  /// Read-only constant data in `.rodata` changed.
  rodataChanged,

  /// Initialized data in `.data` or `.bss` size changed.
  dataChanged,

  /// A `DT_NEEDED` shared library dependency in `.dynamic` was added.
  neededLibraryAdded,

  /// A `DT_NEEDED` shared library dependency in `.dynamic` was removed.
  neededLibraryRemoved,

  /// The `DT_SONAME` shared object name in `.dynamic` changed.
  sonameChanged,

  /// A non-debug ELF section was added.
  sectionAdded,

  /// A non-debug ELF section was removed.
  sectionRemoved,

  /// ELF class (32/64-bit), endianness, machine architecture, or file type
  /// changed.
  architectureChanged,

  /// One or both binaries could not be parsed as valid ELF.
  unparseableBinary;

  /// Whether this kind of difference is safe to ignore during a patch check.
  bool get isSafe => this == buildIdChanged || this == debugInfoChanged;
}

/// {@template elf_difference}
/// A single semantic difference found between two ELF binaries.
/// {@endtemplate}
@immutable
class ElfDifference {
  /// {@macro elf_difference}
  const ElfDifference({
    required this.kind,
    required this.description,
    this.codeDiff,
  });

  /// The classification of this difference.
  final ElfDifferenceKind kind;

  /// A human-readable description of the difference.
  final String description;

  /// Instruction-level diff window when [kind] is
  /// [ElfDifferenceKind.functionCodeChanged].
  final ElfCodeDiff? codeDiff;
}

/// {@template elf_code_diff}
/// Where two function bodies in `.text` disagree.
///
/// Spans from the end of the longest common instruction prefix to the start of
/// the longest common instruction suffix.
/// {@endtemplate}
@immutable
class ElfCodeDiff {
  /// {@macro elf_code_diff}
  const ElfCodeDiff({
    this.oldRegion = const [],
    this.newRegion = const [],
    this.sizeChange,
  });

  /// Canonical instructions from the old function in the differing window.
  final List<ElfCanonicalInstruction> oldRegion;

  /// Canonical instructions from the new function in the differing window.
  final List<ElfCanonicalInstruction> newRegion;

  /// Optional summary when the function body size changed or was added/removed.
  final String? sizeChange;

  /// Default number of tokens rendered per instruction unless full output is
  /// requested.
  static const int defaultTokenLimit = 4;

  /// Whether rendering with [limit] would truncate instructions or tokens.
  bool exceeds(int limit) =>
      oldRegion.length > limit ||
      newRegion.length > limit ||
      [...oldRegion, ...newRegion].any(
        (i) => i.exceedsTokens(defaultTokenLimit),
      );

  /// Whether either region carries a resolved string literal.
  bool get hasStringLiterals =>
      oldRegion.any((i) => i.hasStringLiteral) ||
      newRegion.any((i) => i.hasStringLiteral);

  /// Renders the instruction diff window as indented `-`/`+` lines.
  String describe({int? limit, bool showStringLiterals = false}) {
    final buffer = StringBuffer();

    final currentSizeChange = sizeChange;
    if (currentSizeChange != null) {
      buffer.writeln('      $currentSizeChange');
    }

    void writeSide(String marker, List<ElfCanonicalInstruction> region) {
      final shown = limit == null || region.length <= limit
          ? region
          : region.take(limit).toList();
      for (final instruction in shown) {
        final address = instruction.address.toRadixString(16).padLeft(4, '0');
        final tokens = instruction.render(
          showLiterals: showStringLiterals,
          limit: showStringLiterals ? null : defaultTokenLimit,
        );
        buffer.writeln('      $marker 0x$address  $tokens');
      }
      final hidden = region.length - shown.length;
      if (hidden > 0) {
        buffer.writeln('      $marker ... $hidden more');
      }
    }

    writeSide('-', oldRegion);
    writeSide('+', newRegion);

    return buffer.toString().trimRight();
  }
}

/// {@template elf_diff_result}
/// The result of comparing two ELF binaries.
/// {@endtemplate}
@immutable
class ElfDiffResult {
  /// {@macro elf_diff_result}
  const ElfDiffResult({required this.differences});

  /// Creates an empty (identical) diff result.
  const ElfDiffResult.identical() : differences = const [];

  /// All differences found between the two ELF binaries.
  final List<ElfDifference> differences;

  /// Differences that are safe build noise (`.note.gnu.build-id`,
  /// `.gnu_debuglink`, `.debug_*`).
  Iterable<ElfDifference> get safeDifferences =>
      differences.where((d) => d.kind.isSafe);

  /// Differences that indicate breaking native changes.
  Iterable<ElfDifference> get breakingDifferences =>
      differences.where((d) => !d.kind.isSafe);

  /// Whether all differences are safe to ignore.
  bool get isSafe => breakingDifferences.isEmpty;

  /// Default number of instructions shown per side for a changed function.
  static const int defaultCodeDiffLimit = 4;

  /// Default number of changed functions detailed unless full output is
  /// requested.
  static const int defaultDetailedFunctionLimit = 10;

  /// Whether [describe] hides detail that `showFullCodeDiff: true` would show.
  bool get hasHiddenCodeDiff {
    final detailed = <ElfCodeDiff>[
      for (final d in differences) ?d.codeDiff,
    ];
    return detailed.length > defaultDetailedFunctionLimit ||
        detailed.any(
          (codeDiff) =>
              codeDiff.exceeds(defaultCodeDiffLimit) ||
              codeDiff.hasStringLiterals,
        );
  }

  /// Formats a human-readable summary of safe and breaking differences.
  String describe({bool showFullCodeDiff = false}) {
    final buffer = StringBuffer();
    final safe = safeDifferences.toList();
    final breaking = breakingDifferences.toList();

    var detailed = 0;
    var undetailed = 0;

    void writeDifference(ElfDifference diff) {
      buffer.writeln('  - ${diff.description}');
      final codeDiff = diff.codeDiff;
      if (codeDiff == null) return;
      if (!showFullCodeDiff && detailed >= defaultDetailedFunctionLimit) {
        undetailed++;
        return;
      }
      detailed++;
      final detail = codeDiff.describe(
        limit: showFullCodeDiff ? null : defaultCodeDiffLimit,
        showStringLiterals: showFullCodeDiff,
      );
      if (detail.isNotEmpty) buffer.writeln(detail);
    }

    if (safe.isNotEmpty) {
      buffer.writeln('Safe differences (${safe.length}):');
      safe.forEach(writeDifference);
    }

    if (breaking.isNotEmpty) {
      buffer.writeln('Breaking differences (${breaking.length}):');
      breaking.forEach(writeDifference);
    }

    if (undetailed > 0) {
      buffer.writeln('  ... $undetailed more changed functions not detailed');
    }

    return buffer.toString().trimRight();
  }
}

/// {@template elf_differ}
/// Compares two ELF shared objects or executables and produces an
/// [ElfDiffResult] classifying every semantic difference as safe build noise
/// or a breaking native change.
/// {@endtemplate}
class ElfDiffer {
  /// {@macro elf_differ}
  const ElfDiffer();

  /// Parses [oldBytes] and [newBytes] and compares them.
  ///
  /// If either binary fails to parse, returns a breaking [ElfDiffResult]
  /// containing [ElfDifferenceKind.unparseableBinary] rather than throwing.
  ElfDiffResult diffBytes(
    Uint8List oldBytes,
    Uint8List newBytes, {
    ElfParser parser = const ElfParser(),
  }) {
    final ElfFile oldFile;
    final ElfFile newFile;
    try {
      oldFile = parser.parse(oldBytes);
      newFile = parser.parse(newBytes);
      // Catch all format/parse errors so malformed binaries fail closed.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return ElfDiffResult(
        differences: [
          ElfDifference(
            kind: ElfDifferenceKind.unparseableBinary,
            description: 'Unparseable ELF binary: $e',
          ),
        ],
      );
    }

    return diff(oldFile, newFile);
  }

  /// Compares two parsed [ElfFile]s and returns an [ElfDiffResult].
  ElfDiffResult diff(ElfFile oldFile, ElfFile newFile) {
    final differences = <ElfDifference>[];

    // 1. Header / architecture check.
    if (oldFile.header.elfClass != newFile.header.elfClass ||
        oldFile.header.dataEncoding != newFile.header.dataEncoding ||
        oldFile.header.machine != newFile.header.machine ||
        oldFile.header.fileType != newFile.header.fileType) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.architectureChanged,
          description:
              'ELF architecture/header changed from '
              '${_formatHeaderArch(oldFile.header)} to '
              '${_formatHeaderArch(newFile.header)}',
        ),
      );
      return ElfDiffResult(differences: differences);
    }

    // 2. Safe checks: .note.gnu.build-id, .gnu_debuglink, .debug_* sections.
    if (!_nullableBytesEqual(oldFile.buildId, newFile.buildId)) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.buildIdChanged,
          description:
              '.note.gnu.build-id changed from '
              '${_formatHex(oldFile.buildId)} to '
              '${_formatHex(newFile.buildId)}',
        ),
      );
    }

    if (!_nullableBytesEqual(oldFile.debugLink, newFile.debugLink) ||
        !_byteMapsEqual(oldFile.debugSections, newFile.debugSections)) {
      differences.add(
        const ElfDifference(
          kind: ElfDifferenceKind.debugInfoChanged,
          description: '.gnu_debuglink or .debug_* sections changed',
        ),
      );
    }

    // 3. DT_NEEDED and DT_SONAME in .dynamic.
    _compareNeededLibraries(
      oldFile.neededLibraries,
      newFile.neededLibraries,
      differences,
    );

    if (oldFile.soname != newFile.soname) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.sonameChanged,
          description:
              'DT_SONAME changed from ${oldFile.soname ?? "<none>"} to '
              '${newFile.soname ?? "<none>"}',
        ),
      );
    }

    // 4. Structural non-debug sections and section header ordering.
    _compareSections(oldFile, newFile, differences);

    // 5. Read-only data (.rodata, .rodata.*).
    _compareNamedByteMaps(
      oldMap: oldFile.rodataSections,
      newMap: newFile.rodataSections,
      kind: ElfDifferenceKind.rodataChanged,
      label: 'Read-only data section',
      differences: differences,
    );

    // 6. Initialized data (.data, .data.*, .init_array, .fini_array) and .bss.
    _compareNamedByteMaps(
      oldMap: oldFile.dataSections,
      newMap: newFile.dataSections,
      kind: ElfDifferenceKind.dataChanged,
      label: 'Data section',
      differences: differences,
    );

    if (oldFile.bssSize != newFile.bssSize) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.dataChanged,
          description:
              '.bss size changed from ${oldFile.bssSize} to '
              '${newFile.bssSize} bytes',
        ),
      );
    }

    // 7. Dynamic symbol table (.dynsym).
    final reportedSymbols = _compareSymbols(
      oldFile: oldFile,
      newFile: newFile,
      differences: differences,
    );

    // 8. .plt and per-symbol .text code slices.
    _comparePlt(oldFile.pltSection, newFile.pltSection, differences);
    _compareFunctions(
      oldFile: oldFile,
      newFile: newFile,
      reportedSymbols: reportedSymbols,
      differences: differences,
    );

    return ElfDiffResult(differences: differences);
  }

  void _compareNeededLibraries(
    List<String> oldNeeded,
    List<String> newNeeded,
    List<ElfDifference> differences,
  ) {
    final oldSet = oldNeeded.toSet();
    final newSet = newNeeded.toSet();

    for (final added in newSet.difference(oldSet)) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.neededLibraryAdded,
          description: 'DT_NEEDED library added: $added',
        ),
      );
    }

    for (final removed in oldSet.difference(newSet)) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.neededLibraryRemoved,
          description: 'DT_NEEDED library removed: $removed',
        ),
      );
    }
  }

  void _compareSections(
    ElfFile oldFile,
    ElfFile newFile,
    List<ElfDifference> differences,
  ) {
    bool isIgnoredStructural(ElfSection s) =>
        s.type == ElfSectionType.shtNull ||
        s.name.isEmpty ||
        s.name == '.note.gnu.build-id' ||
        s.name == '.gnu_debuglink' ||
        s.name.startsWith('.debug_') ||
        s.name == '.shstrtab' ||
        s.name == '.dynstr' ||
        s.name == '.strtab' ||
        s.name == '.dynsym' ||
        s.name == '.symtab' ||
        s.name == '.dynamic' ||
        s.name == '.hash' ||
        s.name == '.gnu.hash';

    final oldFiltered = [
      for (final s in oldFile.sections)
        if (!isIgnoredStructural(s)) s,
    ];
    final newFiltered = [
      for (final s in newFile.sections)
        if (!isIgnoredStructural(s)) s,
    ];

    final oldMap = {for (final s in oldFiltered) s.name: s};
    final newMap = {for (final s in newFiltered) s.name: s};

    final oldNames = oldMap.keys.toSet();
    final newNames = newMap.keys.toSet();

    for (final added in newNames.difference(oldNames)) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.sectionAdded,
          description: 'Section added: $added',
        ),
      );
    }

    for (final removed in oldNames.difference(newNames)) {
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.sectionRemoved,
          description: 'Section removed: $removed',
        ),
      );
    }

    // Check any custom non-debug sections not already covered by .text, .plt,
    // .rodata*, .data*, .init_array, .fini_array, or .bss.
    bool isCoveredByDedicatedCheck(String name, ElfSection s) =>
        name == '.text' ||
        name == '.plt' ||
        name == '.rodata' ||
        name.startsWith('.rodata.') ||
        name == '.data' ||
        name.startsWith('.data.') ||
        name == '.init_array' ||
        name == '.fini_array' ||
        name == '.bss' ||
        s.isNoBits;

    for (final name in oldNames.intersection(newNames)) {
      final oldSect = oldMap[name];
      final newSect = newMap[name];
      if (oldSect == null || newSect == null) continue;
      if (isCoveredByDedicatedCheck(name, oldSect)) continue;

      if (!_bytesEqual(oldSect.bytes, newSect.bytes)) {
        final kind = oldSect.isExecutable
            ? ElfDifferenceKind.functionCodeChanged
            : (oldSect.isWritable
                  ? ElfDifferenceKind.dataChanged
                  : ElfDifferenceKind.rodataChanged);
        differences.add(
          ElfDifference(
            kind: kind,
            description: 'Section payload changed: $name',
          ),
        );
      }
    }

    // If the set of non-debug sections is identical but their order in the
    // section header table changed, record a safe debugInfoChanged difference.
    if (oldNames.length == newNames.length && oldNames.containsAll(newNames)) {
      final oldOrder = [for (final s in oldFiltered) s.name];
      final newOrder = [for (final s in newFiltered) s.name];
      if (!_listEquals(oldOrder, newOrder)) {
        differences.add(
          const ElfDifference(
            kind: ElfDifferenceKind.debugInfoChanged,
            description: 'Section header table ordering changed',
          ),
        );
      }
    }
  }

  void _compareNamedByteMaps({
    required Map<String, Uint8List> oldMap,
    required Map<String, Uint8List> newMap,
    required ElfDifferenceKind kind,
    required String label,
    required List<ElfDifference> differences,
  }) {
    final commonKeys = oldMap.keys.toSet().intersection(newMap.keys.toSet());
    for (final key in commonKeys) {
      final oldBytes = oldMap[key];
      final newBytes = newMap[key];
      if (oldBytes != null &&
          newBytes != null &&
          !_bytesEqual(oldBytes, newBytes)) {
        differences.add(
          ElfDifference(
            kind: kind,
            description: '$label payload changed: $key',
          ),
        );
      }
    }
  }

  Set<String> _compareSymbols({
    required ElfFile oldFile,
    required ElfFile newFile,
    required List<ElfDifference> differences,
  }) {
    final oldMap = _collectSemanticSymbols(oldFile.dynamicSymbols);
    final newMap = _collectSemanticSymbols(newFile.dynamicSymbols);

    final oldNames = oldMap.keys.toSet();
    final newNames = newMap.keys.toSet();
    final reported = <String>{};

    for (final added in newNames.difference(oldNames)) {
      reported.add(added);
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.symbolAdded,
          description: 'Dynamic symbol added: $added',
        ),
      );
    }

    for (final removed in oldNames.difference(newNames)) {
      reported.add(removed);
      differences.add(
        ElfDifference(
          kind: ElfDifferenceKind.symbolRemoved,
          description: 'Dynamic symbol removed: $removed',
        ),
      );
    }

    for (final name in oldNames.intersection(newNames)) {
      final oldSym = oldMap[name];
      final newSym = newMap[name];
      if (oldSym == null || newSym == null) continue;
      final oldDesc = oldSym.describe();
      final newDesc = newSym.describe();
      if (oldDesc != newDesc) {
        differences.add(
          ElfDifference(
            kind: ElfDifferenceKind.symbolBindingChanged,
            description: 'Dynamic symbol changed: $name ($oldDesc -> $newDesc)',
          ),
        );
      }
    }

    return reported;
  }

  Map<String, _SemanticElfSymbol> _collectSemanticSymbols(
    List<ElfSymbol> symbols,
  ) {
    final result = <String, _SemanticElfSymbol>{};
    for (final sym in symbols) {
      if (sym.name.isEmpty ||
          sym.type == ElfSymbolType.section ||
          sym.type == ElfSymbolType.file) {
        continue;
      }
      result[sym.name] = _SemanticElfSymbol(
        name: sym.name,
        binding: sym.binding,
        type: sym.type,
        visibility: sym.visibility,
        size: sym.size,
        isUndefined: sym.isUndefined,
        sectionKey:
            sym.sectionName ??
            (sym.isUndefined
                ? 'UND'
                : 'shndx:0x${sym.shndx.toRadixString(16)}'),
      );
    }
    return result;
  }

  void _comparePlt(
    ElfSection? oldPlt,
    ElfSection? newPlt,
    List<ElfDifference> differences,
  ) {
    if (oldPlt != null &&
        newPlt != null &&
        !_bytesEqual(oldPlt.bytes, newPlt.bytes)) {
      differences.add(
        const ElfDifference(
          kind: ElfDifferenceKind.functionCodeChanged,
          description: 'Procedure linkage table (.plt) code changed',
        ),
      );
    }
  }

  void _compareFunctions({
    required ElfFile oldFile,
    required ElfFile newFile,
    required Set<String> reportedSymbols,
    required List<ElfDifference> differences,
  }) {
    final oldFuncs = {
      for (final f in oldFile.resolveFunctions()) f.name: f,
    };
    final newFuncs = {
      for (final f in newFile.resolveFunctions()) f.name: f,
    };

    final oldNames = oldFuncs.keys.toSet();
    final newNames = newFuncs.keys.toSet();

    for (final added in newNames.difference(oldNames)) {
      if (!reportedSymbols.contains(added)) {
        differences.add(
          ElfDifference(
            kind: ElfDifferenceKind.functionCodeChanged,
            description: 'Function added in .text: $added',
            codeDiff: const ElfCodeDiff(sizeChange: 'function body added'),
          ),
        );
      }
    }

    for (final removed in oldNames.difference(newNames)) {
      if (!reportedSymbols.contains(removed)) {
        differences.add(
          ElfDifference(
            kind: ElfDifferenceKind.functionCodeChanged,
            description: 'Function removed from .text: $removed',
            codeDiff: const ElfCodeDiff(sizeChange: 'function body removed'),
          ),
        );
      }
    }

    for (final name in oldNames.intersection(newNames)) {
      final oldFunc = oldFuncs[name];
      final newFunc = newFuncs[name];
      if (oldFunc == null || newFunc == null) continue;
      final codeDiff = _diffFunctionBodies(oldFunc, newFunc);
      if (codeDiff != null) {
        differences.add(
          ElfDifference(
            kind: ElfDifferenceKind.functionCodeChanged,
            description: 'Function code changed in $name',
            codeDiff: codeDiff,
          ),
        );
      }
    }
  }

  static ElfCodeDiff? _diffFunctionBodies(
    ElfFunction oldFunc,
    ElfFunction newFunc,
  ) {
    final sizeChange = oldFunc.size != newFunc.size
        ? 'size ${oldFunc.size} -> ${newFunc.size} bytes'
        : null;

    final oldCount = oldFunc.instructionCount;
    final newCount = newFunc.instructionCount;
    final shortest = oldCount < newCount ? oldCount : newCount;

    var head = 0;
    while (head < shortest &&
        oldFunc.tokensAt(head) == newFunc.tokensAt(head)) {
      head++;
    }

    var tail = 0;
    while (tail < shortest - head &&
        oldFunc.tokensAt(oldCount - 1 - tail) ==
            newFunc.tokensAt(newCount - 1 - tail)) {
      tail++;
    }

    final oldRegion = [
      for (var i = head; i < oldCount - tail; i++) oldFunc.instructionAt(i),
    ];
    final newRegion = [
      for (var i = head; i < newCount - tail; i++) newFunc.instructionAt(i),
    ];

    if (oldRegion.isEmpty && newRegion.isEmpty && sizeChange == null) {
      return null;
    }

    return ElfCodeDiff(
      oldRegion: oldRegion,
      newRegion: newRegion,
      sizeChange: sizeChange,
    );
  }

  static String _formatHeaderArch(ElfHeader header) {
    final bits = header.is64Bit ? 'ELF64' : 'ELF32';
    final endian = header.isLittleEndian ? 'LE' : 'BE';
    final machine = switch (header.machine) {
      ElfMachine.aarch64 => 'aarch64',
      ElfMachine.arm => 'arm',
      ElfMachine.x86_64 => 'x86_64',
      ElfMachine.x86 => 'x86',
      ElfMachine.riscv => 'riscv',
      _ => 'machine_0x${header.machine.toRadixString(16)}',
    };
    return '$bits-$endian-$machine(type=${header.fileType})';
  }

  static String _formatHex(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return '<none>';
    return [
      for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _nullableBytesEqual(Uint8List? a, Uint8List? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return _bytesEqual(a, b);
  }

  static bool _byteMapsEqual(
    Map<String, Uint8List> a,
    Map<String, Uint8List> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !_bytesEqual(entry.value, other)) return false;
    }
    return true;
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

@immutable
class _SemanticElfSymbol {
  const _SemanticElfSymbol({
    required this.name,
    required this.binding,
    required this.type,
    required this.visibility,
    required this.size,
    required this.isUndefined,
    required this.sectionKey,
  });

  final String name;
  final int binding;
  final int type;
  final int visibility;
  final int size;
  final bool isUndefined;
  final String sectionKey;

  String describe() {
    final bindStr = switch (binding) {
      ElfSymbolBinding.local => 'local',
      ElfSymbolBinding.global => 'global',
      ElfSymbolBinding.weak => 'weak',
      _ => 'bind_$binding',
    };
    final typeStr = switch (type) {
      ElfSymbolType.notype => 'notype',
      ElfSymbolType.object => 'object',
      ElfSymbolType.func => 'func',
      ElfSymbolType.common => 'common',
      ElfSymbolType.tls => 'tls',
      ElfSymbolType.gnuIfunc => 'ifunc',
      _ => 'type_$type',
    };
    final visStr = switch (visibility) {
      ElfSymbolVisibility.defaultVisibility => 'default',
      ElfSymbolVisibility.internal => 'internal',
      ElfSymbolVisibility.hidden => 'hidden',
      _ => 'protected',
    };
    final defStr = isUndefined ? 'undef' : 'def($sectionKey,size=$size)';
    return '$defStr,$bindStr,$typeStr,$visStr';
  }
}
