// cspell:words uleb sleb mutf Dalvik Ljava insns annot iget iput sget sput
import 'dart:typed_data';

/// {@template dex_file}
/// A parsed DEX (Dalvik Executable) file.
/// {@endtemplate}
class DexFile {
  /// {@macro dex_file}
  const DexFile({
    required this.header,
    required this.strings,
    required this.typeDescriptors,
    required this.protoIds,
    required this.fieldIds,
    required this.methodIds,
    required this.classDefs,
  });

  /// The DEX file header.
  final DexHeader header;

  /// The resolved string table.
  final List<String> strings;

  /// Resolved type descriptors (e.g. `Ljava/lang/Object;`, `I`, `V`).
  final List<String> typeDescriptors;

  /// Resolved prototype identifiers.
  final List<DexProtoId> protoIds;

  /// Resolved field identifiers.
  final List<DexFieldId> fieldIds;

  /// Resolved method identifiers.
  final List<DexMethodId> methodIds;

  /// Resolved class definitions.
  final List<DexClassDef> classDefs;
}

/// {@template dex_header}
/// The header section of a DEX file.
/// {@endtemplate}
class DexHeader {
  /// {@macro dex_header}
  const DexHeader({
    required this.stringIdsSize,
    required this.stringIdsOff,
    required this.typeIdsSize,
    required this.typeIdsOff,
    required this.protoIdsSize,
    required this.protoIdsOff,
    required this.fieldIdsSize,
    required this.fieldIdsOff,
    required this.methodIdsSize,
    required this.methodIdsOff,
    required this.classDefsSize,
    required this.classDefsOff,
  });

  /// Number of string identifiers.
  final int stringIdsSize;

  /// Offset of string identifiers section.
  final int stringIdsOff;

  /// Number of type identifiers.
  final int typeIdsSize;

  /// Offset of type identifiers section.
  final int typeIdsOff;

  /// Number of prototype identifiers.
  final int protoIdsSize;

  /// Offset of prototype identifiers section.
  final int protoIdsOff;

  /// Number of field identifiers.
  final int fieldIdsSize;

  /// Offset of field identifiers section.
  final int fieldIdsOff;

  /// Number of method identifiers.
  final int methodIdsSize;

  /// Offset of method identifiers section.
  final int methodIdsOff;

  /// Number of class definitions.
  final int classDefsSize;

  /// Offset of class definitions section.
  final int classDefsOff;
}

/// {@template dex_proto_id}
/// A resolved prototype identifier (method signature).
/// {@endtemplate}
class DexProtoId {
  /// {@macro dex_proto_id}
  const DexProtoId({
    required this.shorty,
    required this.returnType,
    required this.parameterTypes,
  });

  /// Shorty descriptor string.
  final String shorty;

  /// Return type descriptor.
  final String returnType;

  /// Parameter type descriptors, empty if no parameters.
  final List<String> parameterTypes;
}

/// {@template dex_field_id}
/// A resolved field identifier.
/// {@endtemplate}
class DexFieldId {
  /// {@macro dex_field_id}
  const DexFieldId({
    required this.className,
    required this.typeName,
    required this.fieldName,
  });

  /// The type descriptor of the defining class.
  final String className;

  /// The type descriptor of the field's type.
  final String typeName;

  /// The field name.
  final String fieldName;
}

/// {@template dex_method_id}
/// A resolved method identifier.
/// {@endtemplate}
class DexMethodId {
  /// {@macro dex_method_id}
  const DexMethodId({
    required this.className,
    required this.methodName,
    required this.proto,
  });

  /// The type descriptor of the defining class.
  final String className;

  /// The method name.
  final String methodName;

  /// The resolved prototype (signature).
  final DexProtoId proto;
}

/// {@template dex_class_def}
/// A resolved class definition.
/// {@endtemplate}
class DexClassDef {
  /// {@macro dex_class_def}
  const DexClassDef({
    required this.className,
    required this.accessFlags,
    required this.superclass,
    required this.interfaces,
    required this.sourceFile,
    required this.canonicalAnnotations,
    required this.canonicalStaticValues,
    required this.classData,
  });

