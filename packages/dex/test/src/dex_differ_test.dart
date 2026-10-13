// cspell:words Lcom Ljava LGreeter LFoo LPayloads
import 'dart:io';
import 'dart:typed_data';

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

    // Builds a one-class, one-method DexFile so a code item's fields can be
    // varied directly. The parser cannot produce every combination from a
    // fixture, and these branches decide what a blocked patch reports.
    DexFile dexWithCode({
      int registersSize = 1,
      int insSize = 1,
      int outsSize = 0,
      String instructions = '14,',
      String tryCatch = '',
    }) {
      final starts = Uint32List(1);
      final addresses = Uint32List(1);
      return DexFile(
        header: const DexHeader(
          stringIdsSize: 0,
          stringIdsOff: 0,
          typeIdsSize: 0,
          typeIdsOff: 0,
          protoIdsSize: 0,
          protoIdsOff: 0,
          fieldIdsSize: 0,
          fieldIdsOff: 0,
          methodIdsSize: 0,
          methodIdsOff: 0,
          classDefsSize: 0,
          classDefsOff: 0,
        ),
        strings: const [],
        typeDescriptors: const [],
        protoIds: const [],
        fieldIds: const [],
        methodIds: const [],
        classDefs: [
          DexClassDef(
            className: 'LFoo;',
            accessFlags: 1,
            superclass: null,
            interfaces: const [],
            sourceFile: null,
            annotations: null,
            staticValues: null,
            classData: DexClassData(
              staticFields: const [],
              instanceFields: const [],
              directMethods: [
                DexEncodedMethod(
                  method: const DexMethodId(
                    className: 'LFoo;',
                    methodName: 'run',
                    proto: DexProtoId(
                      shorty: 'V',
                      returnType: 'V',
                      parameterTypes: [],
                    ),
                  ),
                  accessFlags: 1,
                  code: DexCodeItem(
                    registersSize: registersSize,
                    insSize: insSize,
                    outsSize: outsSize,
                    canonicalInstructions: instructions,
                    instructionStarts: starts,
                    instructionAddresses: addresses,
                    canonicalTryCatch: tryCatch,
                  ),
                ),
              ],
              virtualMethods: const [],
            ),
          ),
        ],
      );
    }

    group('multi-instruction windows', () {
      DexFile dexWithInstructions(List<String> tokens) {
        final starts = Uint32List(tokens.length);
        final addresses = Uint32List(tokens.length);
        var offset = 0;
        for (var i = 0; i < tokens.length; i++) {
          starts[i] = offset;
          addresses[i] = i;
          offset += tokens[i].length;
        }
        return DexFile(
          header: const DexHeader(
            stringIdsSize: 0,
            stringIdsOff: 0,
            typeIdsSize: 0,
            typeIdsOff: 0,
            protoIdsSize: 0,
            protoIdsOff: 0,
            fieldIdsSize: 0,
            fieldIdsOff: 0,
            methodIdsSize: 0,
            methodIdsOff: 0,
            classDefsSize: 0,
            classDefsOff: 0,
          ),
          strings: const [],
          typeDescriptors: const [],
          protoIds: const [],
          fieldIds: const [],
          methodIds: const [],
          classDefs: [
            DexClassDef(
              className: 'LFoo;',
              accessFlags: 1,
              superclass: null,
              interfaces: const [],
              sourceFile: null,
              annotations: null,
              staticValues: null,
              classData: DexClassData(
                staticFields: const [],
                instanceFields: const [],
                directMethods: [
                  DexEncodedMethod(
                    method: const DexMethodId(
                      className: 'LFoo;',
                      methodName: 'run',
                      proto: DexProtoId(
                        shorty: 'V',
                        returnType: 'V',
                        parameterTypes: [],
                      ),
                    ),
                    accessFlags: 1,
                    code: DexCodeItem(
                      registersSize: 1,
                      insSize: 1,
                      outsSize: 0,
                      canonicalInstructions: tokens.join(),
                      instructionStarts: starts,
                      instructionAddresses: addresses,
                      canonicalTryCatch: '',
                    ),
                  ),
                ],
                virtualMethods: const [],
              ),
            ),
          ],
        );
      }

      test('two edits separated by matching code share one window', () {
        final result = differ.diff(
          dexWithInstructions(['a,', 'b,', 'c,', 'd,']),
          dexWithInstructions(['X,', 'b,', 'c,', 'Y,']),
        );

        final codeDiff = result.breakingDifferences.single.codeDiff!;
        // The shared b and c sit inside the window, not outside it.
        expect(codeDiff.oldRegion.map((i) => i.tokens).toList(), [
          'a,',
          'b,',
          'c,',
          'd,',
        ]);
        expect(codeDiff.newRegion.map((i) => i.tokens).toList(), [
          'X,',
          'b,',
          'c,',
          'Y,',
        ]);
      });

      test('a matching head and tail are trimmed off the window', () {
        final result = differ.diff(
          dexWithInstructions(['a,', 'b,', 'c,']),
          dexWithInstructions(['a,', 'Z,', 'c,']),
        );

        final codeDiff = result.breakingDifferences.single.codeDiff!;
        expect(codeDiff.oldRegion.map((i) => i.tokens).toList(), ['b,']);
        expect(codeDiff.newRegion.map((i) => i.tokens).toList(), ['Z,']);
      });

      test('an added instruction leaves the other region empty', () {
        final result = differ.diff(
          dexWithInstructions(['a,', 'c,']),
          dexWithInstructions(['a,', 'b,', 'c,']),
        );

        final codeDiff = result.breakingDifferences.single.codeDiff!;
        expect(codeDiff.oldRegion, isEmpty);
        expect(codeDiff.newRegion.map((i) => i.tokens).toList(), ['b,']);
      });
    });

    group('size and try/catch changes', () {
      test('reports a register count change', () {
        final result = differ.diff(
          dexWithCode(),
          dexWithCode(registersSize: 2),
        );
        expect(
          result.describe(),
          contains('registers 1 -> 2'),
        );
      });

      test('reports an incoming argument count change', () {
        final result = differ.diff(dexWithCode(), dexWithCode(insSize: 2));
        expect(result.describe(), contains('incoming args 1 -> 2'));
      });

      test('reports an outgoing argument count change', () {
        final result = differ.diff(dexWithCode(), dexWithCode(outsSize: 3));
        expect(result.describe(), contains('outgoing args 0 -> 3'));
      });

      test('reports every size change together', () {
        final result = differ.diff(
          dexWithCode(),
          dexWithCode(registersSize: 2, insSize: 2, outsSize: 3),
        );
        final described = result.describe();
        expect(described, contains('registers 1 -> 2'));
        expect(described, contains('incoming args 1 -> 2'));
        expect(described, contains('outgoing args 0 -> 3'));
      });

      test('reports a try/catch table change with no instruction diff', () {
        final result = differ.diff(
          dexWithCode(),
          dexWithCode(tryCatch: 'HL:1,HS:1,T:Ljava/lang/Exception;,A:4,'),
        );
        expect(result.breakingDifferences, hasLength(1));
        expect(result.describe(), contains('try/catch table changed'));
      });

      test('reports a method body added or removed', () {
        final withCode = dexWithCode();
        final withoutCode = DexFile(
          header: withCode.header,
          strings: const [],
          typeDescriptors: const [],
          protoIds: const [],
          fieldIds: const [],
          methodIds: const [],
          classDefs: const [
            DexClassDef(
              className: 'LFoo;',
              accessFlags: 1,
              superclass: null,
              interfaces: [],
              sourceFile: null,
              annotations: null,
              staticValues: null,
              classData: DexClassData(
                staticFields: [],
                instanceFields: [],
                directMethods: [
                  DexEncodedMethod(
                    method: DexMethodId(
                      className: 'LFoo;',
                      methodName: 'run',
                      proto: DexProtoId(
                        shorty: 'V',
                        returnType: 'V',
                        parameterTypes: [],
                      ),
                    ),
                    accessFlags: 1,
                    code: null,
                  ),
                ],
                virtualMethods: [],
              ),
            ),
          ],
        );

        final result = differ.diff(withCode, withoutCode);
        expect(result.breakingDifferences, hasLength(1));
        expect(
          result.describe(),
          contains('method body added or removed'),
        );
      });

      test('identical code items produce no difference', () {
        final result = differ.diff(dexWithCode(), dexWithCode());
        expect(result.differences, isEmpty);
      });
    });

    group('code diff', () {
      test('names the resolved method reference that changed', () {
        final result = differ.diff(
          parseDexFixture('pool_refs.dex'),
          parseDexFixture('pool_refs_changed.dex'),
        );

        expect(result.breakingDifferences, hasLength(1));
        final diff = result.breakingDifferences.single;
        expect(diff.kind, DexDifferenceKind.bytecodeChanged);

        final codeDiff = diff.codeDiff!;
        expect(
          codeDiff.oldRegion.map((i) => i.tokens).join(),
          contains('M:Ljava/lang/String;.equals(Ljava/lang/Object;)Z'),
        );
        expect(
          codeDiff.newRegion.map((i) => i.tokens).join(),
          contains(
            'M:Ljava/lang/String;.equalsIgnoreCase(Ljava/lang/String;)Z',
          ),
        );
      });

      test('trims the matching head and tail from both regions', () {
        final result = differ.diff(
          parseDexFixture('pool_refs.dex'),
          parseDexFixture('pool_refs_changed.dex'),
        );

        final codeDiff = result.breakingDifferences.single.codeDiff!;
        // Only the invoke differs; the field read and the return are shared.
        expect(codeDiff.oldRegion, hasLength(1));
        expect(codeDiff.newRegion, hasLength(1));
      });

      test('reports a register count change the regions cannot show', () {
        const unchanged = [
          DexCanonicalInstruction(address: 0, tokens: '14,'),
        ];
        final diff = const DexCodeDiff(
          oldRegion: unchanged,
          newRegion: unchanged,
          sizeChange: 'registers 1 -> 2',
        ).describe();

        expect(diff, contains('registers 1 -> 2'));
      });

      test('caps instructions per side and counts the rest', () {
        final region = [
          for (var i = 0; i < 7; i++)
            DexCanonicalInstruction(address: i, tokens: '$i,'),
        ];

        final capped = DexCodeDiff(oldRegion: region).describe(limit: 4);
        expect(capped, contains('... 3 more'));
        expect('- 0x'.allMatches(capped), hasLength(4));

        final full = DexCodeDiff(oldRegion: region).describe();
        expect(full, isNot(contains('more')));
        expect('- 0x'.allMatches(full), hasLength(7));
      });

      test('showFullCodeDiff shows every differing instruction', () {
        final result = differ.diff(
          parseDexFixture('pool_refs.dex'),
          parseDexFixture('pool_refs_changed.dex'),
        );

        expect(
          result.describe(showFullCodeDiff: true),
          contains('equalsIgnoreCase'),
        );
      });
    });

    group('string literals', () {
      test('are escaped in the canonical form so no token holds a comma', () {
        final dex = parseDexFixture('payloads.dex');
        final method = dex.classDefs
            .expand((c) => c.classData!.virtualMethods)
            .firstWhere((m) => m.method.methodName == 'secret');

        final tokens = method.code!.canonicalInstructions;
        expect(tokens, contains('S:token-abc%2C123'));
        expect(tokens, isNot(contains('S:token-abc,123')));
      });

      test('are replaced by their length by default', () {
        const instruction = DexCanonicalInstruction(
          address: 0,
          tokens: '26,S:token-abc%2C123,',
        );

        expect(instruction.hasStringLiteral, isTrue);
        expect(
          const DexCodeDiff(oldRegion: [instruction]).describe(),
          contains('S:<13 chars>'),
        );
        expect(
          const DexCodeDiff(oldRegion: [instruction]).describe(),
          isNot(contains('token-abc')),
        );
      });

      test('are printed when the caller asks', () {
        const instruction = DexCanonicalInstruction(
          address: 0,
          tokens: '26,S:token-abc%2C123,',
        );

        expect(
          const DexCodeDiff(
            oldRegion: [instruction],
          ).describe(showStringLiterals: true),
          contains('S:token-abc,123'),
        );
      });

      test('leave an instruction without one untouched', () {
        const instruction = DexCanonicalInstruction(
          address: 0,
          tokens: '4208,M:Ljava/lang/Object;.<init>()V,',
        );

        expect(instruction.hasStringLiteral, isFalse);
        expect(
          instruction.render(showLiterals: false),
          '4208,M:Ljava/lang/Object;.<init>()V',
        );
      });
    });

    group('resolved references', () {
      test('are one token however many parameters they carry', () {
        const instruction = DexCanonicalInstruction(
          address: 2,
          tokens: '8302,M:LFoo;.bar(La;%2CLb;%2CLc;%2CLd;)V,32,',
        );

        expect(instruction.tokenCount, 3);
        expect(
          instruction.exceedsTokens(DexCodeDiff.defaultTokenLimit),
          isFalse,
        );
        expect(
          instruction.render(
            showLiterals: false,
            limit: DexCodeDiff.defaultTokenLimit,
          ),
          '8302,M:LFoo;.bar(La;,Lb;,Lc;,Ld;)V,32',
        );
      });

      test('a one-parameter method reference reads plainly', () {
        final dex = parseDexFixture('pool_refs.dex');
        final tokens = dex.classDefs.first.classData!.virtualMethods
            .firstWhere((m) => m.method.methodName == 'matches')
            .code!
            .canonicalInstructions;

        // One parameter, so nothing to escape, and the token reads plainly.
        expect(
          tokens,
          contains('M:Ljava/lang/String;.equals(Ljava/lang/Object;)Z'),
        );
      });
    });

    group('payloads', () {
      test('parse as single instructions carrying their data', () {
        final dex = parseDexFixture('payloads.dex');
        final methods = dex.classDefs
            .expand((c) => c.classData!.virtualMethods)
            .toList();

        for (final name in ['packed', 'sparse', 'filled']) {
          final code = methods
              .firstWhere((m) => m.method.methodName == name)
              .code!;
          expect(code.instructionCount, greaterThan(1));
          expect(code.canonicalInstructions, isNotEmpty);
          // Every instruction is addressable and the last one ends the string.
          final last = code.tokensAt(code.instructionCount - 1);
          expect(code.canonicalInstructions, endsWith(last));
        }
      });

      test('withhold their data on the default path', () {
        final dex = parseDexFixture('payloads.dex');
        final code = dex.classDefs.first.classData!.virtualMethods
            .firstWhere((m) => m.method.methodName == 'filled')
            .code!;
        final payload = [
          for (var i = 0; i < code.instructionCount; i++) code.instructionAt(i),
        ].reduce((a, b) => a.tokenCount >= b.tokenCount ? a : b);

        // fill-array-data for {7, 8, 9, 10, 11, 12, 13, 14}: a 4-unit header
        // then the data, as one instruction.
        expect(payload.tokenCount, 20);
        expect(payload.exceedsTokens(DexCodeDiff.defaultTokenLimit), isTrue);

        final rendered = payload.render(
          showLiterals: false,
          limit: DexCodeDiff.defaultTokenLimit,
        );
        // The header says what it is. None of the eight values appear.
        expect(rendered, '768,4,8,0,... 16 more units');

        expect(
          payload.render(showLiterals: true),
          contains('768,4,8,0,7,0,8,0,9,0'),
        );
      });

      test('count as hidden detail so the hint fires', () {
        final dex = parseDexFixture('payloads.dex');
        final code = dex.classDefs.first.classData!.virtualMethods
            .firstWhere((m) => m.method.methodName == 'filled')
            .code!;
        final result = DexDiffResult(
          differences: [
            DexDifference(
              kind: DexDifferenceKind.bytecodeChanged,
              description: 'LPayloads;: bytecode changed in filled',
              codeDiff: DexCodeDiff(
                oldRegion: [
                  for (var i = 0; i < code.instructionCount; i++)
                    code.instructionAt(i),
                ],
              ),
            ),
          ],
        );

        expect(result.hasHiddenCodeDiff, isTrue);
        final described = result.describe();
        // The payload sits past the per-side instruction cap, so it is held
        // back entirely. Either way none of the eight array values appear.
        expect(described, contains('... 1 more'));
        expect(described, isNot(contains('768,4,8,0,7')));

        // A region holding only the payload reaches the token cap instead.
        final payloadOnly = DexCodeDiff(
          oldRegion: [code.instructionAt(code.instructionCount - 1)],
        );
        expect(payloadOnly.describe(limit: 4), contains('more units'));
        expect(payloadOnly.describe(limit: 4), isNot(contains(',7,0,8,0')));
      });

      test('a lone payload is hidden by the token cap, not the side cap', () {
        final dex = parseDexFixture('payloads.dex');
        final code = dex.classDefs.first.classData!.virtualMethods
            .firstWhere((m) => m.method.methodName == 'filled')
            .code!;
        final result = DexDiffResult(
          differences: [
            DexDifference(
              kind: DexDifferenceKind.bytecodeChanged,
              description: 'LPayloads;: bytecode changed in filled',
              codeDiff: DexCodeDiff(
                oldRegion: [code.instructionAt(code.instructionCount - 1)],
              ),
            ),
          ],
        );

        // One instruction, so the per-side cap cannot fire and only the token
        // cap is left to report the payload as withheld.
        expect(result.hasHiddenCodeDiff, isTrue);
      });

      test('a method compares equal to itself', () {
        final dex = parseDexFixture('payloads.dex');
        expect(differ.diff(dex, dex).differences, isEmpty);
      });
    });

    group('detail caps', () {
      test('renders a token with no trailing comma unchanged', () {
        const instruction = DexCanonicalInstruction(
          address: 3,
          tokens: '14',
        );

        expect(
          const DexCodeDiff(oldRegion: [instruction]).describe(),
          contains('0x0003  14'),
        );
      });

      test('exceeds reports whether a limit would hide an instruction', () {
        final region = [
          for (var i = 0; i < 3; i++)
            DexCanonicalInstruction(address: i, tokens: '$i,'),
        ];

        expect(DexCodeDiff(oldRegion: region).exceeds(2), isTrue);
        expect(DexCodeDiff(newRegion: region).exceeds(2), isTrue);
        expect(DexCodeDiff(oldRegion: region).exceeds(3), isFalse);
      });

      test('reports hidden detail at the method cap boundary', () {
        DexDiffResult resultWith(int methods) => DexDiffResult(
          differences: [
            for (var i = 0; i < methods; i++)
              DexDifference(
                kind: DexDifferenceKind.bytecodeChanged,
                description: 'LFoo;: bytecode changed in LFoo;.m$i()V',
                codeDiff: DexCodeDiff(
                  oldRegion: [
                    DexCanonicalInstruction(address: 0, tokens: '$i,'),
                  ],
                ),
              ),
          ],
        );

        final atLimit = resultWith(DexDiffResult.defaultDetailedMethodLimit);
        expect(atLimit.hasHiddenCodeDiff, isFalse);
        expect(atLimit.describe(), isNot(contains('not detailed')));

        final overLimit = resultWith(
          DexDiffResult.defaultDetailedMethodLimit + 1,
        );
        expect(overLimit.hasHiddenCodeDiff, isTrue);
        expect(
          overLimit.describe(),
          contains('... 1 more changed methods not detailed'),
        );
      });

      test('caps detailed methods and counts the rest', () {
        final result = DexDiffResult(
          differences: [
            for (var i = 0; i < 12; i++)
              DexDifference(
                kind: DexDifferenceKind.bytecodeChanged,
                description: 'LFoo;: bytecode changed in LFoo;.m$i()V',
                codeDiff: DexCodeDiff(
                  oldRegion: [
                    DexCanonicalInstruction(address: 0, tokens: '$i,'),
                  ],
                ),
              ),
          ],
        );

        expect(result.hasHiddenCodeDiff, isTrue);
        expect(
          result.describe(),
          contains('... 2 more changed methods not detailed'),
        );
        expect(
          result.describe(showFullCodeDiff: true),
          isNot(contains('not detailed')),
        );
      });

      test('hasHiddenCodeDiff is false when nothing is held back', () {
        const result = DexDiffResult(
          differences: [
            DexDifference(
              kind: DexDifferenceKind.bytecodeChanged,
              description: 'LFoo;: bytecode changed in LFoo;.m()V',
              codeDiff: DexCodeDiff(
                oldRegion: [
                  DexCanonicalInstruction(address: 0, tokens: '14,'),
                ],
              ),
            ),
          ],
        );

        expect(result.hasHiddenCodeDiff, isFalse);
      });

      test('hasHiddenCodeDiff is true when a literal is redacted', () {
        const result = DexDiffResult(
          differences: [
            DexDifference(
              kind: DexDifferenceKind.bytecodeChanged,
              description: 'LFoo;: bytecode changed in LFoo;.m()V',
              codeDiff: DexCodeDiff(
                oldRegion: [
                  DexCanonicalInstruction(address: 0, tokens: '26,S:abc,'),
                ],
              ),
            ),
          ],
        );

        expect(result.hasHiddenCodeDiff, isTrue);
      });
    });

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
        expect(
          result.describe(),
          equals(
            '''
Safe differences (2):
  - Lcom/example/Helper;: source file changed from "Helper.java" to "/different/path/Helper.java"
  - Lcom/example/MyClass;: source file changed from "MyClass.java" to "/different/path/MyClass.java"''',
          ),
        );
      });

      test('method-added diff produces exact output', () {
        final methodAddedDex = parseDexFixture('method_added.dex');
        final result = differ.diff(baseDex, methodAddedDex);
        expect(
          result.describe(),
          equals(
            '''
Breaking differences (1):
  - Lcom/example/MyClass;: method added: '''
            'Lcom/example/MyClass;.newMethod()V',
          ),
        );
      });

      test('bytecode-changed diff produces exact output', () {
        final baseWithCode = parseDexFixture('base_with_code.dex');
        final codeChanged = parseDexFixture('code_changed.dex');
        final result = differ.diff(baseWithCode, codeChanged);
        expect(
          result.describe(),
          equals(
            '''
Breaking differences (1):
  - Lcom/example/Foo;: bytecode changed in '''
            'Lcom/example/Foo;.<init>()V\n'
            '      + 0x0000  18',
          ),
        );
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
