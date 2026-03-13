// cspell:words uleb sleb
import 'dart:typed_data';

import 'package:dex/src/dex_parser.dart';

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

    final oldClasses = {
      for (final c in oldFile.classDefs) c.className: c,
    };
    final newClasses = {
      for (final c in newFile.classDefs) c.className: c,
    };

    final oldClassNames = oldClasses.keys.toSet();
    final newClassNames = newClasses.keys.toSet();

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

    final matched = oldClassNames.intersection(newClassNames);

    for (final name in matched) {
      _compareClassStructure(
        oldClasses[name]!,
        newClasses[name]!,
        differences,
      );
    }

    // If there are already breaking structural differences, no need to do
    // deeper comparison — we'll report breaking regardless.
    if (differences.any((d) => !d.kind.isSafe)) {
      return DexDiffResult(differences: differences);
    }

    // Structural tables match. Now compare bytecode, annotations, and
    // static values using index mappings to handle string-table
    // reordering.
    final ctx = _DiffContext(
      oldFile: oldFile,
      newFile: newFile,
      mappings: _buildMappings(oldFile, newFile),
    );

    for (final name in matched) {
      ctx.compareClassData(
        name,
        oldClasses[name]!,
        newClasses[name]!,
        differences,
      );
    }

    return DexDiffResult(differences: differences);
  }

  void _compareClassStructure(
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
          '${f.field.className}.${f.field.fieldName}'
              ':${f.field.typeName}': f.accessFlags,
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
        for (final m in [
          ...data.directMethods,
          ...data.virtualMethods,
        ])
          _methodKey(m): m.accessFlags,
      },
      memberLabel: 'method',
      addedKind: DexDifferenceKind.methodAdded,
      removedKind: DexDifferenceKind.methodRemoved,
      differences: differences,
    );
  }

  // -- Index mapping construction -----------------------------------------

  static _IndexMappings _buildMappings(
    DexFile oldFile,
    DexFile newFile,
  ) {
    Map<int, int> buildMapping<T>(
      List<T> oldItems,
      List<T> newItems,
      String Function(T) key,
    ) {
      final newIndex = <String, int>{};
      for (var i = 0; i < newItems.length; i++) {
        newIndex[key(newItems[i])] = i;
      }
      final mapping = <int, int>{};
      for (var i = 0; i < oldItems.length; i++) {
        final newIdx = newIndex[key(oldItems[i])];
        if (newIdx != null) mapping[i] = newIdx;
      }
      return mapping;
    }

    return _IndexMappings(
      string: buildMapping(
        oldFile.strings,
        newFile.strings,
        (s) => s,
      ),
      type: buildMapping(
        oldFile.typeDescriptors,
        newFile.typeDescriptors,
        (t) => t,
      ),
      proto: buildMapping(
        oldFile.protoIds,
        newFile.protoIds,
        (p) => '${p.returnType}(${p.parameterTypes.join(',')})',
      ),
      field: buildMapping(
        oldFile.fieldIds,
        newFile.fieldIds,
        (f) => '${f.className}.${f.fieldName}:${f.typeName}',
      ),
      method: buildMapping(
        oldFile.methodIds,
        newFile.methodIds,
        (m) {
          final params = m.proto.parameterTypes.join(',');
          return '${m.className}.${m.methodName}'
              '($params)${m.proto.returnType}';
        },
      ),
    );
  }

  // -- Member comparison (shared helper) ----------------------------------

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
    final oldMembers =
        oldData != null ? extract(oldData) : <String, int>{};
    final newMembers =
        newData != null ? extract(newData) : <String, int>{};

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
          description:
              '$className: $memberLabel removed: $removed',
        ),
      );
    }

    for (final common in oldKeys.intersection(newKeys)) {
      if (oldMembers[common] != newMembers[common]) {
        differences.add(
          DexDifference(
            kind: DexDifferenceKind.accessFlagsChanged,
            description:
                '$className: $memberLabel $common access flags '
                'changed from '
                '0x${oldMembers[common]!.toRadixString(16)} '
                'to 0x${newMembers[common]!.toRadixString(16)}',
          ),
        );
      }
    }
  }

  // -- Utility methods ----------------------------------------------------

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
}