  /// The type descriptor of this class.
  final String className;

  /// Access flags (public, final, etc.).
  final int accessFlags;

  /// The type descriptor of the superclass, or `null` for `Object`.
  final String? superclass;

  /// Type descriptors of implemented interfaces.
  final List<String> interfaces;

  /// Source file name, or `null` if not present.
  final String? sourceFile;

  /// Canonical string representation of annotations, or `null` if none.
  final String? canonicalAnnotations;

  /// Canonical string representation of static field initial values,
  /// or `null` if none.
  final String? canonicalStaticValues;

  /// Class data (fields and methods), or `null` if no data.
  final DexClassData? classData;
}

/// {@template dex_class_data}
/// The fields and methods of a class.
/// {@endtemplate}
class DexClassData {
  /// {@macro dex_class_data}
  const DexClassData({
    required this.staticFields,
    required this.instanceFields,
    required this.directMethods,
    required this.virtualMethods,
  });

  /// Static field definitions.
  final List<DexEncodedField> staticFields;

  /// Instance field definitions.
  final List<DexEncodedField> instanceFields;

  /// Direct method definitions (static, private, constructors).
  final List<DexEncodedMethod> directMethods;

  /// Virtual method definitions.
  final List<DexEncodedMethod> virtualMethods;
}

/// {@template dex_encoded_field}
/// A field definition within a class.
/// {@endtemplate}
class DexEncodedField {
  /// {@macro dex_encoded_field}
  const DexEncodedField({
    required this.field,
    required this.accessFlags,
  });

  /// The resolved field identifier.
  final DexFieldId field;

  /// Access flags.
  final int accessFlags;
}

/// {@template dex_encoded_method}
/// A method definition within a class.
/// {@endtemplate}
class DexEncodedMethod {
  /// {@macro dex_encoded_method}
  const DexEncodedMethod({
    required this.method,
    required this.accessFlags,
    required this.code,
  });

  /// The resolved method identifier.
  final DexMethodId method;

  /// Access flags.
  final int accessFlags;

  /// The parsed code item, or `null` if abstract/native.
  final DexCodeItem? code;
}

/// {@template dex_code_item}
/// A parsed code_item from a DEX file, with all pool indices resolved.
/// {@endtemplate}
class DexCodeItem {
  /// {@macro dex_code_item}
  const DexCodeItem({
    required this.registersSize,
    required this.insSize,
    required this.outsSize,
    required this.canonicalBytecode,
  });

  /// Number of registers used by this code.
  final int registersSize;

  /// Number of words of incoming arguments.
  final int insSize;

  /// Number of words of outgoing argument space.
  final int outsSize;

  /// Canonical string of instructions and try/catch with all pool
  /// indices resolved to string values.
  final String canonicalBytecode;
}

/// Sentinel value for "no index" in DEX files.
const _noIndex = 0xFFFFFFFF; // NO_INDEX

/// DEX file magic bytes.
final _dexMagicPrefix = [
  0x64, 0x65, 0x78, 0x0a, // "dex\n"
];

/// {@template dex_parser}
/// Parses DEX binary files into structured [DexFile] objects.
///
/// See https://source.android.com/docs/core/runtime/dex-format for the
/// DEX format specification.
/// {@endtemplate}
class DexParser {
  /// {@macro dex_parser}
  const DexParser();

  /// Parses a DEX file from raw bytes.
  ///
  /// Throws [FormatException] if the data is not a valid DEX file.
  DexFile parse(Uint8List bytes) {
    _validateMagic(bytes);

    final header = _parseHeader(bytes);
    final strings = _parseStrings(bytes, header);
    final typeDescriptors =
        _parseTypeDescriptors(bytes, header, strings);
    final protoIds =
        _parseProtoIds(bytes, header, strings, typeDescriptors);
    final fieldIds =
        _parseFieldIds(bytes, header, strings, typeDescriptors);
    final methodIds = _parseMethodIds(
      bytes,
      header,
      strings,
      typeDescriptors,
      protoIds,
    );
    final classDefs = _parseClassDefs(
      bytes,
      header,
      strings,
      typeDescriptors,
      protoIds,
      fieldIds,
      methodIds,
    );

    return DexFile(
      header: header,
      strings: strings,
      typeDescriptors: typeDescriptors,
      protoIds: protoIds,
      fieldIds: fieldIds,
      methodIds: methodIds,
      classDefs: classDefs,
    );
  }

