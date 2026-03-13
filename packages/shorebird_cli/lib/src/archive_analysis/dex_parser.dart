// cspell:words uleb mutf
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
  });

  /// The resolved method identifier.
  final DexMethodId method;

  /// Access flags.
  final int accessFlags;
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
    final typeDescriptors = _parseTypeDescriptors(bytes, header, strings);
    final protoIds = _parseProtoIds(bytes, header, strings, typeDescriptors);
    final fieldIds = _parseFieldIds(bytes, header, strings, typeDescriptors);
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
    return DexHeader(
      stringIdsSize: _readUint32(bytes, 56),
      stringIdsOff: _readUint32(bytes, 60),
      typeIdsSize: _readUint32(bytes, 64),
      typeIdsOff: _readUint32(bytes, 68),
      protoIdsSize: _readUint32(bytes, 72),
      protoIdsOff: _readUint32(bytes, 76),
      fieldIdsSize: _readUint32(bytes, 80),
      fieldIdsOff: _readUint32(bytes, 84),
      methodIdsSize: _readUint32(bytes, 88),
      methodIdsOff: _readUint32(bytes, 92),
      classDefsSize: _readUint32(bytes, 96),
      classDefsOff: _readUint32(bytes, 100),
    );
  }

  List<String> _parseStrings(Uint8List bytes, DexHeader header) {
    final strings = <String>[];
    for (var i = 0; i < header.stringIdsSize; i++) {
      final stringDataOff = _readUint32(bytes, header.stringIdsOff + i * 4);
      strings.add(_readMutf8String(bytes, stringDataOff));
    }
    return strings;
  }

  List<String> _parseTypeDescriptors(
    Uint8List bytes,
    DexHeader header,
    List<String> strings,
  ) {
    final types = <String>[];
    for (var i = 0; i < header.typeIdsSize; i++) {
      final stringIdx = _readUint32(bytes, header.typeIdsOff + i * 4);
      types.add(strings[stringIdx]);
    }
    return types;
  }

  List<DexProtoId> _parseProtoIds(
    Uint8List bytes,
    DexHeader header,
    List<String> strings,
    List<String> typeDescriptors,
  ) {
    final protos = <DexProtoId>[];
    for (var i = 0; i < header.protoIdsSize; i++) {
      final offset = header.protoIdsOff + i * 12;
      final shortyIdx = _readUint32(bytes, offset);
      final returnTypeIdx = _readUint32(bytes, offset + 4);
      final parametersOff = _readUint32(bytes, offset + 8);

      final parameterTypes = <String>[];
      if (parametersOff != 0) {
        final paramCount = _readUint32(bytes, parametersOff);
        for (var j = 0; j < paramCount; j++) {
          final typeIdx = _readUint16(bytes, parametersOff + 4 + j * 2);
          parameterTypes.add(typeDescriptors[typeIdx]);
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
    final fields = <DexFieldId>[];
    for (var i = 0; i < header.fieldIdsSize; i++) {
      final offset = header.fieldIdsOff + i * 8;
      final classIdx = _readUint16(bytes, offset);
      final typeIdx = _readUint16(bytes, offset + 2);
      final nameIdx = _readUint32(bytes, offset + 4);

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
    final methods = <DexMethodId>[];
    for (var i = 0; i < header.methodIdsSize; i++) {
      final offset = header.methodIdsOff + i * 8;
      final classIdx = _readUint16(bytes, offset);
      final protoIdx = _readUint16(bytes, offset + 2);
      final nameIdx = _readUint32(bytes, offset + 4);

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
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    final classDefs = <DexClassDef>[];
    for (var i = 0; i < header.classDefsSize; i++) {
      final offset = header.classDefsOff + i * 32;
      final classIdx = _readUint32(bytes, offset);
      final accessFlags = _readUint32(bytes, offset + 4);
      final superclassIdx = _readUint32(bytes, offset + 8);
      final interfacesOff = _readUint32(bytes, offset + 12);
      final sourceFileIdx = _readUint32(bytes, offset + 16);
      final classDataOff = _readUint32(bytes, offset + 24);

      final interfaces = <String>[];
      if (interfacesOff != 0) {
        final count = _readUint32(bytes, interfacesOff);
        for (var j = 0; j < count; j++) {
          final typeIdx = _readUint16(bytes, interfacesOff + 4 + j * 2);
          interfaces.add(typeDescriptors[typeIdx]);
        }
      }

      DexClassData? classData;
      if (classDataOff != 0) {
        classData = _parseClassData(
          bytes,
          classDataOff,
          fieldIds,
          methodIds,
        );
      }

      classDefs.add(
        DexClassDef(
          className: typeDescriptors[classIdx],
          accessFlags: accessFlags,
          superclass: superclassIdx == _noIndex
              ? null
              : typeDescriptors[superclassIdx],
          interfaces: interfaces,
          sourceFile:
              sourceFileIdx == _noIndex ? null : strings[sourceFileIdx],
          classData: classData,
        ),
      );
    }
    return classDefs;
  }

  DexClassData _parseClassData(
    Uint8List bytes,
    int offset,
    List<DexFieldId> fieldIds,
    List<DexMethodId> methodIds,
  ) {
    var pos = offset;
    final (staticFieldsSize, b1) = _readUleb128(bytes, pos);
    pos += b1;
    final (instanceFieldsSize, b2) = _readUleb128(bytes, pos);
    pos += b2;
    final (directMethodsSize, b3) = _readUleb128(bytes, pos);
    pos += b3;
    final (virtualMethodsSize, b4) = _readUleb128(bytes, pos);
    pos += b4;

    final staticFields = <DexEncodedField>[];
    var fieldIdx = 0;
    for (var i = 0; i < staticFieldsSize; i++) {
      final (fieldIdxDiff, fb1) = _readUleb128(bytes, pos);
      pos += fb1;
      final (accessFlags, fb2) = _readUleb128(bytes, pos);
      pos += fb2;
      fieldIdx += fieldIdxDiff;
      staticFields.add(
        DexEncodedField(field: fieldIds[fieldIdx], accessFlags: accessFlags),
      );
    }

    final instanceFields = <DexEncodedField>[];
    fieldIdx = 0;
    for (var i = 0; i < instanceFieldsSize; i++) {
      final (fieldIdxDiff, fb1) = _readUleb128(bytes, pos);
      pos += fb1;
      final (accessFlags, fb2) = _readUleb128(bytes, pos);
      pos += fb2;
      fieldIdx += fieldIdxDiff;
      instanceFields.add(
        DexEncodedField(field: fieldIds[fieldIdx], accessFlags: accessFlags),
      );
    }

    final directMethods = <DexEncodedMethod>[];
    var methodIdx = 0;
    for (var i = 0; i < directMethodsSize; i++) {
      final (methodIdxDiff, mb1) = _readUleb128(bytes, pos);
      pos += mb1;
      final (accessFlags, mb2) = _readUleb128(bytes, pos);
      pos += mb2;
      final (_, mb3) = _readUleb128(bytes, pos); // code_off, skipped
      pos += mb3;
      methodIdx += methodIdxDiff;
      directMethods.add(
        DexEncodedMethod(
          method: methodIds[methodIdx],
          accessFlags: accessFlags,
        ),
      );
    }

    final virtualMethods = <DexEncodedMethod>[];
    methodIdx = 0;
    for (var i = 0; i < virtualMethodsSize; i++) {
      final (methodIdxDiff, mb1) = _readUleb128(bytes, pos);
      pos += mb1;
      final (accessFlags, mb2) = _readUleb128(bytes, pos);
      pos += mb2;
      final (_, mb3) = _readUleb128(bytes, pos); // code_off, skipped
      pos += mb3;
      methodIdx += methodIdxDiff;
      virtualMethods.add(
        DexEncodedMethod(
          method: methodIds[methodIdx],
          accessFlags: accessFlags,
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

  /// Reads a MUTF-8 encoded string from the given offset.
  ///
  /// The format is: ULEB128 length (in UTF-16 code units), followed by
  /// MUTF-8 encoded bytes, followed by a null terminator.
  String _readMutf8String(Uint8List bytes, int offset) {
    // Skip the ULEB128 size prefix (size in UTF-16 code units, not bytes).
    final (_, sizeBytes) = _readUleb128(bytes, offset);
    var pos = offset + sizeBytes;

    final codeUnits = <int>[];
    while (pos < bytes.length && bytes[pos] != 0) {
      final byte1 = bytes[pos++];
      if (byte1 & 0x80 == 0) {
        // Single-byte character (0xxxxxxx).
        codeUnits.add(byte1);
      } else if (byte1 & 0xE0 == 0xC0) {
        // Two-byte character (110xxxxx 10xxxxxx).
        final byte2 = bytes[pos++];
        codeUnits.add(((byte1 & 0x1F) << 6) | (byte2 & 0x3F));
      } else if (byte1 & 0xF0 == 0xE0) {
        // Three-byte character (1110xxxx 10xxxxxx 10xxxxxx).
        final byte2 = bytes[pos++];
        final byte3 = bytes[pos++];
        codeUnits.add(
          ((byte1 & 0x0F) << 12) | ((byte2 & 0x3F) << 6) | (byte3 & 0x3F),
        );
      }
    }

    return String.fromCharCodes(codeUnits);
  }

  /// Reads an unsigned LEB128 value from the given offset.
  ///
  /// Returns a record of (value, bytesConsumed).
  static (int, int) _readUleb128(Uint8List bytes, int offset) {
    var result = 0;
    var shift = 0;
    var bytesConsumed = 0;

    while (true) {
      final byte = bytes[offset + bytesConsumed];
      bytesConsumed++;
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
    }

    return (result, bytesConsumed);
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

/// Reads an unsigned LEB128 value from the given offset.
///
/// Returns a record of (value, bytesConsumed).
(int, int) readUleb128(Uint8List bytes, int offset) {
  return DexParser._readUleb128(bytes, offset);
}

/// Reads a 16-bit unsigned integer as a little-endian value.
int readUint16(Uint8List bytes, int offset) {
  return DexParser._readUint16(bytes, offset);
}

/// Reads a 32-bit unsigned integer as a little-endian value.
int readUint32(Uint8List bytes, int offset) {
  return DexParser._readUint32(bytes, offset);
}