// =====================================================================
// Private helpers — hold shared context to avoid threading the same
// arguments through every call.
// =====================================================================

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

  int mapIndex(int oldIdx, _PoolKind pool) {
    final map = switch (pool) {
      _PoolKind.string => string,
      _PoolKind.type => type,
      _PoolKind.field => field,
      _PoolKind.method => method,
      _PoolKind.proto => proto,
      // Call-site and method-handle tables aren't reordered.
      _PoolKind.callSite || _PoolKind.methodHandle => null,
    };
    if (map == null) return oldIdx;
    return map[oldIdx] ?? oldIdx;
  }
}

/// Holds old/new file context so comparison methods don't need to
/// repeat the same six parameters.
class _DiffContext {
  _DiffContext({
    required this.oldFile,
    required this.newFile,
    required this.mappings,
  });

  final DexFile oldFile;
  final DexFile newFile;
  final _IndexMappings mappings;

  Uint8List get oldBytes => oldFile.bytes;
  Uint8List get newBytes => newFile.bytes;

  // -- Per-class entry point ----------------------------------------------

  void compareClassData(
    String className,
    DexClassDef oldClass,
    DexClassDef newClass,
    List<DexDifference> differences,
  ) {
    _compareCodeItems(className, oldClass, newClass, differences);

    _compareCanonicalSection(
      className: className,
      oldOff: oldClass.annotationsOff,
      newOff: newClass.annotationsOff,
      kind: DexDifferenceKind.annotationsChanged,
      label: 'annotations',
      canonicalize: _canonicalizeAnnotationDirectory,
      differences: differences,
    );

    _compareCanonicalSection(
      className: className,
      oldOff: oldClass.staticValuesOff,
      newOff: newClass.staticValuesOff,
      kind: DexDifferenceKind.staticValuesChanged,
      label: 'static field initial values',
      canonicalize: _canonicalizeEncodedArray,
      differences: differences,
    );
  }

  /// Compares a section that both classes may or may not have, using a
  /// canonicalization function to produce comparable strings.
  void _compareCanonicalSection({
    required String className,
    required int oldOff,
    required int newOff,
    required DexDifferenceKind kind,
    required String label,
    required String Function(_DexReader) canonicalize,
    required List<DexDifference> differences,
  }) {
    if (oldOff == 0 && newOff == 0) return;

    if (oldOff == 0 || newOff == 0) {
      differences.add(
        DexDifference(
          kind: kind,
          description: '$className: $label added or removed',
        ),
      );
      return;
    }

    final oldCanon = canonicalize(_DexReader(oldBytes, oldOff, oldFile));
    final newCanon = canonicalize(_DexReader(newBytes, newOff, newFile));

    if (oldCanon != newCanon) {
      differences.add(
        DexDifference(
          kind: kind,
          description: '$className: $label changed',
        ),
      );
    }
  }

  // -- Code item comparison -----------------------------------------------

  void _compareCodeItems(
    String className,
    DexClassDef oldClass,
    DexClassDef newClass,
    List<DexDifference> differences,
  ) {
    final oldMethods = _methodMap(oldClass.classData);
    final newMethods = _methodMap(newClass.classData);

    for (final entry in oldMethods.entries) {
      final newMethod = newMethods[entry.key];
      if (newMethod == null) continue; // caught structurally

      if (!_codeItemsEqual(
        entry.value.codeOffset,
        newMethod.codeOffset,
      )) {
        differences.add(
          DexDifference(
            kind: DexDifferenceKind.bytecodeChanged,
            description:
                '$className: bytecode changed in ${entry.key}',
          ),
        );
      }
    }
  }

