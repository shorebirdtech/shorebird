// cspell:words aarch addralign adrp debuglink descsz dynstr dynsym ehdr ehsize
// cspell:words elfclass elfdata entsize execinstr fini funcs ifunc immhi immlo
// cspell:words insn insns libarm libc libdl libfoo liblog libm libnative movz
// cspell:words namesz nobits notype phdr phentsize phnum phoff progbits rela
// cspell:words riscv rodata shdr shentsize shndx shnum shoff shstrndx shstrtab
// cspell:words soname strtab symtab undef
import 'dart:typed_data';

import 'package:elf/elf.dart';
import 'package:test/test.dart';

void main() {
  group(ElfParser, () {
    const parser = ElfParser();

    group('isElfBytes', () {
      test('recognizes 4-byte ELF magic and rejects non-ELF inputs', () {
        expect(ElfParser.isElfBytes(Uint8List(0)), isFalse);
        expect(ElfParser.isElfBytes(Uint8List.fromList([0x7f, 0x45])), isFalse);
        expect(
          ElfParser.isElfBytes(Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46])),
          isTrue,
        );
        expect(
          ElfParser.isElfBytes(Uint8List.fromList([0xcf, 0xfa, 0xed, 0xfe])),
          isFalse,
        );
      });
    });

    group('ELF64 parsing', () {
      test('parses headers, .dynsym, .dynstr, .dynamic DT_NEEDED/DT_SONAME, '
          '.text, .plt, .rodata, .data, .bss, .note.gnu.build-id, '
          '.gnu_debuglink, and .debug_* sections', () {
        final bytes = ElfBuilder.build(
          includeProgramHeader: true,
          buildId: ElfBuilder.defaultBuildId,
          soname: 'libnative.so',
          neededLibraries: const ['libc.so', 'libm.so', 'liblog.so'],
          pltBytes: Uint8List.fromList([0x10, 0x20, 0x30, 0x40]),
          textInstructions: [
            ElfArm64Encoder.movz(0, 42),
            // Intra-function branch to offset +8 (pc=0x1004 -> target=0x100c)
            ElfArm64Encoder.b(8),
            ElfArm64Encoder.nop(),
            // Branch to helper at 0x1020 from pc=0x100c (+20 bytes)
            ElfArm64Encoder.bl(0x1020 - 0x100c),
            // Branch to unmapped address 0x1080 from pc=0x1010 (+112 bytes)
            ElfArm64Encoder.bl(0x1080 - 0x1010),
            // ADRP x0 to .rodata page at 0x2000 (delta +1 page) + ADD #0
            ElfArm64Encoder.adrp(0, 1),
            ElfArm64Encoder.addImm(0, 0, 0),
            ElfArm64Encoder.ret(),
            // helper at 0x1020:
            // ADRP xzr to .data page at 0x3000 (delta +2 pages)
            ElfArm64Encoder.adrp(31, 2),
            // ADRP x2 with negative page delta (-1 page -> 0x0000)
            ElfArm64Encoder.adrp(2, -1),
            // ADRP x1 to unmapped page at 0x9000 (delta +8 pages) + shifted ADD
            ElfArm64Encoder.adrp(1, 8),
            ElfArm64Encoder.addImm(1, 1, 1, shift12: true),
            ElfArm64Encoder.ret(),
          ],
          rodataStrings: const ['hello_ffi', 'channel_name'],
          dataBytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
          bssSize: 32,
          symbols: const [
            ElfSymbolSpec(
              name: 'Java_com_example_MainActivity_compute',
              size: 32,
            ),
            ElfSymbolSpec(
              name: 'helper_func',
              value: 0x1020,
              size: 20,
              binding: ElfSymbolBinding.weak,
              visibility: ElfSymbolVisibility.protectedVisibility,
            ),
            ElfSymbolSpec(
              name: 'hidden_var',
              value: 0x3000,
              binding: ElfSymbolBinding.local,
              type: ElfSymbolType.object,
              visibility: ElfSymbolVisibility.hidden,
              sectionName: '.data',
            ),
            ElfSymbolSpec(
              name: 'abs_const',
              value: 0xff,
              size: 0,
              type: ElfSymbolType.notype,
              sectionName: null,
              shndx: ElfSectionIndex.abs,
            ),
            ElfSymbolSpec.undefined('__android_log_print'),
          ],
          staticSymbols: const [
            ElfSymbolSpec(
              name: 'file.c',
              value: 0,
              size: 0,
              binding: ElfSymbolBinding.local,
              type: ElfSymbolType.file,
              sectionName: null,
              shndx: ElfSectionIndex.abs,
            ),
            ElfSymbolSpec(
              name: '',
              binding: ElfSymbolBinding.local,
              type: ElfSymbolType.section,
            ),
          ],
          debugLinkName: 'libnative.so.debug',
          debugSections: {
            '.debug_info': Uint8List.fromList([0xde, 0xad]),
            '.debug_str': Uint8List.fromList(
              '/build/src/native.c\x00'.codeUnits,
            ),
          },
          extraSections: [
            ElfSectionSpec(
              name: '.rodata.cst4',
              bytes: Uint8List.fromList([9, 9, 9, 9]),
            ),
            ElfSectionSpec(
              name: '.init_array',
              bytes: Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]),
              flags: ElfSectionFlags.alloc | ElfSectionFlags.write,
            ),
          ],
        );

        final elf = parser.parse(bytes);
        expect(elf.header.is64Bit, isTrue);
        expect(elf.header.isLittleEndian, isTrue);
        expect(elf.header.endian, Endian.little);
        expect(elf.header.fileType, ElfFileType.dyn);
        expect(elf.header.machine, ElfMachine.aarch64);
        expect(elf.header.phnum, 1);

        expect(elf.buildId, equals(ElfBuilder.defaultBuildId));
        expect(elf.soname, 'libnative.so');
        expect(elf.neededLibraries, ['libc.so', 'libm.so', 'liblog.so']);
        expect(elf.debugLinkName, 'libnative.so.debug');
        expect(elf.debugLink, isNotNull);
        expect(
          elf.debugSections.keys,
          containsAll(['.debug_info', '.debug_str']),
        );
        expect(
          elf.rodataSections.keys,
          containsAll(['.rodata', '.rodata.cst4']),
        );
        expect(elf.dataSections.keys, containsAll(['.data', '.init_array']));
        expect(elf.bssSize, 32);
        expect(elf.pltSection, isNotNull);
        expect(elf.sectionByName('.nonexistent'), isNull);

        expect(elf.symbols, hasLength(5));
        expect(
          elf.exportedSymbolNames,
          {'Java_com_example_MainActivity_compute', 'helper_func', 'abs_const'},
        );
        expect(elf.importedSymbolNames, {'__android_log_print'});

        final computeSym = elf.symbols.firstWhere(
          (s) => s.name == 'Java_com_example_MainActivity_compute',
        );
        expect(computeSym.isGlobal, isTrue);
        expect(computeSym.isWeak, isFalse);
        expect(computeSym.isLocal, isFalse);
        expect(computeSym.isFunction, isTrue);
        expect(computeSym.isExported, isTrue);
        expect(computeSym.sectionName, '.text');

        final helperSym = elf.symbols.firstWhere(
          (s) => s.name == 'helper_func',
        );
        expect(helperSym.isWeak, isTrue);
        expect(helperSym.isExported, isTrue);

        final hiddenSym = elf.symbols.firstWhere(
          (s) => s.name == 'hidden_var',
        );
        expect(hiddenSym.isLocal, isTrue);
        expect(hiddenSym.isExported, isFalse);
        expect(hiddenSym.isFunction, isFalse);

        final funcs = elf.resolveFunctions();
        expect(funcs, hasLength(2));
        expect(funcs[0].name, 'Java_com_example_MainActivity_compute');
        expect(funcs[0].isAnonymous, isFalse);
        expect(funcs[0].canonicalInstructions, contains('b,+0xc,'));
        expect(funcs[0].canonicalInstructions, contains('bl,helper_func,'));
        expect(funcs[0].canonicalInstructions, contains('bl,0x1080,'));
        expect(
          funcs[0].canonicalInstructions,
          contains('adrp,x0,S:hello_ffi,'),
        );

        expect(funcs[1].name, 'helper_func');
        expect(funcs[1].canonicalInstructions, contains('adrp,xzr,.data+0x0,'));
        expect(
          funcs[1].canonicalInstructions,
          contains('adrp,x1,page(0x9000),'),
        );

        // Verify ElfCanonicalInstruction rendering helpers.
        final adrpInsn = funcs[0].instructionAt(5);
        expect(adrpInsn.hasStringLiteral, isTrue);
        expect(
          adrpInsn.render(showLiterals: false),
          contains('string(len=9)'),
        );
        expect(
          adrpInsn.render(showLiterals: true),
          contains('S:hello_ffi'),
        );
        expect(adrpInsn.exceedsTokens(2), isTrue);
        expect(adrpInsn.render(showLiterals: false, limit: 2), endsWith('...'));

        const emptyInsn = ElfCanonicalInstruction(address: 0, tokens: '');
        expect(emptyInsn.exceedsTokens(1), isFalse);
        expect(emptyInsn.render(showLiterals: false), isEmpty);
      });

      test('parses raw build-id bytes when note header is non-standard', () {
        final rawId = Uint8List.fromList([0xaa, 0xbb, 0xcc, 0xdd]);
        final bytes = ElfBuilder.build(
          buildId: rawId,
          rawBuildIdSection: true,
        );
        final elf = parser.parse(bytes);
        expect(elf.buildId, equals(rawId));
      });
    });

    group('ELF32 and big-endian parsing', () {
      test('parses 32-bit ARM little-endian and strips Thumb bit in '
          'resolveFunctions', () {
        // 6 bytes of instructions (one 4-byte word + two trailing bytes) and a
        // leading anonymous prefix before thumb_func at 0x1004 (value=0x1005).
        final textRaw = Uint8List.fromList([
          0x01, 0x02, 0x03, 0x04, // sub_0 at 0x1000
          0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, // thumb_func at 0x1004
        ]);
        final bytes = ElfBuilder.build(
          is64Bit: false,
          machine: ElfMachine.arm,
          includeProgramHeader: true,
          textBytes: textRaw,
          symbols: const [
            ElfSymbolSpec(
              name: 'thumb_func',
              value: 0x1005, // Thumb bit 0 set
              size: 6,
            ),
          ],
          staticSymbols: const [
            ElfSymbolSpec(
              name: 'local_static',
              value: 0x1005,
              size: 6,
              binding: ElfSymbolBinding.local,
            ),
          ],
          neededLibraries: const ['libc.so'],
          soname: 'libarm32.so',
        );

        final elf = parser.parse(bytes);
        expect(elf.header.is64Bit, isFalse);
        expect(elf.header.machine, ElfMachine.arm);
        expect(elf.soname, 'libarm32.so');
        expect(elf.neededLibraries, ['libc.so']);

        final funcs = elf.resolveFunctions();
        expect(funcs, hasLength(2));
        expect(funcs[0].name, 'sub_0');
        expect(funcs[0].isAnonymous, isTrue);
        expect(funcs[1].name, 'thumb_func');
        expect(funcs[1].isAnonymous, isFalse);
        expect(funcs[1].canonicalInstructions, contains('word,'));
        expect(funcs[1].canonicalInstructions, contains('byte,'));
      });

      test('parses big-endian ELF64 with unnamed .text section', () {
        final bytes = ElfBuilder.build(
          dataEncoding: ElfData.msb,
          machine: ElfMachine.x86_64,
          textBytes: Uint8List.fromList([1, 2, 3, 4]),
        );

        final elf = parser.parse(bytes);
        expect(elf.header.isLittleEndian, isFalse);
        expect(elf.header.endian, Endian.big);
        final funcs = elf.resolveFunctions();
        expect(funcs.single.name, '.text');
      });

      test('parses ELF with shnum == 0 and empty .text', () {
        final base = ElfBuilder.build(textBytes: Uint8List(0));
        final parsedEmptyText = parser.parse(base);
        expect(parsedEmptyText.resolveFunctions(), isEmpty);

        // Zero out shnum and shstrndx in ELF64 header.
        final noSections = Uint8List.fromList(base);
        ByteData.sublistView(noSections)
          ..setUint16(60, 0, Endian.little) // e_shnum = 0
          ..setUint16(62, 0, Endian.little); // e_shstrndx = 0
        final parsedNoSections = parser.parse(noSections);
        expect(parsedNoSections.sections, isEmpty);
      });

      test(
        'resolves linked string table by fallback name when sh_link == 0',
        () {
          final bytes = ElfBuilder.build(
            symbols: const [ElfSymbolSpec(name: 'exported_sym')],
            neededLibraries: const ['libdl.so'],
            extraSections: [
              ElfSectionSpec(
                name: '.symtab',
                bytes: Uint8List(24),
                type: ElfSectionType.symtab,
                entsize: 24,
              ),
            ],
          );
          // Set sh_link = 0 on .dynsym and .dynamic sections.
          final copy = Uint8List.fromList(bytes);
          final data = ByteData.sublistView(copy);
          final shoff = data.getUint64(40, Endian.little);
          final shentsize = data.getUint16(58, Endian.little);
          final shnum = data.getUint16(60, Endian.little);
          for (var i = 0; i < shnum; i++) {
            final off = shoff + i * shentsize;
            final shType = data.getUint32(off + 4, Endian.little);
            if (shType == ElfSectionType.dynsym ||
                shType == ElfSectionType.dynamicSection) {
              data.setUint32(off + 40, 0, Endian.little); // sh_link = 0
            }
          }
          final elf = parser.parse(copy);
          expect(elf.exportedSymbolNames, {'exported_sym'});
          expect(elf.neededLibraries, ['libdl.so']);
        },
      );
    });

    group('corruption and truncation error handling', () {
      test('throws ElfFormatException on truncated or invalid headers', () {
        expect(
          () => parser.parse(Uint8List(8)),
          throwsA(isA<ElfFormatException>()),
        );

        final badMagic = Uint8List(64)..[0] = 0x00;
        expect(
          () => parser.parse(badMagic),
          throwsA(isA<ElfFormatException>()),
        );

        final badClass = Uint8List.fromList(ElfBuilder.build())..[4] = 99;
        expect(
          () => parser.parse(badClass),
          throwsA(isA<ElfFormatException>()),
        );

        final badData = Uint8List.fromList(ElfBuilder.build())..[5] = 99;
        expect(
          () => parser.parse(badData),
          throwsA(isA<ElfFormatException>()),
        );

        final badIdentVer = Uint8List.fromList(ElfBuilder.build())..[6] = 0;
        expect(
          () => parser.parse(badIdentVer),
          throwsA(isA<ElfFormatException>()),
        );

        final truncated64 = ElfBuilder.build().sublist(0, 32);
        expect(
          () => parser.parse(truncated64),
          throwsA(isA<ElfFormatException>()),
        );

        final truncated32 = ElfBuilder.build(is64Bit: false).sublist(0, 32);
        expect(
          () => parser.parse(truncated32),
          throwsA(isA<ElfFormatException>()),
        );
      });

      test('throws ElfFormatException on out-of-bounds program or section '
          'headers', () {
        // Out-of-bounds program header table.
        final badPhdr = Uint8List.fromList(
          ElfBuilder.build(includeProgramHeader: true),
        );
        ByteData.sublistView(badPhdr).setUint64(32, 0xffffff, Endian.little);
        expect(
          () => parser.parse(badPhdr),
          throwsA(isA<ElfFormatException>()),
        );

        // Invalid e_shentsize (< 64).
        final badShentsize = Uint8List.fromList(ElfBuilder.build());
        ByteData.sublistView(badShentsize).setUint16(58, 16, Endian.little);
        expect(
          () => parser.parse(badShentsize),
          throwsA(isA<ElfFormatException>()),
        );

        // Out-of-bounds e_shoff.
        final badShoff = Uint8List.fromList(ElfBuilder.build());
        ByteData.sublistView(badShoff).setUint64(40, 0xffffff, Endian.little);
        expect(
          () => parser.parse(badShoff),
          throwsA(isA<ElfFormatException>()),
        );

        // Out-of-bounds e_shstrndx.
        final badShstrndx = Uint8List.fromList(ElfBuilder.build());
        ByteData.sublistView(badShstrndx).setUint16(62, 999, Endian.little);
        expect(
          () => parser.parse(badShstrndx),
          throwsA(isA<ElfFormatException>()),
        );

        // Section payload out of bounds.
        final badSectRange = Uint8List.fromList(ElfBuilder.build());
        final data = ByteData.sublistView(badSectRange);
        final shoff = data.getUint64(40, Endian.little);
        data.setUint64(shoff + 64 + 32, 0xffffff, Endian.little); // sh_size
        expect(
          () => parser.parse(badSectRange),
          throwsA(isA<ElfFormatException>()),
        );

        // Section sh_name out of bounds of .shstrtab.
        final badShName = Uint8List.fromList(ElfBuilder.build());
        final data2 = ByteData.sublistView(badShName);
        final shoff2 = data2.getUint64(40, Endian.little);
        data2.setUint32(shoff2 + 64, 0xffffff, Endian.little); // sh_name
        expect(
          () => parser.parse(badShName),
          throwsA(isA<ElfFormatException>()),
        );

        // shstrndx == 0 with non-zero sh_name.
        final emptyShstrtab = Uint8List.fromList(ElfBuilder.build());
        ByteData.sublistView(emptyShstrtab).setUint16(62, 0, Endian.little);
        expect(
          () => parser.parse(emptyShstrtab),
          throwsA(isA<ElfFormatException>()),
        );
      });

      test('throws ElfFormatException on corrupted .dynsym or .dynamic '
          'tables', () {
        final base = ElfBuilder.build(
          symbols: const [ElfSymbolSpec(name: 'foo')],
          neededLibraries: const ['libc.so'],
          soname: 'libfoo.so',
        );

        int findSectionHeaderOffset(Uint8List buf, int targetType) {
          final d = ByteData.sublistView(buf);
          final shoff = d.getUint64(40, Endian.little);
          final shentsize = d.getUint16(58, Endian.little);
          final shnum = d.getUint16(60, Endian.little);
          for (var i = 0; i < shnum; i++) {
            final off = shoff + i * shentsize;
            if (d.getUint32(off + 4, Endian.little) == targetType) {
              return off;
            }
          }
          throw StateError('Section type $targetType not found');
        }

        // 1. Invalid .dynsym entsize (< 24).
        final badSymEntsize = Uint8List.fromList(base);
        final dynsymHdr = findSectionHeaderOffset(
          badSymEntsize,
          ElfSectionType.dynsym,
        );
        ByteData.sublistView(badSymEntsize).setUint64(
          dynsymHdr + 56,
          7,
          Endian.little,
        );
        expect(
          () => parser.parse(badSymEntsize),
          throwsA(isA<ElfFormatException>()),
        );

        // 2. Out-of-bounds .dynsym sh_link.
        final badSymLink = Uint8List.fromList(base);
        ByteData.sublistView(badSymLink).setUint32(
          dynsymHdr + 40,
          999,
          Endian.little,
        );
        expect(
          () => parser.parse(badSymLink),
          throwsA(isA<ElfFormatException>()),
        );

        // 3. Out-of-bounds symbol st_name.
        final badSymName = Uint8List.fromList(base);
        final symDataOff = ByteData.sublistView(badSymName).getUint64(
          dynsymHdr + 24,
          Endian.little,
        );
        ByteData.sublistView(badSymName).setUint32(
          symDataOff + 24,
          0xffffff,
          Endian.little,
        );
        expect(
          () => parser.parse(badSymName),
          throwsA(isA<ElfFormatException>()),
        );

        // 4. Out-of-bounds symbol st_shndx.
        final badSymShndx = Uint8List.fromList(base);
        ByteData.sublistView(badSymShndx).setUint16(
          symDataOff + 24 + 6,
          999,
          Endian.little,
        );
        expect(
          () => parser.parse(badSymShndx),
          throwsA(isA<ElfFormatException>()),
        );

        // 5. Invalid .dynamic entsize (< 16).
        final badDynEntsize = Uint8List.fromList(base);
        final dynHdr = findSectionHeaderOffset(
          badDynEntsize,
          ElfSectionType.dynamicSection,
        );
        ByteData.sublistView(badDynEntsize).setUint64(
          dynHdr + 56,
          5,
          Endian.little,
        );
        expect(
          () => parser.parse(badDynEntsize),
          throwsA(isA<ElfFormatException>()),
        );

        // 6. Out-of-bounds DT_NEEDED string offset.
        final badNeededOff = Uint8List.fromList(base);
        final dynDataOff = ByteData.sublistView(badNeededOff).getUint64(
          dynHdr + 24,
          Endian.little,
        );
        ByteData.sublistView(badNeededOff).setUint64(
          dynDataOff + 8,
          0xffffff,
          Endian.little,
        );
        expect(
          () => parser.parse(badNeededOff),
          throwsA(isA<ElfFormatException>()),
        );

        // 7. Out-of-bounds DT_SONAME string offset.
        final badSonameOff = Uint8List.fromList(base);
        ByteData.sublistView(badSonameOff).setUint64(
          dynDataOff + 16 + 8,
          0xffffff,
          Endian.little,
        );
        expect(
          () => parser.parse(badSonameOff),
          throwsA(isA<ElfFormatException>()),
        );
      });
    });
  });
}