  void _validateMagic(Uint8List bytes) {
    if (bytes.length < 112) {
      throw FormatException(
        'File too small to be a DEX file (${bytes.length} bytes)',
      );
    }

    for (var i = 0; i < _dexMagicPrefix.length; i++) {
      if (bytes[i] != _dexMagicPrefix[i]) {
        throw const FormatException('Invalid DEX magic bytes');
      }
    }
  }

  DexHeader _parseHeader(Uint8List bytes) {
    final r = _BinaryReader(bytes, 56);
    return DexHeader(
      stringIdsSize: r.readUint32(),
      stringIdsOff: r.readUint32(),
      typeIdsSize: r.readUint32(),
      typeIdsOff: r.readUint32(),
      protoIdsSize: r.readUint32(),
      protoIdsOff: r.readUint32(),
      fieldIdsSize: r.readUint32(),
      fieldIdsOff: r.readUint32(),
      methodIdsSize: r.readUint32(),
      methodIdsOff: r.readUint32(),
      classDefsSize: r.readUint32(),
      classDefsOff: r.readUint32(),
    );
  }

  List<String> _parseStrings(Uint8List bytes, DexHeader header) {
    final r = _BinaryReader(bytes, header.stringIdsOff);
    final strings = <String>[];
    for (var i = 0; i < header.stringIdsSize; i++) {
      final stringDataOff = r.readUint32();
      strings.add(_readMutf8String(r.at(stringDataOff)));
    }
    return strings;
  }

  List<String> _parseTypeDescriptors(
    Uint8List bytes,
    DexHeader header,
    List<String> strings,
  ) {
    final r = _BinaryReader(bytes, header.typeIdsOff);
    final types = <String>[];
    for (var i = 0; i < header.typeIdsSize; i++) {
      types.add(strings[r.readUint32()]);
    }
    return types;
  }

  List<DexProtoId> _parseProtoIds(
    Uint8List bytes,
    DexHeader header,
    List<String> strings,
    List<String> typeDescriptors,
  ) {
    final r = _BinaryReader(bytes, header.protoIdsOff);
    final protos = <DexProtoId>[];
    for (var i = 0; i < header.protoIdsSize; i++) {
      final shortyIdx = r.readUint32();
      final returnTypeIdx = r.readUint32();
      final parametersOff = r.readUint32();

      final parameterTypes = <String>[];
      if (parametersOff != 0) {
        final pr = r.at(parametersOff);
        final paramCount = pr.readUint32();
        for (var j = 0; j < paramCount; j++) {
          parameterTypes.add(typeDescriptors[pr.readUint16()]);
        }
      }

      protos.add(
        DexProtoId(
          shorty: strings[shortyIdx],
          returnType: typeDescriptors[returnTypeIdx],
          parameterTypes: parameterTypes,
        ),
      );
    }
    return protos;
  }

  List<DexFieldId> _parseFieldIds(
    Uint8List bytes,
    DexHeader header,
    List<String> strings,
    List<String> typeDescriptors,
  ) {
    final r = _BinaryReader(bytes, header.fieldIdsOff);
    final fields = <DexFieldId>[];
    for (var i = 0; i < header.fieldIdsSize; i++) {
      final classIdx = r.readUint16();
      final typeIdx = r.readUint16();
      final nameIdx = r.readUint32();

      fields.add(
        DexFieldId(
          className: typeDescriptors[classIdx],
          typeName: typeDescriptors[typeIdx],
          fieldName: strings[nameIdx],
        ),
      );
    }
    return fields;
  }

