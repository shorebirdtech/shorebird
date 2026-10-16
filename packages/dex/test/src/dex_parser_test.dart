// cspell:words Lcom Ljava Uleb
import 'dart:io';
import 'dart:typed_data';

import 'package:dex/src/dex_parser.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group(DexParser, () {
    const parser = DexParser();

    late Uint8List baseDexBytes;

    setUp(() {
      baseDexBytes = File(
        p.join('test', 'fixtures', 'dex', 'base.dex'),
      ).readAsBytesSync();
    });

    group('parse', () {
      test('parses a valid DEX file', () {
        final dex = parser.parse(baseDexBytes);
        expect(dex.strings, hasLength(13));
        expect(dex.typeDescriptors, hasLength(5));
        expect(dex.protoIds, hasLength(2));
        expect(dex.fieldIds, hasLength(2));
        expect(dex.methodIds, hasLength(3));
        expect(dex.classDefs, hasLength(2));
      });

      test('resolves string table values', () {
        final dex = parser.parse(baseDexBytes);
        expect(dex.strings, contains('<init>'));
        expect(dex.strings, contains('Lcom/example/MyClass;'));
        expect(dex.strings, contains('Ljava/lang/Object;'));
        expect(dex.strings, contains('myField'));
        expect(dex.strings, contains('getValue'));
      });

      test('resolves type descriptors', () {
        final dex = parser.parse(baseDexBytes);
        expect(dex.typeDescriptors, contains('I'));
        expect(dex.typeDescriptors, contains('V'));
        expect(dex.typeDescriptors, contains('Lcom/example/MyClass;'));
        expect(dex.typeDescriptors, contains('Lcom/example/Helper;'));
        expect(dex.typeDescriptors, contains('Ljava/lang/Object;'));
      });

      test('resolves field descriptors', () {
        final dex = parser.parse(baseDexBytes);
        final valueField = dex.fieldIds.firstWhere(
          (f) => f.fieldName == 'value',
        );
        expect(valueField.className, equals('Lcom/example/Helper;'));
        expect(valueField.typeName, equals('I'));

        final myField = dex.fieldIds.firstWhere(
          (f) => f.fieldName == 'myField',
        );
        expect(myField.className, equals('Lcom/example/MyClass;'));
        expect(myField.typeName, equals('I'));
      });

      test('resolves method descriptors', () {
        final dex = parser.parse(baseDexBytes);
        final getValue = dex.methodIds.firstWhere(
          (m) => m.methodName == 'getValue',
        );
        expect(getValue.className, equals('Lcom/example/Helper;'));
        expect(getValue.proto.returnType, equals('I'));
        expect(getValue.proto.parameterTypes, isEmpty);
      });

      test('resolves class definitions', () {
        final dex = parser.parse(baseDexBytes);
        final myClass = dex.classDefs.firstWhere(
          (c) => c.className == 'Lcom/example/MyClass;',
        );
        expect(myClass.accessFlags, equals(1)); // public
        expect(myClass.superclass, equals('Ljava/lang/Object;'));
        expect(myClass.interfaces, isEmpty);
        expect(myClass.sourceFile, equals('MyClass.java'));
        expect(myClass.classData, isNotNull);
        expect(myClass.classData!.instanceFields, hasLength(1));
        expect(myClass.classData!.directMethods, hasLength(1));
      });

      test('resolves class data fields and methods', () {
        final dex = parser.parse(baseDexBytes);
        final helper = dex.classDefs.firstWhere(
          (c) => c.className == 'Lcom/example/Helper;',
        );
        expect(helper.classData, isNotNull);
        expect(helper.classData!.instanceFields, hasLength(1));
        expect(
          helper.classData!.instanceFields[0].field.fieldName,
          equals('value'),
        );
        expect(helper.classData!.directMethods, hasLength(1));
        expect(
          helper.classData!.directMethods[0].method.methodName,
          equals('<init>'),
        );
        expect(helper.classData!.virtualMethods, hasLength(1));
        expect(
          helper.classData!.virtualMethods[0].method.methodName,
          equals('getValue'),
        );
      });

      test('parses code items', () {
        final dex = parser.parse(
          File(
            p.join('test', 'fixtures', 'dex', 'base_with_code.dex'),
          ).readAsBytesSync(),
        );
        final method = dex.classDefs[0].classData!.directMethods[0];
        expect(method.code, isA<DexCodeItem>());
        expect(method.code!.registersSize, isNonZero);
      });

      test('DexCodeItem has expected field values', () {
        final dex = parser.parse(
          File(
            p.join('test', 'fixtures', 'dex', 'base_with_code.dex'),
          ).readAsBytesSync(),
        );
        final method = dex.classDefs[0].classData!.directMethods[0];
        final code = method.code!;
        expect(code.registersSize, equals(1));
        expect(code.insSize, equals(1));
        expect(code.outsSize, equals(0));
        expect(code.canonicalBytecode, isNotEmpty);
      });

      test('parses annotations and staticValues', () {
        final dex = parser.parse(baseDexBytes);
        // Our test fixtures don't have annotations or static values.
        for (final classDef in dex.classDefs) {
          expect(classDef.annotations, isNull);
          expect(classDef.staticValues, isNull);
        }
      });
    });

    group('32-bit pool indices', () {
      // d8 only emits const-string/jumbo past 65536 strings, which no fixture
      // this size can reach. It is format 31c, the same three code units as
      // invoke-virtual, so overwriting one in place leaves every following
      // instruction at its original address.
      test('resolves a const-string/jumbo operand', () {
        final bytes = Uint8List.fromList(
          File(
            p.join('test', 'fixtures', 'dex', 'pool_refs.dex'),
          ).readAsBytesSync(),
        );

        final at = _indexOfInvokeVirtual(bytes);
        bytes[at] = 0x1b; // const-string/jumbo
        bytes[at + 1] = 0x01; // destination register
        bytes[at + 2] = 15; // string index, low half
        bytes[at + 3] = 0;
        bytes[at + 4] = 0; // string index, high half
        bytes[at + 5] = 0;

        final greet = parser
            .parse(bytes)
            .classDefs
            .expand(
              (c) => c.classData?.virtualMethods ?? const <DexEncodedMethod>[],
            )
            .firstWhere((m) => m.method.methodName == 'greet');
        final code = greet.code!;

        final rendered = [
          for (var i = 0; i < code.instructionCount; i++)
            code.instructionAt(i).render(showLiterals: true),
        ];

        expect(rendered[3], '283,S:hello ');
        expect(code.instructionAddresses[4], 10);

        // Swapping the halves makes the index 15 << 16, past the fixture's 20
        // strings. Reading only the low half would resolve it instead of
        // throwing, which is what pins the shift rather than the width.
        bytes[at + 2] = 0;
        bytes[at + 4] = 15;
        expect(() => parser.parse(bytes), throwsRangeError);
      });
    });

    group('error handling', () {
      test('throws FormatException for truncated file', () {
        expect(
          () => parser.parse(Uint8List.fromList([0x64, 0x65, 0x78])),
          throwsFormatException,
        );
      });

      test('throws FormatException for invalid magic bytes', () {
        final bad = Uint8List(112)..fillRange(0, 112, 0);
        expect(() => parser.parse(bad), throwsFormatException);
      });
    });

    // readUleb128, readUint16, and readUint32 are now internal to
    // _BinaryReader and exercised transitively through parse().
  });
}

/// File offset of the first `invoke-virtual` with a one-register argument
/// list: opcode `6e`, argument word count `20`, then its register list `0010`.
int _indexOfInvokeVirtual(Uint8List bytes) {
  for (var i = 0; i + 5 < bytes.length; i++) {
    if (bytes[i] == 0x6e &&
        bytes[i + 1] == 0x20 &&
        bytes[i + 4] == 0x10 &&
        bytes[i + 5] == 0x00) {
      return i;
    }
  }
  throw StateError('no invoke-virtual in fixture');
}