  static Map<String, DexEncodedMethod> _methodMap(
    DexClassData? data,
  ) {
    if (data == null) return const {};
    return {
      for (final m in [
        ...data.directMethods,
        ...data.virtualMethods,
      ])
        DexDiffer._methodKey(m): m,
    };
  }

  bool _codeItemsEqual(int oldOff, int newOff) {
    if (oldOff == 0 && newOff == 0) return true;
    if (oldOff == 0 || newOff == 0) return false;

    final oRegs = DexParser.readUint16(oldBytes, oldOff);
    final nRegs = DexParser.readUint16(newBytes, newOff);
    final oIns = DexParser.readUint16(oldBytes, oldOff + 2);
    final nIns = DexParser.readUint16(newBytes, newOff + 2);
    final oOuts = DexParser.readUint16(oldBytes, oldOff + 4);
    final nOuts = DexParser.readUint16(newBytes, newOff + 4);
    final oTries = DexParser.readUint16(oldBytes, oldOff + 6);
    final nTries = DexParser.readUint16(newBytes, newOff + 6);
    // debug_info_off at +8 — skip (safe to differ).
    final oInsnsSize = DexParser.readUint32(oldBytes, oldOff + 12);
    final nInsnsSize = DexParser.readUint32(newBytes, newOff + 12);

    if (oRegs != nRegs ||
        oIns != nIns ||
        oOuts != nOuts ||
        oTries != nTries ||
        oInsnsSize != nInsnsSize) {
      return false;
    }

    final oInsnsOff = oldOff + 16;
    final nInsnsOff = newOff + 16;
    if (!_instructionsEqual(oInsnsOff, nInsnsOff, oInsnsSize)) {
      return false;
    }

    if (oTries > 0) {
      final pad = (oInsnsSize % 2 != 0) ? 2 : 0;
      final oTriesOff = oInsnsOff + oInsnsSize * 2 + pad;
      final nTriesOff = nInsnsOff + nInsnsSize * 2 + pad;
      if (!_tryCatchEqual(oTriesOff, nTriesOff, oTries)) {
        return false;
      }
    }

    return true;
  }

  bool _instructionsEqual(
    int oldOff,
    int newOff,
    int insnsSize,
  ) {
    var pos = 0;
    while (pos < insnsSize) {
      final oldUnit =
          DexParser.readUint16(oldBytes, oldOff + pos * 2);
      final opcode = oldUnit & 0xFF;

      // Handle pseudo-instructions (payloads).
      if (opcode == 0x00) {
        final payloadSize =
            _payloadSize(oldBytes, oldOff + pos * 2);
        if (payloadSize > 0) {
          // Payloads contain no pool indices; compare directly.
          for (var i = 0; i < payloadSize; i++) {
            if (_readUnit(oldBytes, oldOff, pos + i) !=
                _readUnit(newBytes, newOff, pos + i)) {
              return false;
            }
          }
          pos += payloadSize;
          continue;
        }
      }

      final size = _opcodeSizes[opcode];
      final indexInfo = _opcodeIndexInfo[opcode];

      for (var i = 0; i < size; i++) {
        final o = _readUnit(oldBytes, oldOff, pos + i);
        final n = _readUnit(newBytes, newOff, pos + i);

        final ref = indexInfo?.refAt(i);
        if (ref == null) {
          if (o != n) return false;
        } else if (ref.is32Bit) {
          final oHi = _readUnit(oldBytes, oldOff, pos + i + 1);
          final nHi = _readUnit(newBytes, newOff, pos + i + 1);
          final mapped = mappings.mapIndex(
            o | (oHi << 16),
            ref.pool,
          );
          if (mapped != (n | (nHi << 16))) return false;
          i++; // consumed the next unit
        } else {
          if (mappings.mapIndex(o, ref.pool) != n) return false;
        }
      }
      pos += size;
    }
    return true;
  }

  static int _readUnit(Uint8List bytes, int base, int pos) =>
      DexParser.readUint16(bytes, base + pos * 2);