  List<DexMethodId> _parseMethodIds(
    Uint8List bytes,
    DexHeader header,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
  ) {
    final r = _BinaryReader(bytes, header.methodIdsOff);
    final methods = <DexMethodId>[];
    for (var i = 0; i < header.methodIdsSize; i++) {
      final classIdx = r.readUint16();
      final protoIdx = r.readUint16();
      final nameIdx = r.readUint32();

      methods.add(
        DexMethodId(
          className: typeDescriptors[classIdx],
          methodName: strings[nameIdx],
          proto: protoIds[protoIdx],
        ),
      );
    }
    return methods;
  }

  List<DexClassDef> _parseClassDefs(
    Uint8List bytes,
    DexHeader header,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final r = _BinaryReader(bytes, header.classDefsOff);
    final classDefs = <DexClassDef>[];
    for (var i = 0; i < header.classDefsSize; i++) {
      final classIdx = r.readUint32();
      final accessFlags = r.readUint32();
      final superclassIdx = r.readUint32();
      final interfacesOff = r.readUint32();
      final sourceFileIdx = r.readUint32();
      final annotationsOff = r.readUint32();
      final classDataOff = r.readUint32();
      final staticValuesOff = r.readUint32();

      final interfaces = <String>[];
      if (interfacesOff != 0) {
        final ir = r.at(interfacesOff);
        final count = ir.readUint32();
        for (var j = 0; j < count; j++) {
          interfaces.add(typeDescriptors[ir.readUint16()]);
        }
      }

      DexClassData? classData;
      if (classDataOff != 0) {
        classData = _parseClassData(
          _BinaryReader(bytes, classDataOff),
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        );
      }

      final canonAnnotations = annotationsOff != 0
          ? _canonicalizeAnnotationDirectory(
              _BinaryReader(bytes, annotationsOff),
              strings,
              typeDescriptors,
              protoIds,
              fieldIds,
              methodIds,
            )
          : null;

      final canonStaticValues = staticValuesOff != 0
          ? _canonicalizeEncodedArray(
              _BinaryReader(bytes, staticValuesOff),
              strings,
              typeDescriptors,
              protoIds,
              fieldIds,
              methodIds,
            )
          : null;

      classDefs.add(
        DexClassDef(
          className: typeDescriptors[classIdx],
          accessFlags: accessFlags,
          superclass: superclassIdx == _noIndex
              ? null
              : typeDescriptors[superclassIdx],
          interfaces: interfaces,
          sourceFile: sourceFileIdx == _noIndex
              ? null
              : strings[sourceFileIdx],
          canonicalAnnotations: canonAnnotations,
          canonicalStaticValues: canonStaticValues,
          classData: classData,
        ),
      );
    }
    return classDefs;
  }

  DexClassData _parseClassData(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final staticFieldsSize = r.readUleb128();
    final instanceFieldsSize = r.readUleb128();
    final directMethodsSize = r.readUleb128();
    final virtualMethodsSize = r.readUleb128();

    final staticFields = <DexEncodedField>[];
    var fieldIdx = 0;
    for (var i = 0; i < staticFieldsSize; i++) {
      fieldIdx += r.readUleb128();
      final accessFlags = r.readUleb128();
      staticFields.add(
        DexEncodedField(
          field: fieldIds[fieldIdx],
          accessFlags: accessFlags,
        ),
      );
    }

    final instanceFields = <DexEncodedField>[];
    fieldIdx = 0;
    for (var i = 0; i < instanceFieldsSize; i++) {
      fieldIdx += r.readUleb128();
      final accessFlags = r.readUleb128();
      instanceFields.add(
        DexEncodedField(
          field: fieldIds[fieldIdx],
          accessFlags: accessFlags,
        ),
      );
    }

    final directMethods = <DexEncodedMethod>[];
    var methodIdx = 0;
    for (var i = 0; i < directMethodsSize; i++) {
      methodIdx += r.readUleb128();
      final accessFlags = r.readUleb128();
      final codeOff = r.readUleb128();
      directMethods.add(
        DexEncodedMethod(
          method: methodIds[methodIdx],
          accessFlags: accessFlags,
          code: codeOff != 0
              ? _parseCodeItem(
                  r.at(codeOff),
                  strings,
                  typeDescriptors,
                  protoIds,
                  fieldIds,
                  methodIds,
                )
              : null,
        ),
      );
    }

    final virtualMethods = <DexEncodedMethod>[];
    methodIdx = 0;
    for (var i = 0; i < virtualMethodsSize; i++) {
      methodIdx += r.readUleb128();
      final accessFlags = r.readUleb128();
      final codeOff = r.readUleb128();
      virtualMethods.add(
        DexEncodedMethod(
          method: methodIds[methodIdx],
          accessFlags: accessFlags,
          code: codeOff != 0
              ? _parseCodeItem(
                  r.at(codeOff),
                  strings,
                  typeDescriptors,
                  protoIds,
                  fieldIds,
                  methodIds,
                )
              : null,
        ),
      );
    }

    return DexClassData(
      staticFields: staticFields,
      instanceFields: instanceFields,
      directMethods: directMethods,
      virtualMethods: virtualMethods,
    );
  }

