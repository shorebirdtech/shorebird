// cspell:words chkstk cstring cstrings dsym dsyms dylib dylibs funcs linkedit
// cspell:words ltmp methname objc pext reexport symtab undetailed
import 'dart:typed_data';

import 'package:macho/src/macho_parser.dart';
import 'package:meta/meta.dart';

/// The classification of a semantic difference between two Mach-O binaries.
enum MachODifferenceKind {
  /// `LC_UUID` changed (safe — regenerated per build).
  uuidChanged,

  /// `LC_CODE_SIGNATURE` or `__LINKEDIT` trailing alignment padding changed
  /// (safe — signing/linker layout noise).
  codeSignaturePaddingChanged,

  /// Unused `___chkstk_darwin` undefined symbol entry added or removed
  /// (safe — non-deterministic Xcode linker emission when unreferenced).
  chkstkDarwinChanged,

  /// DWARF / `N_OSO` compile-directory or object-file path string changed
  /// (safe — build machine path difference).
  debugPathChanged,

  /// A defined or imported symbol was added.
  symbolAdded,

  /// A defined or imported symbol was removed.
  symbolRemoved,

  /// A symbol's binding, visibility, type, or defining section changed.
  symbolBindingChanged,

  /// Machine code instructions in `__TEXT,__text` changed.
  functionCodeChanged,

  /// An Objective-C class (`__objc_classname`) was added.
  objcClassAdded,

  /// An Objective-C class (`__objc_classname`) was removed.
  objcClassRemoved,

  /// An Objective-C selector (`__objc_methname`) was added.
  objcSelectorAdded,

  /// An Objective-C selector (`__objc_methname`) was removed.
  objcSelectorRemoved,

  /// A Swift nominal type, protocol, or field descriptor section
  /// (`__swift5_*`) was added, removed, or modified.
  swiftDescriptorChanged,

  /// A C string literal in `__TEXT,__cstring` was added, removed, or modified.
  cstringLiteralChanged,

  /// A linked dynamic library (`LC_LOAD_DYLIB`, etc.) was added.
  dylibAdded,

  /// A linked dynamic library (`LC_LOAD_DYLIB`, etc.) was removed.
  dylibRemoved,

  /// A linked dynamic library's version or linkage kind changed.
  dylibVersionChanged,

  /// A Mach-O section was added.
  sectionAdded,

  /// A Mach-O section was removed.
  sectionRemoved,

  /// Constant or initialized data (`__DATA,__const`, `__DATA,__data`, etc.)
  /// changed.
  dataChanged,

  /// A CPU architecture slice was added/removed or file type changed.
  architectureChanged,

  /// One or both binaries could not be parsed as valid Mach-O.
  unparseableBinary;

  /// Whether this kind of difference is safe to ignore during a patch check.
  bool get isSafe =>
      this == uuidChanged ||
      this == codeSignaturePaddingChanged ||
      this == chkstkDarwinChanged ||
      this == debugPathChanged;
}

/// {@template macho_difference}
/// A single semantic difference found between two Mach-O binaries.
/// {@endtemplate}
class MachODifference {
  /// {@macro macho_difference}
  const MachODifference({
    required this.kind,
    required this.description,
    this.codeDiff,
  });

  /// The classification of this difference.
  final MachODifferenceKind kind;

  /// A human-readable description of the difference.
  final String description;

  /// Instruction-level diff window when [kind] is
  /// [MachODifferenceKind.functionCodeChanged].
  final MachOCodeDiff? codeDiff;
}

/// {@template macho_code_diff}
/// Where two function bodies in `__TEXT,__text` disagree.
///
/// Spans from the end of the longest common instruction prefix to the start of
/// the longest common instruction suffix.
/// {@endtemplate}
class MachOCodeDiff {
  /// {@macro macho_code_diff}
  const MachOCodeDiff({
    this.oldRegion = const [],
    this.newRegion = const [],
    this.sizeChange,
  });

  /// Canonical instructions from the old function in the differing window.
  final List<MachOCanonicalInstruction> oldRegion;

  /// Canonical instructions from the new function in the differing window.
  final List<MachOCanonicalInstruction> newRegion;

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

    if (sizeChange != null) {
      buffer.writeln('      $sizeChange');
    }

