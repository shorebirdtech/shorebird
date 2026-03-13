// cspell:words uleb sleb
import 'dart:typed_data';

import 'package:shorebird_cli/src/archive_analysis/dex_parser.dart';

/// The kind of difference found between two DEX files.
enum DexDifferenceKind {
  /// Source file attribute changed (safe — build path difference).
  sourceFileChanged,

  /// A class was added.
  classAdded,

  /// A class was removed.
  classRemoved,

  /// A method was added to a class.
  methodAdded,

  /// A method was removed from a class.
  methodRemoved,

  /// A field was added to a class.
  fieldAdded,

  /// A field was removed from a class.
  fieldRemoved,

  /// Access flags changed on a class, method, or field.
  accessFlagsChanged,

  /// The superclass of a class changed.
  superclassChanged,

  /// The interface list of a class changed.
  interfacesChanged,

  /// Method bytecode changed.
  bytecodeChanged,

  /// Annotations changed.
  annotationsChanged,

  /// Static field initial values changed.
  staticValuesChanged;

  /// Whether this kind of difference is safe (does not affect runtime
  /// behavior).
  bool get isSafe => this == sourceFileChanged;
}

/// {@template dex_difference}
/// A single difference found between two DEX files.
/// {@endtemplate}
class DexDifference {
  /// {@macro dex_difference}
  const DexDifference({required this.kind, required this.description});

  /// The classification of this difference.
  final DexDifferenceKind kind;

  /// A human-readable description of the difference.
  final String description;
}

/// {@template dex_diff_result}
/// The result of comparing two DEX files.
/// {@endtemplate}
class DexDiffResult {
  /// {@macro dex_diff_result}
  const DexDiffResult({required this.differences});

  /// Creates an empty (identical) diff result.
  const DexDiffResult.identical() : differences = const [];

  /// All differences found between the two DEX files.
  final List<DexDifference> differences;

  /// Differences that are safe to ignore (e.g. source file paths).
  Iterable<DexDifference> get safeDifferences =>
      differences.where((d) => d.kind.isSafe);

  /// Differences that indicate real code changes.
  Iterable<DexDifference> get breakingDifferences =>
      differences.where((d) => !d.kind.isSafe);

  /// Whether all differences are safe to ignore.
  bool get isSafe => breakingDifferences.isEmpty;

  /// A human-readable summary of the differences.
  String describe() {
    final buffer = StringBuffer();
    final safe = safeDifferences.toList();
    final breaking = breakingDifferences.toList();

    if (safe.isNotEmpty) {
      buffer.writeln(
        'Safe differences (${safe.length}):',
      );
      for (final diff in safe) {
        buffer.writeln('  - ${diff.description}');
      }
    }

    if (breaking.isNotEmpty) {
      buffer.writeln(
        'Breaking differences (${breaking.length}):',
      );
      for (final diff in breaking) {
        buffer.writeln('  - ${diff.description}');
      }
    }

    return buffer.toString().trimRight();
  }
}

/// Index mappings between two DEX files, built from structurally resolved
/// tables. Used to remap raw index references when comparing bytecode,
/// annotations, and static values.
class _IndexMappings {
  _IndexMappings({
    required this.string,
    required this.type,
    required this.proto,
    required this.field,
    required this.method,
  });

  final Map<int, int> string;
  final Map<int, int> type;
  final Map<int, int> proto;
  final Map<int, int> field;
  final Map<int, int> method;
}

/// {@template dex_differ}
/// Compares two parsed [DexFile]s and produces a [DexDiffResult] describing
/// the semantic differences between them.
/// {@endtemplate}
class DexDiffer {
  /// {@macro dex_differ}
  const DexDiffer();