  // -- Code item parsing --------------------------------------------------

  DexCodeItem _parseCodeItem(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final registersSize = r.readUint16();
    final insSize = r.readUint16();
    final outsSize = r.readUint16();
    final triesSize = r.readUint16();
    r.skip(4); // debug_info_off — safe to differ.
    final insnsSize = r.readUint32();
    // r._pos is now at the start of insns.
    final insnsOff = r._pos;

    final buf = StringBuffer();

    _canonicalizeInstructions(
      buf,
      r.bytes,
      insnsOff,
      insnsSize,
      strings,
      typeDescriptors,
      protoIds,
      fieldIds,
      methodIds,
    );

    if (triesSize > 0) {
      final pad = (insnsSize % 2 != 0) ? 2 : 0;
      final triesOff = insnsOff + insnsSize * 2 + pad;
      _canonicalizeTryCatch(
        buf,
        r.bytes,
        triesOff,
        triesSize,
        typeDescriptors,
      );
    }

    return DexCodeItem(
      registersSize: registersSize,
      insSize: insSize,
      outsSize: outsSize,
      canonicalBytecode: buf.toString(),
    );
  }

  void _canonicalizeInstructions(
    StringBuffer buf,
    Uint8List bytes,
    int insnsOff,
    int insnsSize,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    var pos = 0;
    while (pos < insnsSize) {
      final unit = _readUint16(bytes, insnsOff + pos * 2);
      final opcode = unit & 0xFF;

      // Handle pseudo-instructions (payloads).
      if (opcode == 0x00) {
        final payloadSize =
            _payloadSize(bytes, insnsOff + pos * 2);
        if (payloadSize > 0) {
          for (var i = 0; i < payloadSize; i++) {
            buf
              ..write(
                _readUint16(bytes, insnsOff + (pos + i) * 2),
              )
              ..write(',');
          }
          pos += payloadSize;
          continue;
        }
      }

      final size = _opcodeSizes[opcode];
      final indexInfo = _opcodeIndexInfo[opcode];

      for (var i = 0; i < size; i++) {
        final u = _readUint16(bytes, insnsOff + (pos + i) * 2);
        final ref = indexInfo?.refAt(i);
        if (ref == null) {
          buf
            ..write(u)
            ..write(',');
        } else if (ref.is32Bit) {
          final hi =
              _readUint16(bytes, insnsOff + (pos + i + 1) * 2);
          final idx = u | (hi << 16);
          buf
            ..write(_resolvePoolIndex(
              idx,
              ref.pool,
              strings,
              typeDescriptors,
              protoIds,
              fieldIds,
              methodIds,
            ))
            ..write(',');
          i++; // consumed the next unit
        } else {
          buf
            ..write(_resolvePoolIndex(
              u,
              ref.pool,
              strings,
              typeDescriptors,
              protoIds,
              fieldIds,
              methodIds,
            ))
            ..write(',');
        }
      }
      pos += size;
    }
  }

