// cspell:words Lcom Ljava
import 'dart:io';

import 'package:dex/src/dex_differ.dart';
import 'package:dex/src/dex_parser.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group(DexDiffer, () {
    const parser = DexParser();
    const differ = DexDiffer();

    final dexFixturesPath = p.join('test', 'fixtures', 'dex');

    late DexFile baseDex;

    setUp(() {
      baseDex = parser.parse(
        File(p.join(dexFixturesPath, 'base.dex')).readAsBytesSync(),
      );
    });

    DexFile parseDexFixture(String name) {
      return parser.parse(
        File(p.join(dexFixturesPath, name)).readAsBytesSync(),
      );
    }

    test('identical files produce empty diff', () {
      final result = differ.diff(baseDex, baseDex);
      expect(result.safeDifferences, isEmpty);
      expect(result.breakingDifferences, isEmpty);
      expect(result.isSafe, isTrue);
    });

    test('path-only difference is classified as safe', () {
      final pathDex = parseDexFixture('path_only_diff.dex');
      final result = differ.diff(baseDex, pathDex);
      expect(result.safeDifferences, isNotEmpty);
      expect(result.breakingDifferences, isEmpty);
      expect(result.isSafe, isTrue);
      expect(
        result.safeDifferences.every(
          (d) => d.kind == DexDifferenceKind.sourceFileChanged,
        ),
        isTrue,
      );
    });

    test('added method is classified as breaking', () {
      final methodAddedDex = parseDexFixture('method_added.dex');
      final result = differ.diff(baseDex, methodAddedDex);
      expect(result.isSafe, isFalse);
      expect(
        result.breakingDifferences.any(
          (d) => d.kind == DexDifferenceKind.methodAdded,
        ),
        isTrue,
      );
    });

    test('removed field is classified as breaking', () {
      final fieldRemovedDex = parseDexFixture('field_removed.dex');
      final result = differ.diff(baseDex, fieldRemovedDex);
      expect(result.isSafe, isFalse);
      expect(
        result.breakingDifferences.any(
          (d) => d.kind == DexDifferenceKind.fieldRemoved,
        ),
        isTrue,
      );
    });

    test('changed superclass is classified as breaking', () {
      final superclassChangedDex = parseDexFixture('superclass_changed.dex');
      final result = differ.diff(baseDex, superclassChangedDex);
      expect(result.isSafe, isFalse);
      expect(
        result.breakingDifferences.any(
          (d) => d.kind == DexDifferenceKind.superclassChanged,
        ),
        isTrue,
      );
    });

    test('mixed safe and breaking differences are not safe', () {
      final superclassChangedDex = parseDexFixture('superclass_changed.dex');
      final result = differ.diff(baseDex, superclassChangedDex);
      expect(result.isSafe, isFalse);
    });

    group('bytecode comparison', () {
      late DexFile baseWithCode;

      setUp(() {
        baseWithCode = parseDexFixture('base_with_code.dex');
      });

      test('identical bytecode is safe', () {
        final result = differ.diff(baseWithCode, baseWithCode);
        expect(result.isSafe, isTrue);
      });

      test('changed bytecode is breaking', () {
        final codeChanged = parseDexFixture('code_changed.dex');
        final result = differ.diff(baseWithCode, codeChanged);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences.any(
            (d) => d.kind == DexDifferenceKind.bytecodeChanged,
          ),
          isTrue,
        );
      });

      test('path-only diff with identical bytecode is safe', () {
        final pathWithCode = parseDexFixture('path_only_with_code.dex');
        final result = differ.diff(baseWithCode, pathWithCode);
        expect(result.isSafe, isTrue);
        expect(result.safeDifferences, isNotEmpty);
      });
    });

    group('describe', () {
      test('formats safe-only differences', () {
        final pathDex = parseDexFixture('path_only_diff.dex');
        final result = differ.diff(baseDex, pathDex);
        final description = result.describe();
        expect(description, contains('Safe differences'));
        expect(description, contains('source file changed'));
        expect(description, isNot(contains('Breaking differences')));
      });

      test('formats breaking differences', () {
        final methodAddedDex = parseDexFixture('method_added.dex');
        final result = differ.diff(baseDex, methodAddedDex);
        final description = result.describe();
        expect(description, contains('Breaking differences'));
        expect(description, contains('method added'));
      });

      test('empty diff produces empty string', () {
        final result = differ.diff(baseDex, baseDex);
        expect(result.describe(), isEmpty);
      });

      test('path-only diff produces exact output', () {
        final pathDex = parseDexFixture('path_only_diff.dex');
        final result = differ.diff(baseDex, pathDex);
        expect(result.describe(), equals('''
Safe differences (2):
  - Lcom/example/Helper;: source file changed from "Helper.java" to "/different/path/Helper.java"
  - Lcom/example/MyClass;: source file changed from "MyClass.java" to "/different/path/MyClass.java"'''));
      });

      test('method-added diff produces exact output', () {
        final methodAddedDex = parseDexFixture('method_added.dex');
        final result = differ.diff(baseDex, methodAddedDex);
        expect(result.describe(), equals('''
Breaking differences (1):
  - Lcom/example/MyClass;: method added: '''
            'Lcom/example/MyClass;.newMethod()V'));
      });

      test('bytecode-changed diff produces exact output', () {
        final baseWithCode =
            parseDexFixture('base_with_code.dex');
        final codeChanged = parseDexFixture('code_changed.dex');
        final result = differ.diff(baseWithCode, codeChanged);
        expect(result.describe(), equals('''
Breaking differences (1):
  - Lcom/example/Foo;: bytecode changed in '''
            'Lcom/example/Foo;.<init>()V'));
      });
    });

    group('DexDiffResult.identical', () {
      test('creates an empty result', () {
        const result = DexDiffResult.identical();
        expect(result.safeDifferences, isEmpty);
        expect(result.breakingDifferences, isEmpty);
        expect(result.isSafe, isTrue);
      });
    });

    group('DexDifferenceKind.isSafe', () {
      test('sourceFileChanged is safe', () {
        expect(DexDifferenceKind.sourceFileChanged.isSafe, isTrue);
      });

      test('classAdded is not safe', () {
        expect(DexDifferenceKind.classAdded.isSafe, isFalse);
      });

      test('classRemoved is not safe', () {
        expect(DexDifferenceKind.classRemoved.isSafe, isFalse);
      });

      test('methodAdded is not safe', () {
        expect(DexDifferenceKind.methodAdded.isSafe, isFalse);
      });

      test('methodRemoved is not safe', () {
        expect(DexDifferenceKind.methodRemoved.isSafe, isFalse);
      });

      test('fieldAdded is not safe', () {
        expect(DexDifferenceKind.fieldAdded.isSafe, isFalse);
      });

      test('fieldRemoved is not safe', () {
        expect(DexDifferenceKind.fieldRemoved.isSafe, isFalse);
      });

      test('accessFlagsChanged is not safe', () {
        expect(DexDifferenceKind.accessFlagsChanged.isSafe, isFalse);
      });

      test('superclassChanged is not safe', () {
        expect(DexDifferenceKind.superclassChanged.isSafe, isFalse);
      });

      test('interfacesChanged is not safe', () {
        expect(DexDifferenceKind.interfacesChanged.isSafe, isFalse);
      });

      test('bytecodeChanged is not safe', () {
        expect(DexDifferenceKind.bytecodeChanged.isSafe, isFalse);
      });

      test('annotationsChanged is not safe', () {
        expect(DexDifferenceKind.annotationsChanged.isSafe, isFalse);
      });

      test('staticValuesChanged is not safe', () {
        expect(DexDifferenceKind.staticValuesChanged.isSafe, isFalse);
      });
    });
  });
}