  /// Compares two DEX files and returns the differences.
  DexDiffResult diff(DexFile oldFile, DexFile newFile) {
    final differences = <DexDifference>[];

    // Build class maps keyed by type descriptor.
    final oldClasses = {
      for (final c in oldFile.classDefs) c.className: c,
    };
    final newClasses = {
      for (final c in newFile.classDefs) c.className: c,
    };

    final oldClassNames = oldClasses.keys.toSet();
    final newClassNames = newClasses.keys.toSet();

    // Detect added/removed classes.
    for (final added in newClassNames.difference(oldClassNames)) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.classAdded,
          description: 'Class added: $added',
        ),
      );
    }

    for (final removed in oldClassNames.difference(newClassNames)) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.classRemoved,
          description: 'Class removed: $removed',
        ),
      );
    }

    // Compare matched classes structurally.
    for (final name in oldClassNames.intersection(newClassNames)) {
      _compareClasses(oldClasses[name]!, newClasses[name]!, differences);
    }

    // If there are already breaking structural differences, no need to do
    // deeper comparison — we'll report breaking regardless.
    if (differences.any((d) => !d.kind.isSafe)) {
      return DexDiffResult(differences: differences);
    }

    // Structural tables match. Now compare bytecode, annotations, and static
    // values using index mappings to handle string-table reordering.
    final mappings = _buildMappings(oldFile, newFile);

    for (final name in oldClassNames.intersection(newClassNames)) {
      final oldClass = oldClasses[name]!;
      final newClass = newClasses[name]!;

      _compareCodeItems(
        name,
        oldClass,
        newClass,
        oldFile,
        newFile,
        mappings,
        differences,
      );

      _compareAnnotations(
        name,
        oldClass,
        newClass,
        oldFile,
        newFile,
        mappings,
        differences,
      );

      _compareStaticValues(
        name,
        oldClass,
        newClass,
        oldFile,
        newFile,
        mappings,
        differences,
      );
    }

    return DexDiffResult(differences: differences);
  }

  void _compareClasses(
    DexClassDef oldClass,
    DexClassDef newClass,
    List<DexDifference> differences,
  ) {
    final name = oldClass.className;

    if (oldClass.sourceFile != newClass.sourceFile) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.sourceFileChanged,
          description:
              '$name: source file changed from '
              '"${oldClass.sourceFile}" to "${newClass.sourceFile}"',
        ),
      );
    }

    if (oldClass.accessFlags != newClass.accessFlags) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.accessFlagsChanged,
          description:
              '$name: class access flags changed from '
              '0x${oldClass.accessFlags.toRadixString(16)} to '
              '0x${newClass.accessFlags.toRadixString(16)}',
        ),
      );
    }

    if (oldClass.superclass != newClass.superclass) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.superclassChanged,
          description:
              '$name: superclass changed from '
              '${oldClass.superclass} to ${newClass.superclass}',
        ),
      );
    }

    if (!_listEquals(oldClass.interfaces, newClass.interfaces)) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.interfacesChanged,
          description: '$name: interfaces changed',
        ),
      );
    }

    _compareMembers(
      className: name,
      oldData: oldClass.classData,
      newData: newClass.classData,
      extract: (data) => {
        for (final f in [...data.staticFields, ...data.instanceFields])
          '${f.field.className}.${f.field.fieldName}:${f.field.typeName}':
              f.accessFlags,
      },
      memberLabel: 'field',
      addedKind: DexDifferenceKind.fieldAdded,
      removedKind: DexDifferenceKind.fieldRemoved,
      differences: differences,
    );

    _compareMembers(
      className: name,
      oldData: oldClass.classData,
      newData: newClass.classData,
      extract: (data) => {
        for (final m in [...data.directMethods, ...data.virtualMethods])
          _methodKey(m): m.accessFlags,
      },
      memberLabel: 'method',
      addedKind: DexDifferenceKind.methodAdded,
      removedKind: DexDifferenceKind.methodRemoved,
      differences: differences,
    );
  }

  // -- Index mapping construction -------------------------------------------

  _IndexMappings _buildMappings(DexFile oldFile, DexFile newFile) {
    final stringMap = _buildStringMapping(oldFile, newFile);
    final typeMap = _buildValueMapping(
      oldFile.typeDescriptors,
      newFile.typeDescriptors,
    );
    final protoMap = _buildProtoMapping(oldFile, newFile);
    final fieldMap = _buildFieldMapping(oldFile, newFile);
    final methodMap = _buildMethodMapping(oldFile, newFile);

    return _IndexMappings(
      string: stringMap,
      type: typeMap,
      proto: protoMap,
      field: fieldMap,
      method: methodMap,
    );
  }

  Map<int, int> _buildStringMapping(DexFile oldFile, DexFile newFile) {
    final newIndex = <String, int>{};
    for (var i = 0; i < newFile.strings.length; i++) {
      newIndex[newFile.strings[i]] = i;
    }
    final mapping = <int, int>{};
    for (var i = 0; i < oldFile.strings.length; i++) {
      final newIdx = newIndex[oldFile.strings[i]];
      if (newIdx != null) mapping[i] = newIdx;
    }
    return mapping;
  }

  Map<int, int> _buildValueMapping(List<String> oldVals, List<String> newVals) {
    final newIndex = <String, int>{};
    for (var i = 0; i < newVals.length; i++) {
      newIndex[newVals[i]] = i;
    }
    final mapping = <int, int>{};
    for (var i = 0; i < oldVals.length; i++) {
      final newIdx = newIndex[oldVals[i]];
      if (newIdx != null) mapping[i] = newIdx;
    }
    return mapping;
  }

  Map<int, int> _buildProtoMapping(DexFile oldFile, DexFile newFile) {
    String protoKey(DexProtoId p) =>
        '${p.returnType}(${p.parameterTypes.join(',')})';
    final newIndex = <String, int>{};
    for (var i = 0; i < newFile.protoIds.length; i++) {
      newIndex[protoKey(newFile.protoIds[i])] = i;
    }
    final mapping = <int, int>{};
    for (var i = 0; i < oldFile.protoIds.length; i++) {
      final newIdx = newIndex[protoKey(oldFile.protoIds[i])];
      if (newIdx != null) mapping[i] = newIdx;
    }
    return mapping;
  }

  Map<int, int> _buildFieldMapping(DexFile oldFile, DexFile newFile) {
    String fieldKey(DexFieldId f) =>
        '${f.className}.${f.fieldName}:${f.typeName}';
    final newIndex = <String, int>{};
    for (var i = 0; i < newFile.fieldIds.length; i++) {
      newIndex[fieldKey(newFile.fieldIds[i])] = i;
    }
    final mapping = <int, int>{};
    for (var i = 0; i < oldFile.fieldIds.length; i++) {
      final newIdx = newIndex[fieldKey(oldFile.fieldIds[i])];
      if (newIdx != null) mapping[i] = newIdx;
    }
    return mapping;
  }

  Map<int, int> _buildMethodMapping(DexFile oldFile, DexFile newFile) {
    String methodKey(DexMethodId m) {
      final params = m.proto.parameterTypes.join(',');
      return '${m.className}.${m.methodName}($params)${m.proto.returnType}';
    }

    final newIndex = <String, int>{};
    for (var i = 0; i < newFile.methodIds.length; i++) {
      newIndex[methodKey(newFile.methodIds[i])] = i;
    }
    final mapping = <int, int>{};
    for (var i = 0; i < oldFile.methodIds.length; i++) {
      final newIdx = newIndex[methodKey(oldFile.methodIds[i])];
      if (newIdx != null) mapping[i] = newIdx;
    }
    return mapping;
  }

  // -- Code item comparison -------------------------------------------------

  void _compareCodeItems(
    String className,
    DexClassDef oldClass,
    DexClassDef newClass,
    DexFile oldFile,
    DexFile newFile,
    _IndexMappings mappings,
    List<DexDifference> differences,
  ) {
    final oldMethods = <String, DexEncodedMethod>{};
    final newMethods = <String, DexEncodedMethod>{};

    if (oldClass.classData != null) {
      for (final m in [
        ...oldClass.classData!.directMethods,
        ...oldClass.classData!.virtualMethods,
      ]) {
        oldMethods[_methodKey(m)] = m;
      }
    }
    if (newClass.classData != null) {
      for (final m in [
        ...newClass.classData!.directMethods,
        ...newClass.classData!.virtualMethods,
      ]) {
        newMethods[_methodKey(m)] = m;
      }
    }

    for (final key in oldMethods.keys) {
      final oldMethod = oldMethods[key]!;
      final newMethod = newMethods[key];
      if (newMethod == null) continue; // already caught structurally

      if (!_codeItemsEqual(
        oldFile.bytes,
        oldMethod.codeOffset,
        newFile.bytes,
        newMethod.codeOffset,
        mappings,
      )) {
        differences.add(
          DexDifference(
            kind: DexDifferenceKind.bytecodeChanged,
            description: '$className: bytecode changed in $key',
          ),
        );
      }
    }
  }

  bool _codeItemsEqual(
    Uint8List oldBytes,
    int oldOff,
    Uint8List newBytes,
    int newOff,
    _IndexMappings mappings,
  ) {
    // Both abstract/native.
    if (oldOff == 0 && newOff == 0) return true;
    // One has code, the other doesn't.
    if (oldOff == 0 || newOff == 0) return false;

    final oldRegs = DexParser.readUint16(oldBytes, oldOff);
    final newRegs = DexParser.readUint16(newBytes, newOff);
    final oldIns = DexParser.readUint16(oldBytes, oldOff + 2);
    final newIns = DexParser.readUint16(newBytes, newOff + 2);
    final oldOuts = DexParser.readUint16(oldBytes, oldOff + 4);
    final newOuts = DexParser.readUint16(newBytes, newOff + 4);
    final oldTries = DexParser.readUint16(oldBytes, oldOff + 6);
    final newTries = DexParser.readUint16(newBytes, newOff + 6);
    // debug_info_off at +8 — skip (safe to differ).
    final oldInsnsSize = DexParser.readUint32(oldBytes, oldOff + 12);
    final newInsnsSize = DexParser.readUint32(newBytes, newOff + 12);

    if (oldRegs != newRegs ||
        oldIns != newIns ||
        oldOuts != newOuts ||
        oldTries != newTries ||
        oldInsnsSize != newInsnsSize) {
      return false;
    }

    // Compare instructions with index remapping.
    final oldInsnsOff = oldOff + 16;
    final newInsnsOff = newOff + 16;
    if (!_instructionsEqual(
      oldBytes,
      oldInsnsOff,
      newBytes,
      newInsnsOff,
      oldInsnsSize,
      mappings,
    )) {
      return false;
    }

    // Compare try/catch blocks.
    if (oldTries > 0) {
      // Padding after insns if insns_size is odd.
      final pad = (oldInsnsSize % 2 != 0) ? 2 : 0;
      final oldTriesOff = oldInsnsOff + oldInsnsSize * 2 + pad;
      final newTriesOff = newInsnsOff + newInsnsSize * 2 + pad;

      if (!_tryCatchEqual(
        oldBytes,
        oldTriesOff,
        newBytes,
        newTriesOff,
        oldTries,
        mappings,
      )) {
        return false;
      }
    }

    return true;
  }

  bool _instructionsEqual(
    Uint8List oldBytes,
    int oldOff,
    Uint8List newBytes,
    int newOff,
    int insnsSize,
    _IndexMappings mappings,
  ) {
    var pos = 0;
    while (pos < insnsSize) {
      final oldUnit = DexParser.readUint16(oldBytes, oldOff + pos * 2);
      final opcode = oldUnit & 0xFF;

      // Handle pseudo-instructions (payloads).
      if (opcode == 0x00) {
        final payloadSize = _payloadSize(oldBytes, oldOff + pos * 2);
        if (payloadSize > 0) {
          // Payloads contain no pool indices; compare byte-for-byte.
          for (var i = 0; i < payloadSize; i++) {
            final oUnit =
                DexParser.readUint16(oldBytes, oldOff + (pos + i) * 2);
            final nUnit =
                DexParser.readUint16(newBytes, newOff + (pos + i) * 2);
            if (oUnit != nUnit) return false;
          }
          pos += payloadSize;
          continue;
        }
      }

      final size = _opcodeSizes[opcode];
      final indexInfo = _opcodeIndexInfo[opcode];

      if (indexInfo == null) {
        // No pool references — compare all units directly.
        for (var i = 0; i < size; i++) {
          final o = DexParser.readUint16(oldBytes, oldOff + (pos + i) * 2);
          final n = DexParser.readUint16(newBytes, newOff + (pos + i) * 2);
          if (o != n) return false;
        }
      } else {
        // Compare non-index units directly; remap index units.
        for (var i = 0; i < size; i++) {
          final o = DexParser.readUint16(oldBytes, oldOff + (pos + i) * 2);
          final n = DexParser.readUint16(newBytes, newOff + (pos + i) * 2);

          final ref = indexInfo.refs.where((r) => r.unitOffset == i);
          if (ref.isEmpty) {
            if (o != n) return false;
          } else {
            final r = ref.first;
            if (r.is32Bit) {
              // 32-bit index spans this unit and the next.
              final oHi =
                  DexParser.readUint16(oldBytes, oldOff + (pos + i + 1) * 2);
              final nHi =
                  DexParser.readUint16(newBytes, newOff + (pos + i + 1) * 2);
              final oldIdx = o | (oHi << 16);
              final newIdx = n | (nHi << 16);
              final mapped = _mapIndex(oldIdx, r.pool, mappings);
              if (mapped != newIdx) return false;
              i++; // skip the next unit (already consumed)
            } else {
              final mapped = _mapIndex(o, r.pool, mappings);
              if (mapped != n) return false;
            }
          }
        }
      }
      pos += size;
    }
    return true;
  }

  bool _tryCatchEqual(
    Uint8List oldBytes,
    int oldOff,
    Uint8List newBytes,
    int newOff,
    int triesSize,
    _IndexMappings mappings,
  ) {
    // try_item: uint32 start_addr, ushort insn_count, ushort handler_off
    // Compare try_items byte-for-byte (no pool indices in try_items).
    for (var i = 0; i < triesSize; i++) {
      final o = oldOff + i * 8;
      final n = newOff + i * 8;
      for (var b = 0; b < 8; b++) {
        if (oldBytes[o + b] != newBytes[n + b]) return false;
      }
    }

    // encoded_catch_handler_list follows the try_items.
    final handlersOff = triesSize * 8;
    var oldPos = oldOff + handlersOff;
    var newPos = newOff + handlersOff;

    final (handlerListSize, hb1) = DexParser.readUleb128(oldBytes, oldPos);
    final (newHandlerListSize, hb2) = DexParser.readUleb128(newBytes, newPos);
    if (handlerListSize != newHandlerListSize) return false;
    oldPos += hb1;
    newPos += hb2;

    for (var i = 0; i < handlerListSize; i++) {
      // size is sleb128 — negative means has catch-all.
      final (oldSize, sb1) = DexParser.readSleb128(oldBytes, oldPos);
      final (newSize, sb2) = DexParser.readSleb128(newBytes, newPos);
      if (oldSize != newSize) return false;
      oldPos += sb1;
      newPos += sb2;

      final pairCount = oldSize.abs();
      for (var j = 0; j < pairCount; j++) {
        // type_idx (uleb128) — needs remapping.
        final (oldTypeIdx, tb1) = DexParser.readUleb128(oldBytes, oldPos);
        final (newTypeIdx, tb2) = DexParser.readUleb128(newBytes, newPos);
        oldPos += tb1;
        newPos += tb2;
        final mapped = _mapIndex(oldTypeIdx, _PoolKind.type, mappings);
        if (mapped != newTypeIdx) return false;

        // addr (uleb128) — no remapping.
        final (oldAddr, ab1) = DexParser.readUleb128(oldBytes, oldPos);
        final (newAddr, ab2) = DexParser.readUleb128(newBytes, newPos);
        oldPos += ab1;
        newPos += ab2;
        if (oldAddr != newAddr) return false;
      }

      if (oldSize <= 0) {
        // catch_all_addr (uleb128).
        final (oldAddr, ab1) = DexParser.readUleb128(oldBytes, oldPos);
        final (newAddr, ab2) = DexParser.readUleb128(newBytes, newPos);
        oldPos += ab1;
        newPos += ab2;
        if (oldAddr != newAddr) return false;
      }
    }
    return true;
  }

  // -- Annotation comparison ------------------------------------------------

  void _compareAnnotations(
    String className,
    DexClassDef oldClass,
    DexClassDef newClass,
    DexFile oldFile,
    DexFile newFile,
    _IndexMappings mappings,
    List<DexDifference> differences,
  ) {
    if (oldClass.annotationsOff == 0 && newClass.annotationsOff == 0) return;

    if (oldClass.annotationsOff == 0 || newClass.annotationsOff == 0) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.annotationsChanged,
          description: '$className: annotations added or removed',
        ),
      );
      return;
    }

    // Canonicalize annotations from both files and compare.
    final oldCanon = _canonicalizeAnnotationDirectory(
      oldFile.bytes,
      oldClass.annotationsOff,
      oldFile,
    );
    final newCanon = _canonicalizeAnnotationDirectory(
      newFile.bytes,
      newClass.annotationsOff,
      newFile,
    );

    if (oldCanon != newCanon) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.annotationsChanged,
          description: '$className: annotations changed',
        ),
      );
    }
  }

  /// Produces a canonical string representation of an annotation directory
  /// with all indices resolved to their string values.
  String _canonicalizeAnnotationDirectory(
    Uint8List bytes,
    int off,
    DexFile file,
  ) {
    final buf = StringBuffer();
    final classAnnotationsOff = DexParser.readUint32(bytes, off);
    final fieldsSize = DexParser.readUint32(bytes, off + 4);
    final methodsSize = DexParser.readUint32(bytes, off + 8);
    final paramsSize = DexParser.readUint32(bytes, off + 12);

    if (classAnnotationsOff != 0) {
      buf.writeln(
        'CLASS:${_canonicalizeAnnotationSet(bytes, classAnnotationsOff, file)}',
      );
    }

    var pos = off + 16;
    for (var i = 0; i < fieldsSize; i++) {
      final fieldIdx = DexParser.readUint32(bytes, pos);
      final annotOff = DexParser.readUint32(bytes, pos + 4);
      pos += 8;
      final f = file.fieldIds[fieldIdx];
      buf.writeln(
        'FIELD:${f.className}.${f.fieldName}:'
        '${_canonicalizeAnnotationSet(bytes, annotOff, file)}',
      );
    }

    for (var i = 0; i < methodsSize; i++) {
      final methodIdx = DexParser.readUint32(bytes, pos);
      final annotOff = DexParser.readUint32(bytes, pos + 4);
      pos += 8;
      final m = file.methodIds[methodIdx];
      final params = m.proto.parameterTypes.join(',');
      buf.writeln(
        'METHOD:${m.className}.${m.methodName}($params):'
        '${_canonicalizeAnnotationSet(bytes, annotOff, file)}',
      );
    }

    for (var i = 0; i < paramsSize; i++) {
      final methodIdx = DexParser.readUint32(bytes, pos);
      final annotOff = DexParser.readUint32(bytes, pos + 4);
      pos += 8;
      final m = file.methodIds[methodIdx];
      final params = m.proto.parameterTypes.join(',');
      buf.writeln(
        'PARAM:${m.className}.${m.methodName}($params):'
        '${_canonicalizeAnnotationSetRefList(bytes, annotOff, file)}',
      );
    }

    return buf.toString();
  }

  String _canonicalizeAnnotationSet(
    Uint8List bytes,
    int off,
    DexFile file,
  ) {
    final size = DexParser.readUint32(bytes, off);
    final items = <String>[];
    for (var i = 0; i < size; i++) {
      final annotOff = DexParser.readUint32(bytes, off + 4 + i * 4);
      items.add(_canonicalizeAnnotationItem(bytes, annotOff, file));
    }
    // Sort for order-independence (annotations are sorted by type_idx in the
    // file, but type_idx values may differ between builds).
    items.sort();
    return '{${items.join(';')}}';
  }

  String _canonicalizeAnnotationSetRefList(
    Uint8List bytes,
    int off,
    DexFile file,
  ) {
    final size = DexParser.readUint32(bytes, off);
    final items = <String>[];
    for (var i = 0; i < size; i++) {
      final setOff = DexParser.readUint32(bytes, off + 4 + i * 4);
      if (setOff == 0) {
        items.add('null');
      } else {
        items.add(_canonicalizeAnnotationSet(bytes, setOff, file));
      }
    }
    return '[${items.join(',')}]';
  }

  String _canonicalizeAnnotationItem(
    Uint8List bytes,
    int off,
    DexFile file,
  ) {
    final visibility = bytes[off];
    final (canon, _) = _canonicalizeEncodedAnnotation(bytes, off + 1, file);
    return 'v$visibility:$canon';
  }

  (String, int) _canonicalizeEncodedAnnotation(
    Uint8List bytes,
    int off,
    DexFile file,
  ) {
    var pos = off;
    final (typeIdx, tb) = DexParser.readUleb128(bytes, pos);
    pos += tb;
    final (size, sb) = DexParser.readUleb128(bytes, pos);
    pos += sb;

    final typeName = file.typeDescriptors[typeIdx];
    final elements = <String>[];
    for (var i = 0; i < size; i++) {
      final (nameIdx, nb) = DexParser.readUleb128(bytes, pos);
      pos += nb;
      final name = file.strings[nameIdx];
      final (value, consumed) = _canonicalizeEncodedValue(bytes, pos, file);
      pos += consumed;
      elements.add('$name=$value');
    }
    elements.sort();
    return ('$typeName(${elements.join(',')})', pos - off);
  }

  /// Returns (canonical_string, bytes_consumed).
  (String, int) _canonicalizeEncodedValue(
    Uint8List bytes,
    int off,
    DexFile file,
  ) {
    final header = bytes[off];
    final valueType = header & 0x1F;
    final valueArg = (header >> 5) & 0x07;
    final byteCount = valueArg + 1;
    var consumed = 1; // header byte

    switch (valueType) {
      case 0x00: // byte
        return ('B:${bytes[off + 1]}', 2);
      case 0x02: // short
      case 0x03: // char
      case 0x04: // int
      case 0x06: // long
      case 0x10: // float
      case 0x11: // double
        final val = _readSignExtended(bytes, off + 1, byteCount);
        consumed += byteCount;
        return ('N$valueType:$val', consumed);
      case 0x15: // method_type (proto@)
        final idx = _readUnsigned(bytes, off + 1, byteCount);
        consumed += byteCount;
        final p = file.protoIds[idx];
        return ('MT:${p.returnType}(${p.parameterTypes.join(',')})', consumed);
      case 0x16: // method_handle
        final idx = _readUnsigned(bytes, off + 1, byteCount);
        consumed += byteCount;
        return ('MH:$idx', consumed);
      case 0x17: // string
        final idx = _readUnsigned(bytes, off + 1, byteCount);
        consumed += byteCount;
        return ('S:${file.strings[idx]}', consumed);
      case 0x18: // type
        final idx = _readUnsigned(bytes, off + 1, byteCount);
        consumed += byteCount;
        return ('T:${file.typeDescriptors[idx]}', consumed);
      case 0x19: // field
        final idx = _readUnsigned(bytes, off + 1, byteCount);
        consumed += byteCount;
        final f = file.fieldIds[idx];
        return ('F:${f.className}.${f.fieldName}:${f.typeName}', consumed);
      case 0x1a: // method
        final idx = _readUnsigned(bytes, off + 1, byteCount);
        consumed += byteCount;
        final m = file.methodIds[idx];
        final params = m.proto.parameterTypes.join(',');
        return (
          'M:${m.className}.${m.methodName}($params)${m.proto.returnType}',
          consumed,
        );
      case 0x1b: // enum (field@)
        final idx = _readUnsigned(bytes, off + 1, byteCount);
        consumed += byteCount;
        final f = file.fieldIds[idx];
        return ('E:${f.className}.${f.fieldName}:${f.typeName}', consumed);
      case 0x1c: // array
        var pos = off + 1;
        final (size, sb) = DexParser.readUleb128(bytes, pos);
        pos += sb;
        final items = <String>[];
        for (var i = 0; i < size; i++) {
          final (val, vc) = _canonicalizeEncodedValue(bytes, pos, file);
          pos += vc;
          items.add(val);
        }
        return ('A:[${items.join(',')}]', pos - off);
      case 0x1d: // annotation
        final (canon, ac) = _canonicalizeEncodedAnnotation(
          bytes,
          off + 1,
          file,
        );
        return ('@:$canon', 1 + ac);
      case 0x1e: // null
        return ('NULL', 1);
      case 0x1f: // boolean
        return ('BOOL:$valueArg', 1);
      default:
        // Unknown value type — include raw bytes for safety.
        final rawBytes = bytes.sublist(off + 1, off + 1 + byteCount);
        consumed += byteCount;
        return ('?$valueType:$rawBytes', consumed);
    }
  }

  // -- Static values comparison ---------------------------------------------

  void _compareStaticValues(
    String className,
    DexClassDef oldClass,
    DexClassDef newClass,
    DexFile oldFile,
    DexFile newFile,
    _IndexMappings mappings,
    List<DexDifference> differences,
  ) {
    if (oldClass.staticValuesOff == 0 && newClass.staticValuesOff == 0) return;

    if (oldClass.staticValuesOff == 0 || newClass.staticValuesOff == 0) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.staticValuesChanged,
          description: '$className: static field initial values changed',
        ),
      );
      return;
    }

    final oldCanon = _canonicalizeEncodedArray(
      oldFile.bytes,
      oldClass.staticValuesOff,
      oldFile,
    );
    final newCanon = _canonicalizeEncodedArray(
      newFile.bytes,
      newClass.staticValuesOff,
      newFile,
    );

    if (oldCanon != newCanon) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.staticValuesChanged,
          description: '$className: static field initial values changed',
        ),
      );
    }
  }

  String _canonicalizeEncodedArray(Uint8List bytes, int off, DexFile file) {
    var pos = off;
    final (size, sb) = DexParser.readUleb128(bytes, pos);
    pos += sb;
    final items = <String>[];
    for (var i = 0; i < size; i++) {
      final (val, consumed) = _canonicalizeEncodedValue(bytes, pos, file);
      pos += consumed;
      items.add(val);
    }
    return items.join(',');
  }

  // -- Member comparison (shared helper) ------------------------------------

  void _compareMembers({
    required String className,
    required DexClassData? oldData,
    required DexClassData? newData,
    required Map<String, int> Function(DexClassData) extract,
    required String memberLabel,
    required DexDifferenceKind addedKind,
    required DexDifferenceKind removedKind,
    required List<DexDifference> differences,
  }) {
    final oldMembers = oldData != null ? extract(oldData) : <String, int>{};
    final newMembers = newData != null ? extract(newData) : <String, int>{};

    final oldKeys = oldMembers.keys.toSet();
    final newKeys = newMembers.keys.toSet();

    for (final added in newKeys.difference(oldKeys)) {
      differences.add(
        DexDifference(
          kind: addedKind,
          description: '$className: $memberLabel added: $added',
        ),
      );
    }

    for (final removed in oldKeys.difference(newKeys)) {
      differences.add(
        DexDifference(
          kind: removedKind,
          description: '$className: $memberLabel removed: $removed',
        ),
      );
    }

    for (final common in oldKeys.intersection(newKeys)) {
      if (oldMembers[common] != newMembers[common]) {
        differences.add(
          DexDifference(
            kind: DexDifferenceKind.accessFlagsChanged,
            description:
                '$className: $memberLabel $common access flags changed '
                'from 0x${oldMembers[common]!.toRadixString(16)} '
                'to 0x${newMembers[common]!.toRadixString(16)}',
          ),
        );
      }
    }
  }

  // -- Utility methods ------------------------------------------------------

  static String _methodKey(DexEncodedMethod m) {
    final params = m.method.proto.parameterTypes.join(', ');
    return '${m.method.className}.${m.method.methodName}'
        '($params)${m.method.proto.returnType}';
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int _mapIndex(int oldIdx, _PoolKind pool, _IndexMappings mappings) {
    final map = switch (pool) {
      _PoolKind.string => mappings.string,
      _PoolKind.type => mappings.type,
      _PoolKind.field => mappings.field,
      _PoolKind.method => mappings.method,
      _PoolKind.proto => mappings.proto,
      // Call-site and method-handle tables are not reordered by string changes.
      _PoolKind.callSite || _PoolKind.methodHandle => null,
    };
    if (map == null) return oldIdx;
    return map[oldIdx] ?? oldIdx;
  }

  int _readUnsigned(Uint8List bytes, int off, int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value |= bytes[off + i] << (i * 8);
    }
    return value;
  }

  int _readSignExtended(Uint8List bytes, int off, int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value |= bytes[off + i] << (i * 8);
    }
    // Sign-extend if high bit is set.
    final shift = count * 8;
    if (shift < 64 && (value & (1 << (shift - 1))) != 0) {
      value |= -(1 << shift);
    }
    return value;
  }

  /// Returns the size of a payload pseudo-instruction in 16-bit units,
  /// or 0 if the unit at [off] is not a payload identifier.
  int _payloadSize(Uint8List bytes, int off) {
    final ident = DexParser.readUint16(bytes, off);
    switch (ident) {
      case 0x0100: // packed-switch-payload
        final size = DexParser.readUint16(bytes, off + 2);
        return 4 + size * 2;
      case 0x0200: // sparse-switch-payload
        final size = DexParser.readUint16(bytes, off + 2);
        return 2 + size * 4;
      case 0x0300: // fill-array-data-payload
        final elementWidth = DexParser.readUint16(bytes, off + 2);
        final size = DexParser.readUint32(bytes, off + 4);
        final totalBytes = size * elementWidth;
        return 4 + ((totalBytes + 1) ~/ 2);
      default:
        return 0;
    }
  }
}