  String _resolvePoolIndex(
    int index,
    _PoolKind pool,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    switch (pool) {
      case _PoolKind.string:
        return 'S:${strings[index]}';
      case _PoolKind.type:
        return 'T:${typeDescriptors[index]}';
      case _PoolKind.field:
        final f = fieldIds[index];
        return 'F:${f.className}.${f.fieldName}:${f.typeName}';
      case _PoolKind.method:
        final m = methodIds[index];
        final params = m.proto.parameterTypes.join(',');
        return 'M:${m.className}.${m.methodName}'
            '($params)${m.proto.returnType}';
      case _PoolKind.proto:
        final p = protoIds[index];
        return 'P:${p.returnType}'
            '(${p.parameterTypes.join(',')})';
      case _PoolKind.callSite:
        return 'CS:$index';
      case _PoolKind.methodHandle:
        return 'MH:$index';
    }
  }

  void _canonicalizeTryCatch(
    StringBuffer buf,
    Uint8List bytes,
    int triesOff,
    int triesSize,
    List<String> typeDescriptors,
  ) {
    // try_items: no pool indices, emit directly.
    for (var i = 0; i < triesSize * 8; i++) {
      buf
        ..write(bytes[triesOff + i])
        ..write(',');
    }

    // encoded_catch_handler_list follows try_items.
    final r = _BinaryReader(bytes, triesOff + triesSize * 8);

    final listSize = r.readUleb128();
    buf.write('HL:$listSize,');

    for (var i = 0; i < listSize; i++) {
      final handlerSize = r.readSleb128();
      buf.write('HS:$handlerSize,');

      for (var j = 0; j < handlerSize.abs(); j++) {
        final typeIdx = r.readUleb128();
        final addr = r.readUleb128();
        buf
          // type_idx — resolve to type descriptor.
          ..write('T:${typeDescriptors[typeIdx]},')
          // addr — no resolution needed.
          ..write('A:$addr,');
      }

      if (handlerSize <= 0) {
        buf.write('CA:${r.readUleb128()},');
      }
    }
  }

  // -- Annotation canonicalization ----------------------------------------

