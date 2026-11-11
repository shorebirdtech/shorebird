// cspell:words adrp cafebabe cafebabf chkstk cstring cstrings dsym dsyms
// cspell:words dylib dylibs fieldmd func funcs insn insns linkedit methname
// cspell:words movz objc pext reexport symtab
import 'dart:typed_data';

import 'package:macho/macho.dart';
import 'package:test/test.dart';

void main() {
  group(MachODiffer, () {
    const parser = MachOParser();
    const differ = MachODiffer();

    test('identical binaries produce MachODiffResult.identical', () {
      const identical = MachODiffResult.identical();
      expect(identical.isSafe, isTrue);
      expect(identical.differences, isEmpty);

      final bytes = MachOBuilder.buildThin(
        symbols: const [MachOSymbolSpec(name: '_main')],
        objcClassNames: const ['AppDelegate'],
        objcSelectors: const ['application:didFinishLaunchingWithOptions:'],
        cstrings: const ['hello'],
      );
      final result = differ.diffBytes(bytes, bytes);
      expect(result.isSafe, isTrue);
      expect(result.differences, isEmpty);
      expect(result.describe(), isEmpty);
    });

    group('safe differences (isSafe: true)', () {
      test('LC_UUID change is classified as safe (uuidChanged)', () {
        final oldBytes = MachOBuilder.buildThin(uuid: MachOBuilder.defaultUuid);
        final newBytes = MachOBuilder.buildThin(
          uuid: MachOBuilder.alternateUuid,
        );
        final noUuidBytes = MachOBuilder.buildThin(includeUuid: false);

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isTrue);
        expect(result.safeDifferences, hasLength(1));
        expect(
          result.safeDifferences.single.kind,
          MachODifferenceKind.uuidChanged,
        );
        expect(result.describe(), contains('Safe differences (1):'));
        expect(result.describe(), contains('LC_UUID changed'));

        final resultNoUuid = differ.diffBytes(oldBytes, noUuidBytes);
        expect(resultNoUuid.isSafe, isTrue);
        expect(
          resultNoUuid.safeDifferences.single.kind,
          MachODifferenceKind.uuidChanged,
        );
        expect(resultNoUuid.describe(), contains('<none>'));
      });

      test('LC_CODE_SIGNATURE and __LINKEDIT trailing padding changes are '
          'classified as safe (codeSignaturePaddingChanged)', () {
        final unsignedBytes = MachOBuilder.buildThin(
          symbols: const [MachOSymbolSpec(name: '_main')],
          linkeditTrailingPadding: Uint8List.fromList([0, 0, 0, 0]),
        );
        final signedBytes = MachOBuilder.buildThin(
          symbols: const [MachOSymbolSpec(name: '_main')],
          linkeditTrailingPadding: Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]),
          codeSignatureBytes: Uint8List.fromList([0xfa, 0xde, 0x0c, 0x02]),
        );

        final result = differ.diffBytes(unsignedBytes, signedBytes);
        expect(result.isSafe, isTrue);
        expect(
          result.safeDifferences.map((d) => d.kind),
          contains(MachODifferenceKind.codeSignaturePaddingChanged),
        );
      });

      test('unused ___chkstk_darwin undefined symbol entry added or removed '
          'is classified as safe (chkstkDarwinChanged)', () {
        final withoutChkstk = MachOBuilder.buildThin(
          symbols: const [
            MachOSymbolSpec(name: '_main'),
          ],
        );
        final withChkstk = MachOBuilder.buildThin(
          symbols: const [
            MachOSymbolSpec(name: '_main'),
            MachOSymbolSpec.undefined('___chkstk_darwin'),
          ],
        );

        final addedResult = differ.diffBytes(withoutChkstk, withChkstk);
        expect(addedResult.isSafe, isTrue);
        expect(
          addedResult.safeDifferences.single.kind,
          MachODifferenceKind.chkstkDarwinChanged,
        );

        final removedResult = differ.diffBytes(withChkstk, withoutChkstk);
        expect(removedResult.isSafe, isTrue);
        expect(
          removedResult.safeDifferences.single.kind,
          MachODifferenceKind.chkstkDarwinChanged,
        );
      });

      test('DWARF and N_OSO compile path changes are classified as safe '
          '(debugPathChanged)', () {
        final buildA = MachOBuilder.buildThin(
          symbols: const [
            MachOSymbolSpec(name: '_main'),
            MachOSymbolSpec.oso('/Users/alice/work/Runner.o'),
          ],
          dwarfStrings: const ['/Users/alice/work'],
        );
        final buildB = MachOBuilder.buildThin(
          symbols: const [
            MachOSymbolSpec(name: '_main'),
            MachOSymbolSpec.oso('/Users/bob/ci/Runner.o'),
          ],
          dwarfStrings: const ['/Users/bob/ci'],
        );

        final result = differ.diffBytes(buildA, buildB);
        expect(result.isSafe, isTrue);
        expect(
          result.safeDifferences.single.kind,
          MachODifferenceKind.debugPathChanged,
        );
      });

      test('PC-relative branch and ADRP target shifts that resolve to the '
          'same function/section produce no code diff', () {
        // Build 1: _helper at 0x1000, _main at 0x1008 calls _helper (-8 bytes)
        // and ADRPs __DATA,__const at 0x2000 (+1 page).
        final build1 = MachOBuilder.buildThin(
          textInstructions: [
            Arm64Encoder.ret(),
            Arm64Encoder.nop(),
            // _main at 0x1008:
            Arm64Encoder.bl(-8),
            Arm64Encoder.adrp(0, 1),
            Arm64Encoder.ret(),
          ],
          constSections: {
            '__DATA,__const': Uint8List.fromList([1, 2, 3, 4]),
          },
          symbols: const [
            MachOSymbolSpec(name: '_helper'),
            MachOSymbolSpec(name: '_main', nValue: 0x1008),
          ],
          functionStartOffsets: const [0, 8],
        );

        // Build 2: _main is at 0x1000 and _helper is at 0x100c, so _main's
        // BL displacement is +12 instead of -8, but both call _helper!
        final build2 = MachOBuilder.buildThin(
          textInstructions: [
            // _main at 0x1000:
            Arm64Encoder.bl(12),
            Arm64Encoder.adrp(0, 1),
            Arm64Encoder.ret(),
            // _helper at 0x100c:
            Arm64Encoder.ret(),
            Arm64Encoder.nop(),
          ],
          constSections: {
            '__DATA,__const': Uint8List.fromList([1, 2, 3, 4]),
          },
          symbols: const [
            MachOSymbolSpec(name: '_main'),
            MachOSymbolSpec(name: '_helper', nValue: 0x100c),
          ],
          functionStartOffsets: const [0, 12],
        );

        final result = differ.diffBytes(build1, build2);
        expect(result.isSafe, isTrue);
        expect(result.breakingDifferences, isEmpty);
      });
    });

    group('paired adversarial breaking differences (isSafe: false)', () {
      test('referenced ___chkstk_darwin or defined ___chkstk_darwin is '
          'classified as breaking (!isSafe)', () {
        final baseBytes = MachOBuilder.buildThin(
          textInstructions: [
            Arm64Encoder.nop(),
            Arm64Encoder.ret(),
          ],
          symbols: const [
            MachOSymbolSpec(name: '_main'),
          ],
        );

        // Adversarial 1: ___chkstk_darwin is called via a symbol stub at
        // 0x1040.
        final calledChkstkBytes = MachOBuilder.buildThin(
          textInstructions: [
            Arm64Encoder.bl(0x1040 - 0x1000),
            Arm64Encoder.ret(),
          ],
          extraSections: [
            MachOSectionSpec(
              segname: '__TEXT',
              sectname: '__stubs',
              bytes: Uint8List(12),
              addr: 0x1040,
              flags: MachOSectionType.symbolStubs,
              reserved2: 12,
            ),
          ],
          symbols: const [
            MachOSymbolSpec(name: '_main'),
            MachOSymbolSpec.undefined('___chkstk_darwin'),
          ],
          indirectSymbols: const [1],
        );

        final calledResult = differ.diffBytes(baseBytes, calledChkstkBytes);
        expect(calledResult.isSafe, isFalse);
        expect(
          calledResult.breakingDifferences.map((d) => d.kind),
          containsAll([
            MachODifferenceKind.symbolAdded,
            MachODifferenceKind.functionCodeChanged,
          ]),
        );

        // Adversarial 2: ___chkstk_darwin is a defined symbol rather than
        // undefined.
        final definedChkstkBytes = MachOBuilder.buildThin(
          textInstructions: [
            Arm64Encoder.nop(),
            Arm64Encoder.ret(),
          ],
          symbols: const [
            MachOSymbolSpec(name: '_main'),
            MachOSymbolSpec(name: '___chkstk_darwin', nValue: 0x1004),
          ],
        );

        final definedResult = differ.diffBytes(baseBytes, definedChkstkBytes);
        expect(definedResult.isSafe, isFalse);
        expect(
          definedResult.breakingDifferences.map((d) => d.kind),
          contains(MachODifferenceKind.symbolAdded),
        );
      });

      test(
        'symbolAdded, symbolRemoved, and symbolBindingChanged are breaking',
        () {
          final oldBytes = MachOBuilder.buildThin(
            symbols: const [
              MachOSymbolSpec(name: '_keep_and_change'),
              MachOSymbolSpec(name: '_both_sym_and_exp'),
              MachOSymbolSpec(name: '_removed_sym', nValue: 0x1004),
            ],
            exportedSymbols: const [
              MachOExportedSymbol(
                name: '_both_sym_and_exp',
                flags: 0,
                offset: 0,
              ),
              MachOExportedSymbol(name: '_export_only', flags: 0, offset: 0),
            ],
          );
          final newBytes = MachOBuilder.buildThin(
            symbols: const [
              // Changed from external to local + weak def.
              MachOSymbolSpec(
                name: '_keep_and_change',
                nType: MachOSymbolType.nSect | MachOSymbolType.nPext,
                nDesc: 0x0080,
              ),
              MachOSymbolSpec(name: '_both_sym_and_exp'),
              MachOSymbolSpec(name: '_added_sym', nValue: 0x1004),
            ],
            exportedSymbols: const [
              MachOExportedSymbol(
                name: '_both_sym_and_exp',
                flags: 0x04,
                offset: 0,
              ),
              MachOExportedSymbol(name: '_export_only', flags: 0x04, offset: 0),
            ],
          );

          final result = differ.diffBytes(oldBytes, newBytes);
          expect(result.isSafe, isFalse);
          final kinds = result.breakingDifferences.map((d) => d.kind).toList();
          expect(
            kinds,
            containsAll([
              MachODifferenceKind.symbolAdded,
              MachODifferenceKind.symbolRemoved,
              MachODifferenceKind.symbolBindingChanged,
            ]),
          );
          expect(result.describe(), contains('Breaking differences'));
        },
      );

      test('objcClassAdded, objcClassRemoved, objcSelectorAdded, and '
          'objcSelectorRemoved are breaking', () {
        final oldBytes = MachOBuilder.buildThin(
          objcClassNames: const ['AppDelegate', 'OldView'],
          objcSelectors: const ['init', 'oldMethod:'],
        );
        final newBytes = MachOBuilder.buildThin(
          objcClassNames: const ['AppDelegate', 'NewView'],
          objcSelectors: const ['init', 'newMethod:'],
        );

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences.map((d) => d.kind),
          containsAll([
            MachODifferenceKind.objcClassAdded,
            MachODifferenceKind.objcClassRemoved,
            MachODifferenceKind.objcSelectorAdded,
            MachODifferenceKind.objcSelectorRemoved,
          ]),
        );
      });

      test('swiftDescriptorChanged is breaking on added, removed, or modified '
          '__swift5_* sections', () {
        final oldBytes = MachOBuilder.buildThin(
          swiftSections: {
            '__TEXT,__swift5_types': Uint8List.fromList([1, 2, 3, 4]),
            '__TEXT,__swift5_proto': Uint8List.fromList([5, 6, 7, 8]),
          },
        );
        final newBytes = MachOBuilder.buildThin(
          swiftSections: {
            '__TEXT,__swift5_types': Uint8List.fromList([1, 2, 3, 99]),
            '__TEXT,__swift5_fieldmd': Uint8List.fromList([9, 10, 11, 12]),
          },
        );

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences
              .where(
                (d) => d.kind == MachODifferenceKind.swiftDescriptorChanged,
              )
              .length,
          3,
        );
      });

      test('cstringLiteralChanged is breaking on added, removed, or reordered '
          'C strings', () {
        final oldBytes = MachOBuilder.buildThin(
          cstrings: const ['alpha', 'beta'],
        );
        final newBytes = MachOBuilder.buildThin(
          cstrings: const ['alpha', 'gamma'],
        );
        final reorderedBytes = MachOBuilder.buildThin(
          cstrings: const ['beta', 'alpha'],
        );

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences.map((d) => d.kind),
          contains(MachODifferenceKind.cstringLiteralChanged),
        );

        final reorderedResult = differ.diffBytes(oldBytes, reorderedBytes);
        expect(reorderedResult.isSafe, isFalse);
        expect(
          reorderedResult.breakingDifferences.single.kind,
          MachODifferenceKind.cstringLiteralChanged,
        );
      });

      test(
        'dylibAdded, dylibRemoved, and dylibVersionChanged are breaking',
        () {
          final oldBytes = MachOBuilder.buildThin(
            dylibs: const [
              MachODylib(
                name: '@rpath/PostHog.framework/PostHog',
                cmd: MachOLoadCommandType.loadDylib,
                timestamp: 2,
                currentVersion: 0x00030100,
                compatibilityVersion: 0x00010000,
              ),
              MachODylib(
                name: '@rpath/WeakChanged.framework/WeakChanged',
                cmd: MachOLoadCommandType.loadDylib,
                timestamp: 2,
                currentVersion: 0x00010000,
                compatibilityVersion: 0x00010000,
              ),
              MachODylib(
                name: '@rpath/Removed.framework/Removed',
                cmd: MachOLoadCommandType.loadDylib,
                timestamp: 2,
                currentVersion: 0x00010000,
                compatibilityVersion: 0x00010000,
              ),
            ],
          );
          final newBytes = MachOBuilder.buildThin(
            dylibs: const [
              MachODylib(
                name: '@rpath/PostHog.framework/PostHog',
                cmd: MachOLoadCommandType.loadDylib,
                timestamp: 2,
                currentVersion: 0x00030200,
                compatibilityVersion: 0x00010000,
              ),
              MachODylib(
                name: '@rpath/WeakChanged.framework/WeakChanged',
                cmd: MachOLoadCommandType.loadWeakDylib,
                timestamp: 2,
                currentVersion: 0x00010000,
                compatibilityVersion: 0x00010000,
              ),
              MachODylib(
                name: '@rpath/Added.framework/Added',
                cmd: MachOLoadCommandType.loadDylib,
                timestamp: 2,
                currentVersion: 0x00010000,
                compatibilityVersion: 0x00010000,
              ),
            ],
          );

          final result = differ.diffBytes(oldBytes, newBytes);
          expect(result.isSafe, isFalse);
          expect(
            result.breakingDifferences.map((d) => d.kind),
            containsAll([
              MachODifferenceKind.dylibAdded,
              MachODifferenceKind.dylibRemoved,
              MachODifferenceKind.dylibVersionChanged,
            ]),
          );
        },
      );

      test('sectionAdded, sectionRemoved, and dataChanged are breaking', () {
        final oldBytes = MachOBuilder.buildThin(
          constSections: {
            '__DATA,__const': Uint8List.fromList([1, 2, 3, 4]),
          },
          extraSections: [
            MachOSectionSpec(
              segname: '__DATA',
              sectname: '__old_custom',
              bytes: Uint8List.fromList([1]),
            ),
          ],
        );
        final newBytes = MachOBuilder.buildThin(
          constSections: {
            '__DATA,__const': Uint8List.fromList([1, 2, 3, 5]),
          },
          extraSections: [
            MachOSectionSpec(
              segname: '__DATA',
              sectname: '__new_custom',
              bytes: Uint8List.fromList([2]),
            ),
          ],
        );

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences.map((d) => d.kind),
          containsAll([
            MachODifferenceKind.sectionAdded,
            MachODifferenceKind.sectionRemoved,
            MachODifferenceKind.dataChanged,
          ]),
        );
      });

      test('architectureChanged is breaking when fat slices or fileType '
          'differ', () {
        final armExec = MachOBuilder.buildThin();
        final armDylib = MachOBuilder.buildThin(
          fileType: MachOFileType.dylib,
        );
        final x86Exec = MachOBuilder.buildThin(
          cpuType: MachOCpuType.x86_64,
        );

        final fatBoth = MachOBuilder.buildFat([armExec, x86Exec]);
        final fatArmOnly = MachOBuilder.buildFat([armExec]);

        final addedSliceResult = differ.diffBytes(fatArmOnly, fatBoth);
        expect(addedSliceResult.isSafe, isFalse);
        expect(
          addedSliceResult.breakingDifferences.single.kind,
          MachODifferenceKind.architectureChanged,
        );

        final removedSliceResult = differ.diffBytes(fatBoth, fatArmOnly);
        expect(removedSliceResult.isSafe, isFalse);
        expect(
          removedSliceResult.breakingDifferences.single.kind,
          MachODifferenceKind.architectureChanged,
        );

        final fileTypeResult = differ.diffBytes(armExec, armDylib);
        expect(fileTypeResult.isSafe, isFalse);
        expect(
          fileTypeResult.breakingDifferences.single.kind,
          MachODifferenceKind.architectureChanged,
        );

        final customArch = MachOBuilder.buildThin(cpuType: 0x01000099);
        final customResult = differ.diffBytes(armExec, customArch);
        expect(customResult.isSafe, isFalse);
        expect(customResult.describe(), contains('cpu_0x1000099'));
      });

      test('unparseableBinary is breaking when old or new bytes are malformed, '
          'while malformed dSYM is ignored gracefully', () {
        final validBytes = MachOBuilder.buildThin();
        final corruptBytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);

        final badResult = differ.diffBytes(validBytes, corruptBytes);
        expect(badResult.isSafe, isFalse);
        expect(
          badResult.breakingDifferences.single.kind,
          MachODifferenceKind.unparseableBinary,
        );

        final badDsymResult = differ.diffBytes(
          validBytes,
          validBytes,
          oldDsymBytes: corruptBytes,
          newDsymBytes: corruptBytes,
        );
        expect(badDsymResult.isSafe, isTrue);
      });
    });

    group('functionCodeChanged and MachOCodeDiff rendering', () {
      test('detects single instruction mutation and names function via '
          'companion dSYM', () {
        final oldBin = MachOBuilder.buildThin(
          textInstructions: [
            Arm64Encoder.movz(0, 1),
            Arm64Encoder.ret(),
          ],
          functionStartOffsets: const [0],
        );
        final newBin = MachOBuilder.buildThin(
          textInstructions: [
            Arm64Encoder.movz(0, 2),
            Arm64Encoder.ret(),
          ],
          functionStartOffsets: const [0],
        );
        final dsym = MachOBuilder.buildDsym(
          symbols: const [
            MachOSymbolSpec(
              name: '_[AppDelegate handleMethodCall:]',
            ),
          ],
        );

        final result = differ.diffBytes(
          oldBin,
          newBin,
          oldDsymBytes: dsym,
          newDsymBytes: dsym,
        );
        expect(result.isSafe, isFalse);
        expect(result.breakingDifferences, hasLength(1));
        final diff = result.breakingDifferences.single;
        expect(diff.kind, MachODifferenceKind.functionCodeChanged);
        expect(
          diff.description,
          contains('_[AppDelegate handleMethodCall:]'),
        );
        expect(diff.codeDiff!.oldRegion, hasLength(1));
        expect(diff.codeDiff!.newRegion, hasLength(1));
        expect(result.describe(), contains('- 0x0000'));
        expect(result.describe(), contains('+ 0x0000'));
      });

      test(
        'detects anonymous function added or removed via LC_FUNCTION_STARTS',
        () {
          final oneFunc = MachOBuilder.buildThin(
            textInstructions: [
              Arm64Encoder.ret(),
            ],
            functionStartOffsets: const [0],
          );
          final twoFuncs = MachOBuilder.buildThin(
            textInstructions: [
              Arm64Encoder.ret(),
              Arm64Encoder.ret(),
            ],
            functionStartOffsets: const [0, 4],
          );

          final addedResult = differ.diff(
            parser.parse(oneFunc),
            parser.parse(twoFuncs),
          );
          expect(addedResult.isSafe, isFalse);
          expect(
            addedResult.describe(),
            contains('Function added in __TEXT,__text: sub_1'),
          );
          expect(addedResult.describe(), contains('function body added'));

          final removedResult = differ.diff(
            parser.parse(twoFuncs),
            parser.parse(oneFunc),
          );
          expect(removedResult.isSafe, isFalse);
          expect(
            removedResult.describe(),
            contains('Function removed from __TEXT,__text: sub_1'),
          );
          expect(removedResult.describe(), contains('function body removed'));
        },
      );

      test('handles string literal redaction, token limits, and '
          'defaultDetailedFunctionLimit in describe()', () {
        const longInsn = MachOCanonicalInstruction(
          address: 0,
          tokens: 'adrp,x0,S:secret_api_key,extra1,extra2,',
        );
        expect(longInsn.hasStringLiteral, isTrue);
        expect(longInsn.exceedsTokens(4), isTrue);
        expect(
          longInsn.render(showLiterals: false, limit: 4),
          'adrp x0 string(len=14) extra1 ...',
        );
        expect(
          longInsn.render(showLiterals: true),
          'adrp x0 S:secret_api_key extra1 extra2',
        );

        final newRegionLongDiff = MachOCodeDiff(
          oldRegion: const [
            MachOCanonicalInstruction(address: 0, tokens: 'insn,0xd65f03c0,'),
          ],
          newRegion: [
            const MachOCanonicalInstruction(
              address: 0,
              tokens: 'adrp,x0,S:new_str,t1,t2,',
            ),
            for (var i = 1; i < 6; i++)
              MachOCanonicalInstruction(
                address: i * 4,
                tokens: 'insn,0xd503201f,',
              ),
          ],
        );
        expect(newRegionLongDiff.exceeds(4), isTrue);
        expect(newRegionLongDiff.hasStringLiterals, isTrue);

        const tokenExceedDiff = MachOCodeDiff(
          oldRegion: [
            MachOCanonicalInstruction(
              address: 0,
              tokens: 'a,b,c,d,e,',
            ),
          ],
        );
        expect(tokenExceedDiff.exceeds(4), isTrue);

        const shortLiteralDiff = MachOCodeDiff(
          oldRegion: [
            MachOCanonicalInstruction(
              address: 0,
              tokens: 'adrp,x0,S:short,',
            ),
          ],
        );
        const singleHiddenResult = MachODiffResult(
          differences: [
            MachODifference(
              kind: MachODifferenceKind.functionCodeChanged,
              description: 'Function code changed in _fn',
              codeDiff: shortLiteralDiff,
            ),
          ],
        );
        expect(singleHiddenResult.hasHiddenCodeDiff, isTrue);

        final manyInsnDiff = MachOCodeDiff(
          oldRegion: List.generate(
            6,
            (i) => MachOCanonicalInstruction(
              address: i * 4,
              tokens: i == 0 ? 'adrp,x0,S:hello,' : 'insn,0xd503201f,',
            ),
          ),
          newRegion: const [
            MachOCanonicalInstruction(address: 0, tokens: 'insn,0xd65f03c0,'),
          ],
          sizeChange: 'size 24 -> 4 bytes',
        );
        expect(manyInsnDiff.exceeds(4), isTrue);
        expect(manyInsnDiff.hasStringLiterals, isTrue);

        final diffs = List.generate(
          12,
          (i) => MachODifference(
            kind: MachODifferenceKind.functionCodeChanged,
            description: 'Function code changed in _fn_$i',
            codeDiff: manyInsnDiff,
          ),
        );
        final diffResult = MachODiffResult(differences: diffs);
        expect(diffResult.hasHiddenCodeDiff, isTrue);

        final defaultDesc = diffResult.describe();
        expect(defaultDesc, contains('size 24 -> 4 bytes'));
        expect(defaultDesc, contains('string(len=5)'));
        expect(defaultDesc, contains('- ... 2 more'));
        expect(
          defaultDesc,
          contains('... 2 more changed functions not detailed'),
        );

        final fullDesc = diffResult.describe(showFullCodeDiff: true);
        expect(fullDesc, contains('S:hello'));
        expect(fullDesc, isNot(contains('changed functions not detailed')));
      });
    });
  });
}