// -- Opcode tables ----------------------------------------------------------

/// Pool kinds for index references in instructions.
enum _PoolKind { string, type, field, method, proto, callSite, methodHandle }

/// Describes a pool-index reference within a DEX instruction.
class _IndexRef {
  const _IndexRef(this.unitOffset, this.pool, {this.is32Bit = false});
  final int unitOffset;
  final _PoolKind pool;
  final bool is32Bit;
}

/// Opcode index info — which units carry pool references.
class _OpcodeIndexInfo {
  const _OpcodeIndexInfo(this.refs);
  final List<_IndexRef> refs;
}

// Instruction sizes by opcode (in 16-bit code units).
// cspell:disable
const _opcodeSizes = [
  1, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 1, 1, 1, 1, 1, // 0x00-0x0f
  1, 1, 1, 2, 3, 2, 2, 3, 5, 2, 2, 3, 2, 1, 1, 2, // 0x10-0x1f
  2, 1, 2, 2, 3, 3, 3, 1, 1, 2, 3, 3, 3, 2, 2, 2, // 0x20-0x2f
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, // 0x30-0x3f
  1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0x40-0x4f
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0x50-0x5f
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, // 0x60-0x6f
  3, 3, 3, 1, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, // 0x70-0x7f
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0x80-0x8f
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0x90-0x9f
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0xa0-0xaf
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0xb0-0xbf
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0xc0-0xcf
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // 0xd0-0xdf
  2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0xe0-0xef
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4, 4, 3, 3, 2, 2, // 0xf0-0xff
];
// cspell:enable