  String _canonicalizeAnnotationDirectory(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final buf = StringBuffer();
    final classAnnotationsOff = r.readUint32();
    final fieldsSize = r.readUint32();
    final methodsSize = r.readUint32();
    final paramsSize = r.readUint32();

    if (classAnnotationsOff != 0) {
      buf.writeln(
        'CLASS:'
        '${_canonicalizeAnnotationSet(
          r.at(classAnnotationsOff),
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        )}',
      );
    }

    for (var i = 0; i < fieldsSize; i++) {
      final fieldIdx = r.readUint32();
      final annotOff = r.readUint32();
      final f = fieldIds[fieldIdx];
      buf.writeln(
        'FIELD:${f.className}.${f.fieldName}:'
        '${_canonicalizeAnnotationSet(
          r.at(annotOff),
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        )}',
      );
    }

    for (var i = 0; i < methodsSize; i++) {
      final methodIdx = r.readUint32();
      final annotOff = r.readUint32();
      final m = methodIds[methodIdx];
      final params = m.proto.parameterTypes.join(',');
      buf.writeln(
        'METHOD:${m.className}.${m.methodName}($params):'
        '${_canonicalizeAnnotationSet(
          r.at(annotOff),
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        )}',
      );
    }

    for (var i = 0; i < paramsSize; i++) {
      final methodIdx = r.readUint32();
      final annotOff = r.readUint32();
      final m = methodIds[methodIdx];
      final params = m.proto.parameterTypes.join(',');
      buf.writeln(
        'PARAM:${m.className}.${m.methodName}($params):'
        '${_canonicalizeAnnotationSetRefList(
          r.at(annotOff),
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        )}',
      );
    }

    return buf.toString();
  }

  String _canonicalizeAnnotationSet(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final size = r.readUint32();
    final items = <String>[];
    for (var i = 0; i < size; i++) {
      final annotOff = r.readUint32();
      items.add(_canonicalizeAnnotationItem(
        r.at(annotOff),
        strings,
        typeDescriptors,
        protoIds,
        fieldIds,
        methodIds,
      ));
    }
    // Sort for order-independence (sorted by type_idx in the file,
    // but type_idx values may differ between builds).
    items.sort();
    return '{${items.join(';')}}';
  }

  String _canonicalizeAnnotationSetRefList(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final size = r.readUint32();
    final items = <String>[];
    for (var i = 0; i < size; i++) {
      final setOff = r.readUint32();
      items.add(
        setOff == 0
            ? 'null'
            : _canonicalizeAnnotationSet(
                r.at(setOff),
                strings,
                typeDescriptors,
                protoIds,
                fieldIds,
                methodIds,
              ),
      );
    }
    return '[${items.join(',')}]';
  }

  String _canonicalizeAnnotationItem(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final visibility = r.readByte();
    return 'v$visibility:${_canonicalizeEncodedAnnotation(
      r,
      strings,
      typeDescriptors,
      protoIds,
      fieldIds,
      methodIds,
    )}';
  }

  String _canonicalizeEncodedAnnotation(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final typeIdx = r.readUleb128();
    final size = r.readUleb128();
    final typeName = typeDescriptors[typeIdx];
    final elements = <String>[];
    for (var i = 0; i < size; i++) {
      final nameIdx = r.readUleb128();
      final name = strings[nameIdx];
      elements.add(
        '$name=${_canonicalizeEncodedValue(
          r,
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        )}',
      );
    }
    elements.sort();
    return '$typeName(${elements.join(',')})';
  }

  String _canonicalizeEncodedValue(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
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
        final p = protoIds[r.readUnsigned(byteCount)];
        return 'MT:${p.returnType}'
            '(${p.parameterTypes.join(',')})';
      case 0x16: // method_handle
        return 'MH:${r.readUnsigned(byteCount)}';
      case 0x17: // string
        return 'S:${strings[r.readUnsigned(byteCount)]}';
      case 0x18: // type
        final desc =
            typeDescriptors[r.readUnsigned(byteCount)];
        return 'T:$desc';
      case 0x19: // field
        final f = fieldIds[r.readUnsigned(byteCount)];
        return 'F:${f.className}.${f.fieldName}'
            ':${f.typeName}';
      case 0x1a: // method
        final m = methodIds[r.readUnsigned(byteCount)];
        final params = m.proto.parameterTypes.join(',');
        return 'M:${m.className}.${m.methodName}'
            '($params)${m.proto.returnType}';
      case 0x1b: // enum (field@)
        final f = fieldIds[r.readUnsigned(byteCount)];
        return 'E:${f.className}.${f.fieldName}'
            ':${f.typeName}';
      case 0x1c: // array
        final size = r.readUleb128();
        final items = [
          for (var i = 0; i < size; i++)
            _canonicalizeEncodedValue(
              r,
              strings,
              typeDescriptors,
              protoIds,
              fieldIds,
              methodIds,
            ),
        ];
        return 'A:[${items.join(',')}]';
      case 0x1d: // annotation
        return '@:${_canonicalizeEncodedAnnotation(
          r,
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        )}';
      case 0x1e: // null
        return 'NULL';
      case 0x1f: // boolean
        return 'BOOL:$valueArg';
      default:
        return '?$valueType:${r.readRawBytes(byteCount)}';
    }
  }

  // -- Static values canonicalization -------------------------------------

  String _canonicalizeEncodedArray(
    _BinaryReader r,
    List<String> strings,
    List<String> typeDescriptors,
    List<DexProtoId> protoIds,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final size = r.readUleb128();
    final items = [
      for (var i = 0; i < size; i++)
        _canonicalizeEncodedValue(
          r,
          strings,
          typeDescriptors,
          protoIds,
          fieldIds,
          methodIds,
        ),
    ];
    return items.join(',');
  }

  // -- Payload size -------------------------------------------------------

  static int _payloadSize(Uint8List bytes, int off) {
    final ident = _readUint16(bytes, off);
    switch (ident) {
      case 0x0100: // packed-switch-payload
        final size = _readUint16(bytes, off + 2);
        return 4 + size * 2;
      case 0x0200: // sparse-switch-payload
        final size = _readUint16(bytes, off + 2);
        return 2 + size * 4;
      case 0x0300: // fill-array-data-payload
        final elementWidth = _readUint16(bytes, off + 2);
        final size = _readUint32(bytes, off + 4);
        final totalBytes = size * elementWidth;
        return 4 + ((totalBytes + 1) ~/ 2);
      default:
        return 0;
    }
  }

  /// Reads a MUTF-8 encoded string using the given reader.
  ///
  /// The format is: ULEB128 length (in UTF-16 code units), followed
  /// by MUTF-8 encoded bytes, followed by a null terminator.
  String _readMutf8String(_BinaryReader r) {
    // Skip the ULEB128 size prefix (size in UTF-16 code units,
    // not bytes).
    r.readUleb128();

    final codeUnits = <int>[];
    while (r._pos < r.bytes.length && r.bytes[r._pos] != 0) {
      final byte1 = r.readByte();
      if (byte1 & 0x80 == 0) {
        // Single-byte character (0xxxxxxx).
        codeUnits.add(byte1);
      } else if (byte1 & 0xE0 == 0xC0) {
        // Two-byte character (110xxxxx 10xxxxxx).
        final byte2 = r.readByte();
        codeUnits.add(
          ((byte1 & 0x1F) << 6) | (byte2 & 0x3F),
        );
      } else if (byte1 & 0xF0 == 0xE0) {
        // Three-byte character (1110xxxx 10xxxxxx 10xxxxxx).
        final byte2 = r.readByte();
        final byte3 = r.readByte();
        codeUnits.add(
          ((byte1 & 0x0F) << 12) |
              ((byte2 & 0x3F) << 6) |
              (byte3 & 0x3F),
        );
      }
    }

    return String.fromCharCodes(codeUnits);
  }

  static int _readUint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}