  bool _tryCatchEqual(int oldOff, int newOff, int triesSize) {
    // try_items: no pool indices, compare directly.
    for (var i = 0; i < triesSize * 8; i++) {
      if (oldBytes[oldOff + i] != newBytes[newOff + i]) {
        return false;
      }
    }

    // encoded_catch_handler_list follows try_items.
    var oPos = oldOff + triesSize * 8;
    var nPos = newOff + triesSize * 8;

    final (listSize, hb1) = DexParser.readUleb128(oldBytes, oPos);
    final (nListSize, hb2) = DexParser.readUleb128(newBytes, nPos);
    if (listSize != nListSize) return false;
    oPos += hb1;
    nPos += hb2;

    for (var i = 0; i < listSize; i++) {
      final (oSize, sb1) = DexParser.readSleb128(oldBytes, oPos);
      final (nSize, sb2) = DexParser.readSleb128(newBytes, nPos);
      if (oSize != nSize) return false;
      oPos += sb1;
      nPos += sb2;

      for (var j = 0; j < oSize.abs(); j++) {
        // type_idx — needs remapping.
        final (oType, tb1) = DexParser.readUleb128(oldBytes, oPos);
        final (nType, tb2) = DexParser.readUleb128(newBytes, nPos);
        oPos += tb1;
        nPos += tb2;
        if (mappings.mapIndex(oType, _PoolKind.type) != nType) {
          return false;
        }

        // addr — no remapping.
        final (oAddr, ab1) = DexParser.readUleb128(oldBytes, oPos);
        final (nAddr, ab2) = DexParser.readUleb128(newBytes, nPos);
        oPos += ab1;
        nPos += ab2;
        if (oAddr != nAddr) return false;
      }

      if (oSize <= 0) {
        final (oAddr, ab1) = DexParser.readUleb128(oldBytes, oPos);
        final (nAddr, ab2) = DexParser.readUleb128(newBytes, nPos);
        oPos += ab1;
        nPos += ab2;
        if (oAddr != nAddr) return false;
      }
    }
    return true;
  }

  // -- Annotation canonicalization ----------------------------------------

  String _canonicalizeAnnotationDirectory(_DexReader r) {
    final buf = StringBuffer();
    final classAnnotationsOff = r.readUint32();
    final fieldsSize = r.readUint32();
    final methodsSize = r.readUint32();
    final paramsSize = r.readUint32();

    if (classAnnotationsOff != 0) {
      buf.writeln(
        'CLASS:'
        '${_canonicalizeAnnotationSet(r.at(classAnnotationsOff))}',
      );
    }

    for (var i = 0; i < fieldsSize; i++) {
      final fieldIdx = r.readUint32();
      final annotOff = r.readUint32();
      final f = r.file.fieldIds[fieldIdx];
      buf.writeln(
        'FIELD:${f.className}.${f.fieldName}:'
        '${_canonicalizeAnnotationSet(r.at(annotOff))}',
      );
    }

    for (var i = 0; i < methodsSize; i++) {
      final methodIdx = r.readUint32();
      final annotOff = r.readUint32();
      final m = r.file.methodIds[methodIdx];
      final params = m.proto.parameterTypes.join(',');
      buf.writeln(
        'METHOD:${m.className}.${m.methodName}($params):'
        '${_canonicalizeAnnotationSet(r.at(annotOff))}',
      );
    }

    for (var i = 0; i < paramsSize; i++) {
      final methodIdx = r.readUint32();
      final annotOff = r.readUint32();
      final m = r.file.methodIds[methodIdx];
      final params = m.proto.parameterTypes.join(',');
      buf.writeln(
        'PARAM:${m.className}.${m.methodName}($params):'
        '${_canonicalizeAnnotationSetRefList(r.at(annotOff))}',
      );
    }

    return buf.toString();
  }

  String _canonicalizeAnnotationSet(_DexReader r) {
    final size = r.readUint32();
    final items = <String>[];
    for (var i = 0; i < size; i++) {
      final annotOff = r.readUint32();
      items.add(_canonicalizeAnnotationItem(r.at(annotOff)));
    }
    // Sort for order-independence (sorted by type_idx in the file,
    // but type_idx values may differ between builds).
    items.sort();
    return '{${items.join(';')}}';
  }