    void writeSide(String marker, List<MachOCanonicalInstruction> region) {
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

/// {@template macho_diff_result}
/// The result of comparing two Mach-O binaries.
/// {@endtemplate}
class MachODiffResult {
  /// {@macro macho_diff_result}
  const MachODiffResult({required this.differences});

  /// Creates an empty (identical) diff result.
  const MachODiffResult.identical() : differences = const [];

  /// All differences found between the two Mach-O binaries.
  final List<MachODifference> differences;

  /// Differences that are safe build noise (e.g. `LC_UUID`, signature padding).
  Iterable<MachODifference> get safeDifferences =>
      differences.where((d) => d.kind.isSafe);

  /// Differences that indicate breaking native changes.
  Iterable<MachODifference> get breakingDifferences =>
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
    final detailed = differences.where((d) => d.codeDiff != null).toList();
    return detailed.length > defaultDetailedFunctionLimit ||
        detailed.any(
          (d) =>
              d.codeDiff!.exceeds(defaultCodeDiffLimit) ||
              d.codeDiff!.hasStringLiterals,
        );
  }

  /// Formats a human-readable summary of safe and breaking differences.
  String describe({bool showFullCodeDiff = false}) {
    final buffer = StringBuffer();
    final safe = safeDifferences.toList();
    final breaking = breakingDifferences.toList();

    var detailed = 0;
    var undetailed = 0;

    void writeDifference(MachODifference diff) {
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

/// {@template macho_differ}
/// Compares two Mach-O binaries and produces a [MachODiffResult] classifying
/// every semantic difference as safe build noise or a breaking native change.
/// {@endtemplate}
class MachODiffer {
  /// {@macro macho_differ}
  const MachODiffer();

  /// Parses [oldBytes] and [newBytes] and compares them.
  ///
  /// If either binary fails to parse, returns a breaking [MachODiffResult]
  /// containing [MachODifferenceKind.unparseableBinary] rather than throwing.
  MachODiffResult diffBytes(
    Uint8List oldBytes,
    Uint8List newBytes, {
    Uint8List? oldDsymBytes,
    Uint8List? newDsymBytes,
    MachOParser parser = const MachOParser(),
  }) {
    final MachOFile oldFile;
    final MachOFile newFile;
    try {
      oldFile = parser.parse(oldBytes);
      newFile = parser.parse(newBytes);
      // Catch all format/parse errors so malformed binaries fail closed.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return MachODiffResult(
        differences: [
          MachODifference(
            kind: MachODifferenceKind.unparseableBinary,
            description: 'Unparseable Mach-O binary: $e',
          ),
        ],
      );
    }

    MachOFile? oldDsym;
    MachOFile? newDsym;
    if (oldDsymBytes != null) {
      try {
        oldDsym = parser.parse(oldDsymBytes);
        // Ignore malformed companion dSYM without weakening binary diff.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
    if (newDsymBytes != null) {
      try {
        newDsym = parser.parse(newDsymBytes);
        // Ignore malformed companion dSYM without weakening binary diff.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }

    return diff(oldFile, newFile, oldDsym: oldDsym, newDsym: newDsym);
  }

  /// Compares two parsed [MachOFile]s (with optional companion [oldDsym] and
  /// [newDsym] debug symbol files) and returns a [MachODiffResult].
  MachODiffResult diff(
    MachOFile oldFile,
    MachOFile newFile, {
    MachOFile? oldDsym,
    MachOFile? newDsym,
  }) {
    final differences = <MachODifference>[];

    final oldSlices = {
      for (final s in oldFile.slices)
        _archKey(s.header.cpuType, s.header.cpuSubtype): s,
    };
    final newSlices = {
      for (final s in newFile.slices)
        _archKey(s.header.cpuType, s.header.cpuSubtype): s,
    };
    final oldDsymSlices = {
      if (oldDsym != null)
        for (final s in oldDsym.slices)
          _archKey(s.header.cpuType, s.header.cpuSubtype): s,
    };
    final newDsymSlices = {
      if (newDsym != null)
        for (final s in newDsym.slices)
          _archKey(s.header.cpuType, s.header.cpuSubtype): s,
    };

    final oldKeys = oldSlices.keys.toSet();
    final newKeys = newSlices.keys.toSet();

    for (final added in newKeys.difference(oldKeys)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.architectureChanged,
          description: 'Architecture slice added: $added',
        ),
      );
    }

    for (final removed in oldKeys.difference(newKeys)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.architectureChanged,
          description: 'Architecture slice removed: $removed',
        ),
      );
    }

    for (final key in oldKeys.intersection(newKeys)) {
      _diffSlices(
        oldSlices[key]!,
        newSlices[key]!,
        oldDsymSlice: oldDsymSlices[key],
        newDsymSlice: newDsymSlices[key],
        differences: differences,
      );
    }

    return MachODiffResult(differences: differences);
  }

  void _diffSlices(
    MachOSlice oldSlice,
    MachOSlice newSlice, {
    required MachOSlice? oldDsymSlice,
    required MachOSlice? newDsymSlice,
    required List<MachODifference> differences,
  }) {
    if (oldSlice.header.fileType != newSlice.header.fileType) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.architectureChanged,
          description:
              'Mach-O file type changed from '
              '0x${oldSlice.header.fileType.toRadixString(16)} to '
              '0x${newSlice.header.fileType.toRadixString(16)}',
        ),
      );
    }

    // 1. Safe checks: LC_UUID, DWARF compile paths, __LINKEDIT padding.
    if (!_nullableBytesEqual(oldSlice.uuid, newSlice.uuid)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.uuidChanged,
          description:
              'LC_UUID changed from ${_formatUuid(oldSlice.uuid)} to '
              '${_formatUuid(newSlice.uuid)}',
        ),
      );
    }

    final oldDwarfPaths = [
      ...oldSlice.dwarfCompilePaths,
      if (oldDsymSlice != null) ...oldDsymSlice.dwarfCompilePaths,
    ];
    final newDwarfPaths = [
      ...newSlice.dwarfCompilePaths,
      if (newDsymSlice != null) ...newDsymSlice.dwarfCompilePaths,
    ];
    if (!_listEquals(oldDwarfPaths, newDwarfPaths)) {
      differences.add(
        const MachODifference(
          kind: MachODifferenceKind.debugPathChanged,
          description: 'DWARF compile path strings changed',
        ),
      );
    }

    if (!_bytesEqual(
          oldSlice.linkeditPaddingBytes,
          newSlice.linkeditPaddingBytes,
        ) ||
        (oldSlice.codeSignature == null) != (newSlice.codeSignature == null)) {
      differences.add(
        const MachODifference(
          kind: MachODifferenceKind.codeSignaturePaddingChanged,
          description:
              'LC_CODE_SIGNATURE or __LINKEDIT alignment padding changed',
        ),
      );
    }

    // 2. Linked dylibs.
    _compareDylibs(oldSlice.dylibs, newSlice.dylibs, differences);

    // 3. Structural sections (excluding DWARF and symbol stubs).
    _compareSections(oldSlice.sections, newSlice.sections, differences);

    // 4. Objective-C classes and selectors.
    _compareStringSet(
      oldItems: oldSlice.objcClassNames,
      newItems: newSlice.objcClassNames,
      addedKind: MachODifferenceKind.objcClassAdded,
      removedKind: MachODifferenceKind.objcClassRemoved,
      label: 'Objective-C class',
      differences: differences,
    );

    _compareStringSet(
      oldItems: oldSlice.objcSelectors,
      newItems: newSlice.objcSelectors,
      addedKind: MachODifferenceKind.objcSelectorAdded,
      removedKind: MachODifferenceKind.objcSelectorRemoved,
      label: 'Objective-C selector',
      differences: differences,
    );

    // 5. Swift descriptors (__swift5_*).
    _compareSwiftSections(
      oldSlice.swiftSections,
      newSlice.swiftSections,
      differences,
    );

    // 6. C string literals (__TEXT,__cstring).
    _compareCstrings(oldSlice.cstrings, newSlice.cstrings, differences);

    // 7. Constant and initialized data (__DATA,__const, __DATA,__data, etc.).
    _compareConstSections(
      oldSlice.constSections,
      newSlice.constSections,
      differences,
    );

    // 8. Symbol table & export trie (with unused ___chkstk_darwin filter).
    final reportedSymbols = _compareSymbols(
      oldSlice: oldSlice,
      newSlice: newSlice,
      differences: differences,
    );

    // 9. Per-function __TEXT,__text instructions.
    _compareFunctions(
      oldSlice: oldSlice,
      newSlice: newSlice,
      oldDsymSlice: oldDsymSlice,
      newDsymSlice: newDsymSlice,
      reportedSymbols: reportedSymbols,
      differences: differences,
    );
  }

  void _compareDylibs(
    List<MachODylib> oldDylibs,
    List<MachODylib> newDylibs,
    List<MachODifference> differences,
  ) {
    final oldMap = {for (final d in oldDylibs) d.name: d};
    final newMap = {for (final d in newDylibs) d.name: d};

    final oldNames = oldMap.keys.toSet();
    final newNames = newMap.keys.toSet();

    for (final added in newNames.difference(oldNames)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.dylibAdded,
          description: 'Linked dylib added: $added',
        ),
      );
    }

    for (final removed in oldNames.difference(newNames)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.dylibRemoved,
          description: 'Linked dylib removed: $removed',
        ),
      );
    }

    for (final name in oldNames.intersection(newNames)) {
      final oldDylib = oldMap[name]!;
      final newDylib = newMap[name]!;
      if (oldDylib.currentVersion != newDylib.currentVersion ||
          oldDylib.compatibilityVersion != newDylib.compatibilityVersion ||
          oldDylib.cmd != newDylib.cmd) {
        final oldVer = MachODylib.formatVersion(oldDylib.currentVersion);
        final newVer = MachODylib.formatVersion(newDylib.currentVersion);
        final oldCompat = MachODylib.formatVersion(
          oldDylib.compatibilityVersion,
        );
        final newCompat = MachODylib.formatVersion(
          newDylib.compatibilityVersion,
        );
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.dylibVersionChanged,
            description:
                'Linked dylib changed: $name '
                '(version $oldVer -> $newVer, '
                'compat $oldCompat -> $newCompat, '
                'cmd 0x${oldDylib.cmd.toRadixString(16)} -> '
                '0x${newDylib.cmd.toRadixString(16)})',
          ),
        );
      }
    }
  }

  void _compareSections(
    List<MachOSection> oldSections,
    List<MachOSection> newSections,
    List<MachODifference> differences,
  ) {
    bool isTrackedSeparately(MachOSection s) =>
        s.segname == '__DWARF' ||
        s.sectname.startsWith('__swift5_') ||
        s.sectname == '__stubs' ||
        s.sectname == '__auth_stubs' ||
        s.sectname == '__stub_helper';

    final oldNames = {
      for (final s in oldSections)
        if (!isTrackedSeparately(s)) s.fullName,
    };
    final newNames = {
      for (final s in newSections)
        if (!isTrackedSeparately(s)) s.fullName,
    };

    for (final added in newNames.difference(oldNames)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.sectionAdded,
          description: 'Section added: $added',
        ),
      );
    }

    for (final removed in oldNames.difference(newNames)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.sectionRemoved,
          description: 'Section removed: $removed',
        ),
      );
    }
  }

  void _compareStringSet({
    required List<String> oldItems,
    required List<String> newItems,
    required MachODifferenceKind addedKind,
    required MachODifferenceKind removedKind,
    required String label,
    required List<MachODifference> differences,
  }) {
    final oldSet = oldItems.toSet();
    final newSet = newItems.toSet();

    for (final added in newSet.difference(oldSet)) {
      differences.add(
        MachODifference(
          kind: addedKind,
          description: '$label added: $added',
        ),
      );
    }

    for (final removed in oldSet.difference(newSet)) {
      differences.add(
        MachODifference(
          kind: removedKind,
          description: '$label removed: $removed',
        ),
      );
    }
  }

  void _compareSwiftSections(
    Map<String, Uint8List> oldSwift,
    Map<String, Uint8List> newSwift,
    List<MachODifference> differences,
  ) {
    final oldKeys = oldSwift.keys.toSet();
    final newKeys = newSwift.keys.toSet();

    for (final added in newKeys.difference(oldKeys)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.swiftDescriptorChanged,
          description: 'Swift descriptor section added: $added',
        ),
      );
    }

    for (final removed in oldKeys.difference(newKeys)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.swiftDescriptorChanged,
          description: 'Swift descriptor section removed: $removed',
        ),
      );
    }

    for (final key in oldKeys.intersection(newKeys)) {
      if (!_bytesEqual(oldSwift[key]!, newSwift[key]!)) {
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.swiftDescriptorChanged,
            description: 'Swift descriptor section changed: $key',
          ),
        );
      }
    }
  }

  void _compareCstrings(
    List<String> oldCstrings,
    List<String> newCstrings,
    List<MachODifference> differences,
  ) {
    final oldSet = oldCstrings.toSet();
    final newSet = newCstrings.toSet();

    for (final added in newSet.difference(oldSet)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.cstringLiteralChanged,
          description: 'C string literal added: "$added"',
        ),
      );
    }

    for (final removed in oldSet.difference(newSet)) {
      differences.add(
        MachODifference(
          kind: MachODifferenceKind.cstringLiteralChanged,
          description: 'C string literal removed: "$removed"',
        ),
      );
    }

    if (oldSet.length == newSet.length &&
        oldSet.containsAll(newSet) &&
        !_listEquals(oldCstrings, newCstrings)) {
      differences.add(
        const MachODifference(
          kind: MachODifferenceKind.cstringLiteralChanged,
          description: 'C string literals in __TEXT,__cstring changed',
        ),
      );
    }
  }

  void _compareConstSections(
    Map<String, Uint8List> oldConsts,
    Map<String, Uint8List> newConsts,
    List<MachODifference> differences,
  ) {
    final commonKeys = oldConsts.keys.toSet().intersection(
      newConsts.keys.toSet(),
    );
    for (final key in commonKeys) {
      if (!_bytesEqual(oldConsts[key]!, newConsts[key]!)) {
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.dataChanged,
            description: 'Data section payload changed: $key',
          ),
        );
      }
    }
  }

  Set<String> _compareSymbols({
    required MachOSlice oldSlice,
    required MachOSlice newSlice,
    required List<MachODifference> differences,
  }) {
    final oldMap = _collectSemanticSymbols(oldSlice);
    final newMap = _collectSemanticSymbols(newSlice);

    final oldNames = oldMap.keys.toSet();
    final newNames = newMap.keys.toSet();
    final reported = <String>{};

    for (final added in newNames.difference(oldNames)) {
      final sym = newMap[added]!;
      if (_isUnusedChkstkDarwin(sym, oldSlice, newSlice)) {
        differences.add(
          const MachODifference(
            kind: MachODifferenceKind.chkstkDarwinChanged,
            description: 'Unused ___chkstk_darwin undefined symbol entry added',
          ),
        );
      } else {
        reported.add(added);
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.symbolAdded,
            description: 'Symbol added: $added',
          ),
        );
      }
    }

    for (final removed in oldNames.difference(newNames)) {
      final sym = oldMap[removed]!;
      if (_isUnusedChkstkDarwin(sym, oldSlice, newSlice)) {
        differences.add(
          const MachODifference(
            kind: MachODifferenceKind.chkstkDarwinChanged,
            description:
                'Unused ___chkstk_darwin undefined symbol entry removed',
          ),
        );
      } else {
        reported.add(removed);
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.symbolRemoved,
            description: 'Symbol removed: $removed',
          ),
        );
      }
    }

    for (final name in oldNames.intersection(newNames)) {
      final oldSym = oldMap[name]!;
      final newSym = newMap[name]!;
      final oldDesc = oldSym.describe();
      final newDesc = newSym.describe();
      if (oldDesc != newDesc) {
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.symbolBindingChanged,
            description: 'Symbol binding changed: $name ($oldDesc -> $newDesc)',
          ),
        );
      }
    }

    return reported;
  }

  bool _isUnusedChkstkDarwin(
    _SemanticSymbol sym,
    MachOSlice oldSlice,
    MachOSlice newSlice,
  ) {
    return sym.name == '___chkstk_darwin' &&
        sym.isUndefined &&
        !sym.isExported &&
        !oldSlice.callsSymbol('___chkstk_darwin') &&
        !newSlice.callsSymbol('___chkstk_darwin');
  }

  Map<String, _SemanticSymbol> _collectSemanticSymbols(MachOSlice slice) {
    final result = <String, _SemanticSymbol>{};

    for (final sym in slice.symbols) {
      if (sym.isDebugStab || sym.name.isEmpty || sym.name.startsWith('ltmp')) {
        continue;
      }
      result[sym.name] = _SemanticSymbol(
        name: sym.name,
        isUndefined: sym.isUndefined,
        isExternal: sym.isExternal,
        isPrivateExternal: sym.isPrivateExternal,
        isWeakDef: sym.isWeakDef,
        sectionName: sym.sectionName,
        isExported: false,
        exportFlags: 0,
        reexportOrdinal: null,
        importedName: null,
      );
    }

    for (final exp in slice.exportedSymbols) {
      if (exp.name.isEmpty) continue;
      final existing = result[exp.name];
      if (existing != null) {
        result[exp.name] = existing.withExport(
          exportFlags: exp.flags,
          reexportOrdinal: exp.reexportOrdinal,
          importedName: exp.importedName,
        );
      } else {
        result[exp.name] = _SemanticSymbol(
          name: exp.name,
          isUndefined: false,
          isExternal: true,
          isPrivateExternal: false,
          isWeakDef: (exp.flags & 0x04) != 0,
          sectionName: exp.isReexport ? null : '__TEXT,__text',
          isExported: true,
          exportFlags: exp.flags,
          reexportOrdinal: exp.reexportOrdinal,
          importedName: exp.importedName,
        );
      }
    }

    return result;
  }

  void _compareFunctions({
    required MachOSlice oldSlice,
    required MachOSlice newSlice,
    required MachOSlice? oldDsymSlice,
    required MachOSlice? newDsymSlice,
    required Set<String> reportedSymbols,
    required List<MachODifference> differences,
  }) {
    final oldFuncs = {
      for (final f in oldSlice.resolveFunctions(dsymSlice: oldDsymSlice))
        f.name: f,
    };
    final newFuncs = {
      for (final f in newSlice.resolveFunctions(dsymSlice: newDsymSlice))
        f.name: f,
    };

    final oldNames = oldFuncs.keys.toSet();
    final newNames = newFuncs.keys.toSet();

    for (final added in newNames.difference(oldNames)) {
      if (!reportedSymbols.contains(added)) {
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.functionCodeChanged,
            description: 'Function added in __TEXT,__text: $added',
            codeDiff: const MachOCodeDiff(
              sizeChange: 'function body added',
            ),
          ),
        );
      }
    }

    for (final removed in oldNames.difference(newNames)) {
      if (!reportedSymbols.contains(removed)) {
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.functionCodeChanged,
            description: 'Function removed from __TEXT,__text: $removed',
            codeDiff: const MachOCodeDiff(
              sizeChange: 'function body removed',
            ),
          ),
        );
      }
    }

    for (final name in oldNames.intersection(newNames)) {
      final codeDiff = _diffFunctionBodies(oldFuncs[name]!, newFuncs[name]!);
      if (codeDiff != null) {
        differences.add(
          MachODifference(
            kind: MachODifferenceKind.functionCodeChanged,
            description: 'Function code changed in $name',
            codeDiff: codeDiff,
          ),
        );
      }
    }
  }

  static MachOCodeDiff? _diffFunctionBodies(
    MachOFunction oldFunc,
    MachOFunction newFunc,
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

    return MachOCodeDiff(
      oldRegion: oldRegion,
      newRegion: newRegion,
      sizeChange: sizeChange,
    );
  }

  static String _archKey(int cpuType, int cpuSubtype) {
    final archName = switch (cpuType) {
      MachOCpuType.arm64 => 'arm64',
      MachOCpuType.x86_64 => 'x86_64',
      _ => 'cpu_0x${cpuType.toRadixString(16)}',
    };
    return '$archName(0x${cpuSubtype.toRadixString(16)})';
  }

  static String _formatUuid(Uint8List? uuid) {
    if (uuid == null || uuid.length != 16) return '<none>';
    String hex(int start, int end) => [
      for (var i = start; i < end; i++)
        uuid[i].toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-'
        '${hex(8, 10)}-${hex(10, 16)}';
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
class _SemanticSymbol {
  const _SemanticSymbol({
    required this.name,
    required this.isUndefined,
    required this.isExternal,
    required this.isPrivateExternal,
    required this.isWeakDef,
    required this.sectionName,
    required this.isExported,
    required this.exportFlags,
    required this.reexportOrdinal,
    required this.importedName,
  });

  final String name;
  final bool isUndefined;
  final bool isExternal;
  final bool isPrivateExternal;
  final bool isWeakDef;
  final String? sectionName;
  final bool isExported;
  final int exportFlags;
  final int? reexportOrdinal;
  final String? importedName;

  _SemanticSymbol withExport({
    required int exportFlags,
    required int? reexportOrdinal,
    required String? importedName,
  }) {
    return _SemanticSymbol(
      name: name,
      isUndefined: isUndefined,
      isExternal: isExternal,
      isPrivateExternal: isPrivateExternal,
      isWeakDef: isWeakDef,
      sectionName: sectionName,
      isExported: true,
      exportFlags: exportFlags,
      reexportOrdinal: reexportOrdinal,
      importedName: importedName,
    );
  }

  String describe() {
    final parts = <String>[
      if (isUndefined) 'undef' else 'def(${sectionName ?? "abs"})',
      if (isExternal) 'ext' else 'local',
      if (isPrivateExternal) 'pext',
      if (isWeakDef) 'weak',
      if (isExported) 'export(0x${exportFlags.toRadixString(16)})',
      if (reexportOrdinal != null) 'reexport($reexportOrdinal:$importedName)',
    ];
    return parts.join(',');
  }
}
