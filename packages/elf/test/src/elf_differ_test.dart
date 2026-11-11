// cspell:words aarch adrp debuglink dynstr dynsym execinstr fini ifunc insn
// cspell:words insns libc libfoo libnew libold movz nobits notype progbits
// cspell:words riscv rodata shndx soname symtab undef
import 'dart:typed_data';

import 'package:elf/elf.dart';
import 'package:test/test.dart';

void main() {
  group(ElfDiffer, () {
    const differ = ElfDiffer();

    test('identical binaries produce ElfDiffResult.identical', () {
      const identical = ElfDiffResult.identical();
      expect(identical.isSafe, isTrue);
      expect(identical.differences, isEmpty);

      final bytes = ElfBuilder.build(
        symbols: const [ElfSymbolSpec(name: 'native_add')],
        neededLibraries: const ['libc.so'],
        rodataStrings: const ['constant'],
        dataBytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      final result = differ.diffBytes(bytes, bytes);
      expect(result.isSafe, isTrue);
      expect(result.differences, isEmpty);
      expect(result.describe(), isEmpty);
    });

    group('safe differences (isSafe: true)', () {
      test('.note.gnu.build-id change is classified as safe '
          '(buildIdChanged)', () {
        final oldBytes = ElfBuilder.build(buildId: ElfBuilder.defaultBuildId);
        final newBytes = ElfBuilder.build(buildId: ElfBuilder.alternateBuildId);
        final noBuildIdBytes = ElfBuilder.build(includeBuildId: false);

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isTrue);
        expect(result.safeDifferences, hasLength(1));
        expect(
          result.safeDifferences.single.kind,
          ElfDifferenceKind.buildIdChanged,
        );
        expect(result.describe(), contains('Safe differences (1):'));
        expect(result.describe(), contains('.note.gnu.build-id changed'));

        final resultRemoved = differ.diffBytes(oldBytes, noBuildIdBytes);
        expect(resultRemoved.isSafe, isTrue);
        expect(resultRemoved.describe(), contains('<none>'));
      });

      test('.gnu_debuglink and .debug_* section changes are classified as '
          'safe (debugInfoChanged)', () {
        final buildA = ElfBuilder.build(
          debugLinkName: 'libfoo_a.so.debug',
          debugSections: {
            '.debug_str': Uint8List.fromList('/home/alice/foo.c\x00'.codeUnits),
          },
        );
        final buildB = ElfBuilder.build(
          debugLinkName: 'libfoo_b.so.debug',
          debugSections: {
            '.debug_str': Uint8List.fromList('/home/bob/foo.c\x00'.codeUnits),
            '.debug_line': Uint8List.fromList([1, 2, 3]),
          },
        );

        final result = differ.diffBytes(buildA, buildB);
        expect(result.isSafe, isTrue);
        expect(
          result.safeDifferences.single.kind,
          ElfDifferenceKind.debugInfoChanged,
        );

        // Same debugLink and same number of debugSections, but different
        // .debug_str payload bytes.
        final buildC = ElfBuilder.build(
          debugLinkName: 'libfoo_a.so.debug',
          debugSections: {
            '.debug_str': Uint8List.fromList('/home/carol/foo.c\x00'.codeUnits),
          },
        );
        final resultSameCount = differ.diffBytes(buildA, buildC);
        expect(resultSameCount.isSafe, isTrue);
        expect(
          resultSameCount.safeDifferences.single.kind,
          ElfDifferenceKind.debugInfoChanged,
        );
      });

      test('section header table ordering change when payloads match is '
          'classified as safe (debugInfoChanged)', () {
        final normalOrder = ElfBuilder.build(
          symbols: const [ElfSymbolSpec(name: 'native_fn')],
          rodataBytes: Uint8List.fromList([1, 2, 3, 4]),
          dataBytes: Uint8List.fromList([5, 6, 7, 8]),
        );
        final reversedOrder = ElfBuilder.build(
          symbols: const [ElfSymbolSpec(name: 'native_fn')],
          rodataBytes: Uint8List.fromList([1, 2, 3, 4]),
          dataBytes: Uint8List.fromList([5, 6, 7, 8]),
          reverseSectionOrder: true,
        );

        final result = differ.diffBytes(normalOrder, reversedOrder);
        expect(result.isSafe, isTrue);
        expect(
          result.safeDifferences.map((d) => d.kind),
          contains(ElfDifferenceKind.debugInfoChanged),
        );
      });

      test('PC-relative branch and ADRP target shifts that resolve to the '
          'same function/section produce no breaking code diff', () {
        final build1 = ElfBuilder.build(
          textInstructions: [
            // helper at 0x1000:
            ElfArm64Encoder.ret(),
            ElfArm64Encoder.nop(),
            // main_fn at 0x1008 calls helper (-8) and ADRPs .rodata (+1 page)
            ElfArm64Encoder.bl(-8),
            ElfArm64Encoder.adrp(0, 1),
            ElfArm64Encoder.ret(),
          ],
          rodataBytes: Uint8List.fromList([1, 2, 3, 4]),
          symbols: const [
            ElfSymbolSpec(name: 'helper'),
            ElfSymbolSpec(name: 'main_fn', value: 0x1008, size: 12),
          ],
        );

        final build2 = ElfBuilder.build(
          textInstructions: [
            // main_fn at 0x1000 calls helper (+12) and ADRPs .rodata (+1 page)
            ElfArm64Encoder.bl(12),
            ElfArm64Encoder.adrp(0, 1),
            ElfArm64Encoder.ret(),
            // helper at 0x100c:
            ElfArm64Encoder.ret(),
            ElfArm64Encoder.nop(),
          ],
          rodataBytes: Uint8List.fromList([1, 2, 3, 4]),
          symbols: const [
            ElfSymbolSpec(name: 'main_fn', size: 12),
            ElfSymbolSpec(name: 'helper', value: 0x100c),
          ],
        );

        final result = differ.diffBytes(build1, build2);
        expect(result.isSafe, isTrue);
        expect(result.breakingDifferences, isEmpty);
      });
    });

    group('paired adversarial breaking differences (isSafe: false)', () {
      test('added, removed, or modified .dynsym symbols are classified as '
          'breaking', () {
        final base = ElfBuilder.build(
          symbols: const [
            ElfSymbolSpec(name: 'keep_fn'),
            ElfSymbolSpec(
              name: 'change_sym',
              binding: ElfSymbolBinding.weak,
              type: ElfSymbolType.common,
              visibility: ElfSymbolVisibility.internal,
              sectionName: null,
              shndx: ElfSectionIndex.common,
            ),
            ElfSymbolSpec.undefined('old_import'),
          ],
        );
        final modified = ElfBuilder.build(
          symbols: const [
            ElfSymbolSpec(name: 'keep_fn'),
            ElfSymbolSpec(
              name: 'change_sym',
              type: ElfSymbolType.gnuIfunc,
              visibility: ElfSymbolVisibility.protectedVisibility,
              size: 16,
            ),
            ElfSymbolSpec(
              name: 'tls_sym',
              type: ElfSymbolType.tls,
              visibility: ElfSymbolVisibility.hidden,
            ),
            ElfSymbolSpec(
              name: 'os_specific_sym',
              binding: 10,
              type: 12,
            ),
            ElfSymbolSpec.undefined('new_import'),
          ],
        );

        final modified2 = ElfBuilder.build(
          symbols: const [
            ElfSymbolSpec(
              name: 'os_specific_sym',
              binding: 11,
              type: 13,
            ),
          ],
        );
        expect(differ.diffBytes(modified, modified2).isSafe, isFalse);

        final result = differ.diffBytes(base, modified);
        expect(result.isSafe, isFalse);
        final kinds = result.breakingDifferences.map((d) => d.kind).toSet();
        expect(
          kinds,
          containsAll([
            ElfDifferenceKind.symbolAdded,
            ElfDifferenceKind.symbolRemoved,
            ElfDifferenceKind.symbolBindingChanged,
          ]),
        );
        expect(result.describe(), contains('Breaking differences'));
      });

      test('.text instruction changes, .plt changes, and static function '
          'additions/removals are classified as breaking '
          '(functionCodeChanged)', () {
        final oldBytes = ElfBuilder.build(
          pltBytes: Uint8List.fromList([1, 2, 3, 4]),
          textInstructions: [
            ElfArm64Encoder.movz(0, 1),
            ElfArm64Encoder.adrp(0, 1),
            ElfArm64Encoder.addImm(0, 0, 0),
            ElfArm64Encoder.ret(),
            ElfArm64Encoder.ret(),
          ],
          rodataStrings: const ['old_literal'],
          symbols: const [ElfSymbolSpec(name: 'entry_fn')],
          staticSymbols: const [
            ElfSymbolSpec(
              name: 'only_old_static',
              value: 0x1010,
              size: 4,
              binding: ElfSymbolBinding.local,
            ),
          ],
        );

        final newBytes = ElfBuilder.build(
          pltBytes: Uint8List.fromList([1, 2, 3, 9]),
          textInstructions: [
            ElfArm64Encoder.movz(0, 2),
            ElfArm64Encoder.adrp(0, 1),
            ElfArm64Encoder.addImm(0, 0, 0),
            ElfArm64Encoder.nop(),
            ElfArm64Encoder.ret(),
            ElfArm64Encoder.ret(),
          ],
          rodataStrings: const ['new_literal'],
          symbols: const [ElfSymbolSpec(name: 'entry_fn', size: 20)],
          staticSymbols: const [
            ElfSymbolSpec(
              name: 'only_new_static',
              value: 0x1014,
              size: 4,
              binding: ElfSymbolBinding.local,
            ),
          ],
        );

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences.map((d) => d.kind),
          contains(ElfDifferenceKind.functionCodeChanged),
        );
        expect(result.hasHiddenCodeDiff, isTrue);
        expect(result.describe(), contains('size 16 -> 20 bytes'));
        expect(
          result.describe(showFullCodeDiff: true),
          contains('S:new_literal'),
        );
      });

      test('truncates codeDiff output when > 10 functions or > 4 instructions '
          'change', () {
        final oldInsns = <int>[];
        final newInsns = <int>[];
        final symbols = <ElfSymbolSpec>[];

        for (var f = 0; f < 12; f++) {
          final addr = 0x1000 + f * 24;
          symbols.add(ElfSymbolSpec(name: 'fn_$f', value: addr, size: 24));
          for (var i = 0; i < 6; i++) {
            oldInsns.add(ElfArm64Encoder.movz(0, i));
            newInsns.add(ElfArm64Encoder.movz(0, i + 100));
          }
        }

        final oldBytes = ElfBuilder.build(
          textInstructions: oldInsns,
          symbols: symbols,
        );
        final newBytes = ElfBuilder.build(
          textInstructions: newInsns,
          symbols: symbols,
        );

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isFalse);
        expect(result.hasHiddenCodeDiff, isTrue);
        final summary = result.describe();
        expect(summary, contains('... 2 more'));
        expect(summary, contains('... 2 more changed functions not detailed'));
      });

      test('.rodata, .data, .bss, DT_NEEDED, DT_SONAME, and custom section '
          'changes are classified as breaking', () {
        final oldBytes = ElfBuilder.build(
          neededLibraries: const ['libc.so', 'libold.so'],
          soname: 'libfoo.so.1',
          rodataBytes: Uint8List.fromList([1, 2, 3, 4]),
          dataBytes: Uint8List.fromList([5, 6, 7, 8]),
          bssSize: 16,
          extraSections: [
            ElfSectionSpec(
              name: '.only_old',
              bytes: Uint8List.fromList([1]),
            ),
            ElfSectionSpec(
              name: '.custom_exec',
              bytes: Uint8List.fromList([1, 2, 3, 4]),
              flags: ElfSectionFlags.alloc | ElfSectionFlags.execinstr,
            ),
            ElfSectionSpec(
              name: '.custom_rw',
              bytes: Uint8List.fromList([1, 2]),
              flags: ElfSectionFlags.alloc | ElfSectionFlags.write,
            ),
            ElfSectionSpec(
              name: '.custom_ro',
              bytes: Uint8List.fromList([3, 4]),
            ),
          ],
        );

        final newBytes = ElfBuilder.build(
          neededLibraries: const ['libc.so', 'libnew.so'],
          soname: 'libfoo.so.2',
          rodataBytes: Uint8List.fromList([1, 2, 3, 9]),
          dataBytes: Uint8List.fromList([5, 6, 7, 0]),
          bssSize: 64,
          extraSections: [
            ElfSectionSpec(
              name: '.only_new',
              bytes: Uint8List.fromList([2]),
            ),
            ElfSectionSpec(
              name: '.custom_exec',
              bytes: Uint8List.fromList([9, 9, 9, 9]),
              flags: ElfSectionFlags.alloc | ElfSectionFlags.execinstr,
            ),
            ElfSectionSpec(
              name: '.custom_rw',
              bytes: Uint8List.fromList([9, 9]),
              flags: ElfSectionFlags.alloc | ElfSectionFlags.write,
            ),
            ElfSectionSpec(
              name: '.custom_ro',
              bytes: Uint8List.fromList([8, 8]),
            ),
          ],
        );

        final result = differ.diffBytes(oldBytes, newBytes);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences.map((d) => d.kind).toSet(),
          containsAll([
            ElfDifferenceKind.neededLibraryAdded,
            ElfDifferenceKind.neededLibraryRemoved,
            ElfDifferenceKind.sonameChanged,
            ElfDifferenceKind.sectionAdded,
            ElfDifferenceKind.sectionRemoved,
            ElfDifferenceKind.rodataChanged,
            ElfDifferenceKind.dataChanged,
            ElfDifferenceKind.functionCodeChanged,
          ]),
        );
      });

      test('architecture, class, endianness, or fileType changes are '
          'classified as breaking (architectureChanged)', () {
        final arm64 = ElfBuilder.build();
        final arm32 = ElfBuilder.build(is64Bit: false, machine: ElfMachine.arm);
        final x86 = ElfBuilder.build(is64Bit: false, machine: ElfMachine.x86);
        final x64 = ElfBuilder.build(machine: ElfMachine.x86_64);
        final riscv = ElfBuilder.build(machine: ElfMachine.riscv);
        final customMach = ElfBuilder.build(machine: 0x999);
        final bigEndian = ElfBuilder.build(dataEncoding: ElfData.msb);

        for (final other in [
          arm32,
          x86,
          x64,
          riscv,
          customMach,
          bigEndian,
        ]) {
          final res = differ.diffBytes(arm64, other);
          expect(res.isSafe, isFalse);
          expect(
            res.breakingDifferences.single.kind,
            ElfDifferenceKind.architectureChanged,
          );
        }
      });

      test('unparseable or truncated binaries fail closed with '
          'unparseableBinary (isSafe: false)', () {
        final valid = ElfBuilder.build();
        final corrupted = Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46, 0, 0]);

        final result = differ.diffBytes(valid, corrupted);
        expect(result.isSafe, isFalse);
        expect(
          result.breakingDifferences.single.kind,
          ElfDifferenceKind.unparseableBinary,
        );
      });
    });
  });
}