// =====================================================================
// _BinaryReader — cursor-based reader for sequential binary parsing.
// =====================================================================

class _BinaryReader {
  _BinaryReader(this.bytes, this._pos);

  final Uint8List bytes;
  int _pos;

  /// Creates a new reader at a different offset in the same bytes.
  _BinaryReader at(int offset) => _BinaryReader(bytes, offset);

  /// Advances position by [count] bytes without reading.
  void skip(int count) => _pos += count;

  int readByte() => bytes[_pos++];

  int readUint16() {
    final v = bytes[_pos] | (bytes[_pos + 1] << 8);
    _pos += 2;
    return v;
  }

  int readUint32() {
    final v = bytes[_pos] |
        (bytes[_pos + 1] << 8) |
        (bytes[_pos + 2] << 16) |
        (bytes[_pos + 3] << 24);
    _pos += 4;
    return v;
  }

  int readUleb128() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[_pos++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
    }
    return result;
  }

  int readSleb128() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      byte = bytes[_pos++];
      result |= (byte & 0x7F) << shift;
      shift += 7;
    } while (byte & 0x80 != 0);
    if (shift < 64 && (byte & 0x40) != 0) {
      result |= -(1 << shift);
    }
    return result;
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
  0x1a: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.string),
  ]),
  // const-string/jumbo (string@, 32-bit)
  0x1b: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.string, is32Bit: true),
  ]),
  // const-class, check-cast (type@)
  0x1c: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.type),
  ]),
  0x1f: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.type),
  ]),
  // instance-of, new-instance, new-array (type@)
  0x20: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.type),
  ]),
  0x22: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.type),
  ]),
  0x23: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.type),
  ]),
  // filled-new-array, filled-new-array/range (type@)
  0x24: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.type),
  ]),
  0x25: const _OpcodeIndexInfo([
    _IndexRef(1, _PoolKind.type),
  ]),
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