  String _canonicalizeAnnotationSetRefList(_DexReader r) {
    final size = r.readUint32();
    final items = <String>[];
    for (var i = 0; i < size; i++) {
      final setOff = r.readUint32();
      items.add(
        setOff == 0
            ? 'null'
            : _canonicalizeAnnotationSet(r.at(setOff)),
      );
    }
    return '[${items.join(',')}]';
  }

  String _canonicalizeAnnotationItem(_DexReader r) {
    final visibility = r.readByte();
    return 'v$visibility:${_canonicalizeEncodedAnnotation(r)}';
  }

  String _canonicalizeEncodedAnnotation(_DexReader r) {
    final typeIdx = r.readUleb128();
    final size = r.readUleb128();
    final typeName = r.file.typeDescriptors[typeIdx];
    final elements = <String>[];
    for (var i = 0; i < size; i++) {
      final nameIdx = r.readUleb128();
      final name = r.file.strings[nameIdx];
      elements.add('$name=${_canonicalizeEncodedValue(r)}');
    }
    elements.sort();
    return '$typeName(${elements.join(',')})';
  }

  String _canonicalizeEncodedValue(_DexReader r) {
    final header = r.readByte();
    final valueType = header & 0x1F;
    final valueArg = (header >> 5) & 0x07;
    final byteCount = valueArg + 1;

    switch (valueType) {
      case 0x00: // byte
        return 'B:${r.readByte()}';
      case 0x02: // short
      case 0x03: // char
      case 0x04: // int
      case 0x06: // long
      case 0x10: // float
      case 0x11: // double
        return 'N$valueType:${r.readSignExtended(byteCount)}';
      case 0x15: // method_type (proto@)
        final p = r.file.protoIds[r.readUnsigned(byteCount)];
        return 'MT:${p.returnType}'
            '(${p.parameterTypes.join(',')})';
      case 0x16: // method_handle
        return 'MH:${r.readUnsigned(byteCount)}';
      case 0x17: // string
        return 'S:${r.file.strings[r.readUnsigned(byteCount)]}';
      case 0x18: // type
        final desc =
            r.file.typeDescriptors[r.readUnsigned(byteCount)];
        return 'T:$desc';
      case 0x19: // field
        final f = r.file.fieldIds[r.readUnsigned(byteCount)];
        return 'F:${f.className}.${f.fieldName}:${f.typeName}';
      case 0x1a: // method
        final m = r.file.methodIds[r.readUnsigned(byteCount)];
        final params = m.proto.parameterTypes.join(',');
        return 'M:${m.className}.${m.methodName}'
            '($params)${m.proto.returnType}';
      case 0x1b: // enum (field@)
        final f = r.file.fieldIds[r.readUnsigned(byteCount)];
        return 'E:${f.className}.${f.fieldName}:${f.typeName}';
      case 0x1c: // array
        final size = r.readUleb128();
        final items = [
          for (var i = 0; i < size; i++)
            _canonicalizeEncodedValue(r),
        ];
        return 'A:[${items.join(',')}]';
      case 0x1d: // annotation
        return '@:${_canonicalizeEncodedAnnotation(r)}';
      case 0x1e: // null
        return 'NULL';
      case 0x1f: // boolean
        return 'BOOL:$valueArg';
      default:
        return '?$valueType:${r.readRawBytes(byteCount)}';
    }
  }

  // -- Static values canonicalization -------------------------------------

  String _canonicalizeEncodedArray(_DexReader r) {
    final size = r.readUleb128();
    final items = [
      for (var i = 0; i < size; i++) _canonicalizeEncodedValue(r),
    ];
    return items.join(',');
  }

  // -- Payload size -------------------------------------------------------