/// Opcodes that carry pool-index references. Only these need index remapping.
const _opcodeIndexInfo = <int, _OpcodeIndexInfo>{
  // const-string (string@)
  0x1a: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.string)]),
  // const-string/jumbo (string@, 32-bit)
  0x1b: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.string, is32Bit: true)]),
  // const-class (type@)
  0x1c: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // check-cast (type@)
  0x1f: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // instance-of (type@)
  0x20: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // new-instance (type@)
  0x22: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // new-array (type@)
  0x23: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // filled-new-array (type@)
  0x24: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // filled-new-array/range (type@)
  0x25: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // iget (field@)
  0x52: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x53: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x54: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x55: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x56: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x57: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x58: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  // iput (field@)
  0x59: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x5a: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x5b: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x5c: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x5d: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x5e: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x5f: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  // sget (field@)
  0x60: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x61: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x62: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x63: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x64: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x65: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x66: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  // sput (field@)
  0x67: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x68: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x69: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x6a: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x6b: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x6c: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  0x6d: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.field)]),
  // invoke-virtual through invoke-interface (method@)
  0x6e: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x6f: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x70: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x71: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x72: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  // invoke-virtual/range through invoke-interface/range (method@)
  0x74: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x75: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x76: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x77: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  0x78: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.method)]),
  // invoke-polymorphic (method@ + proto@)
  0xfa: _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.method),
    _IndexRef(3, _PoolKind.proto),
  ]),
  // invoke-polymorphic/range (method@ + proto@)
  0xfb: _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.method),
    _IndexRef(3, _PoolKind.proto),
  ]),
  // invoke-custom (call_site@)
  0xfc: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.callSite)]),
  // invoke-custom/range (call_site@)
  0xfd: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.callSite)]),
  // const-method-handle (method_handle@)
  0xfe: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.methodHandle)]),
  // const-method-type (proto@)
  0xff: _OpcodeIndexInfo([_IndexRef(1, _PoolKind.proto)]),
};