  static int _payloadSize(Uint8List bytes, int off) {
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

// =====================================================================
// _DexReader — cursor-based reader that holds bytes + file context,
// eliminating the need to pass (Uint8List, int, DexFile) everywhere.
// =====================================================================

class _DexReader {
  _DexReader(this.bytes, this._pos, this.file);

  final Uint8List bytes;
  final DexFile file;
  int _pos;

  /// Creates a new reader at a different offset in the same file.
  _DexReader at(int offset) => _DexReader(bytes, offset, file);

  int readByte() => bytes[_pos++];

  int readUint32() {
    final v = DexParser.readUint32(bytes, _pos);
    _pos += 4;
    return v;
  }

  int readUleb128() {
    final (value, consumed) = DexParser.readUleb128(bytes, _pos);
    _pos += consumed;
    return value;
  }

  int readUnsigned(int byteCount) {
    var value = 0;
    for (var i = 0; i < byteCount; i++) {
      value |= bytes[_pos++] << (i * 8);
    }
    return value;
  }

  int readSignExtended(int byteCount) {
    var value = 0;
    for (var i = 0; i < byteCount; i++) {
      value |= bytes[_pos++] << (i * 8);
    }
    final shift = byteCount * 8;
    if (shift < 64 && (value & (1 << (shift - 1))) != 0) {
      value |= -(1 << shift);
    }
    return value;
  }

  List<int> readRawBytes(int count) {
    final result = bytes.sublist(_pos, _pos + count);
    _pos += count;
    return result;
  }
}

// =====================================================================
// Opcode tables
// =====================================================================

/// Pool kinds for index references in instructions.
enum _PoolKind {
  string,
  type,
  field,
  method,
  proto,
  callSite,
  methodHandle,
}

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

  /// Returns the [_IndexRef] at [unitOffset], or null.
  _IndexRef? refAt(int unitOffset) {
    for (final r in refs) {
      if (r.unitOffset == unitOffset) return r;
    }
    return null;
  }
}

/// Helper to create the same index info for a range of opcodes.
Map<int, _OpcodeIndexInfo> _range(
  int start,
  int end,
  _PoolKind pool,
) => {
  for (var op = start; op <= end; op++)
    op: _OpcodeIndexInfo([_IndexRef(1, pool)]),
};

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

/// Opcodes that carry pool-index references.
final _opcodeIndexInfo = <int, _OpcodeIndexInfo>{
  // const-string (string@)
  0x1a: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.string)]),
  // const-string/jumbo (string@, 32-bit)
  0x1b: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.string, is32Bit: true),
  ]),
  // const-class, check-cast (type@)
  0x1c: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  0x1f: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // instance-of, new-instance, new-array (type@)
  0x20: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  0x22: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  0x23: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // filled-new-array, filled-new-array/range (type@)
  0x24: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  0x25: const _OpcodeIndexInfo([_IndexRef(1, _PoolKind.type)]),
  // iget/iput 0x52-0x5f, sget/sput 0x60-0x6d (field@)
  ..._range(0x52, 0x5f, _PoolKind.field),
  ..._range(0x60, 0x6d, _PoolKind.field),
  // invoke-virtual .. invoke-interface 0x6e-0x72 (method@)
  ..._range(0x6e, 0x72, _PoolKind.method),
  // invoke-virtual/range .. invoke-interface/range 0x74-0x78
  ..._range(0x74, 0x78, _PoolKind.method),
  // invoke-polymorphic (method@ + proto@)
  0xfa: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.method),
    _IndexRef(3, _PoolKind.proto),
  ]),
  // invoke-polymorphic/range (method@ + proto@)
  0xfb: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.method),
    _IndexRef(3, _PoolKind.proto),
  ]),
  // invoke-custom (call_site@)
  0xfc: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.callSite),
  ]),
  // invoke-custom/range (call_site@)
  0xfd: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.callSite),
  ]),
  // const-method-handle (method_handle@)
  0xfe: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.methodHandle),
  ]),
  // const-method-type (proto@)
  0xff: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.proto),
  ]),
};
