// cspell:words adrp cafebabe cafebabf chkstk cputype cpusubtype cstring
// cspell:words cstrings dataoff datasize dsym dsyms dysym dysymtab extdef
// cspell:words feedface feedfacf fieldmd fileoff filesize func funcs iextdefsym
// cspell:words ilocalsym indirectsymoff initprot insn insns iundefsym libobjc
// cspell:words linkedit maxprot methname movz ncmds nextdefsym nfat
// cspell:words nindirectsyms nlist nlocalsym nreloc nsects nsyms nundefsym
// cspell:words objc pext reexp reexport reflstr reloff sectname segname
// cspell:words sizeofcmds stab stroff strsize strx symoff symtab typeref uleb
// cspell:words undf unterm vmaddr vmsize zerofill
import 'dart:typed_data';

import 'package:macho/macho.dart';
import 'package:test/test.dart';

void main() {
  group(MachOParser, () {
    const parser = MachOParser();

    group('isMachOBytes', () {
      test(
        'recognizes MH_MAGIC_64, MH_MAGIC, FAT_MAGIC, and FAT_MAGIC_64',
        () {
          expect(MachOParser.isMachOBytes(Uint8List(0)), isFalse);
          expect(
            MachOParser.isMachOBytes(Uint8List.fromList([1, 2, 3])),
            isFalse,
          );

          final mh64 = Uint8List(4);
          ByteData.sublistView(mh64).setUint32(
            0,
            MachOMagic.mhMagic64,
            Endian.little,
          );
          expect(MachOParser.isMachOBytes(mh64), isTrue);

          final mh32 = Uint8List(4);
          ByteData.sublistView(mh32).setUint32(
            0,
            MachOMagic.mhMagic32,
            Endian.little,
          );
          expect(MachOParser.isMachOBytes(mh32), isTrue);

          final fat32 = Uint8List(4);
          ByteData.sublistView(fat32).setUint32(
            0,
            MachOMagic.fatMagic,
          );
          expect(MachOParser.isMachOBytes(fat32), isTrue);

          final fat64 = Uint8List(4);
          ByteData.sublistView(fat64).setUint32(
            0,
            MachOMagic.fatMagic64,
          );
          expect(MachOParser.isMachOBytes(fat64), isTrue);

          final unknown = Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46]);
          expect(MachOParser.isMachOBytes(unknown), isFalse);
        },
      );
    });

    group('thin 64-bit Mach-O parsing', () {
      test('parses segments, sections, symbols, exports, dylibs, ObjC, Swift, '
          'and function starts', () {
        final swiftTypes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final constData = Uint8List.fromList([0xaa, 0xbb, 0xcc, 0xdd]);
        final sigBytes = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);

        final stubBytes = Uint8List(12);
        final bytes = MachOBuilder.buildThin(
          uuid: MachOBuilder.defaultUuid,
          textInstructions: [
            Arm64Encoder.movz(0, 42),
            // Branch to stub at 0x1040 from pc=0x1004 (offset +0x3c = 60).
            Arm64Encoder.bl(0x1040 - 0x1004),
            Arm64Encoder.ret(),
            Arm64Encoder.movz(0, 7),
            Arm64Encoder.ret(),
          ],
          objcClassNames: const ['AppDelegate', 'ViewController'],
          objcSelectors: const ['viewDidLoad', 'initWithFrame:'],
          swiftSections: {'__TEXT,__swift5_types': swiftTypes},
          cstrings: const ['hello_world', 'com.example.channel'],
          constSections: {'__DATA,__const': constData},
          dwarfStrings: const ['/Users/builder/project/ios'],
          extraSections: [
            MachOSectionSpec(
              segname: '__TEXT',
              sectname: '__stubs',
              bytes: stubBytes,
              addr: 0x1040,
              flags: MachOSectionType.symbolStubs,
              reserved2: 12,
            ),
            MachOSectionSpec(
              segname: '__DATA',
              sectname: '__bss',
              bytes: Uint8List(16),
              flags: MachOSectionType.zerofill,
            ),
            MachOSectionSpec(
              segname: '__DWARF',
              sectname: '__debug_line_str',
              bytes: Uint8List.fromList('/Users/builder/line.swift'.codeUnits),
            ),
          ],
          symbols: const [
            MachOSymbolSpec(
              name: '_local_helper',
              nType: MachOSymbolType.nSect,
              nValue: 0x100c,
            ),
            MachOSymbolSpec(
              name: '_main',
            ),
            MachOSymbolSpec.undefined('_objc_msgSend'),
            MachOSymbolSpec.oso('/Users/builder/Runner.o'),
          ],
          indirectSymbols: const [
            2, // _objc_msgSend
            MachOSymbolType.indirectSymbolLocal,
            MachOSymbolType.indirectSymbolAbs,
          ],
          exportedSymbols: const [
            MachOExportedSymbol(name: '_main', flags: 0, offset: 0),
            MachOExportedSymbol(
              name: '_reexported_sym',
              flags: 0x08,
              offset: 0,
              reexportOrdinal: 1,
              importedName: '_orig_sym',
            ),
            MachOExportedSymbol(
              name: '_resolver_sym',
              flags: 0x10,
              offset: 0x0c,
            ),
          ],
          dylibs: const [
            MachODylib(
              name: '/usr/lib/libobjc.A.dylib',
              cmd: MachOLoadCommandType.loadDylib,
              timestamp: 2,
              currentVersion: 0x00010203,
              compatibilityVersion: 0x00010000,
            ),
            MachODylib(
              name: '@rpath/WeakSDK.framework/WeakSDK',
              cmd: MachOLoadCommandType.loadWeakDylib,
              timestamp: 2,
              currentVersion: 0x00020000,
              compatibilityVersion: 0x00010000,
            ),
            MachODylib(
              name: '@rpath/Reexport.framework/Reexport',
              cmd: MachOLoadCommandType.reexportDylib,
              timestamp: 2,
              currentVersion: 0x00010000,
              compatibilityVersion: 0x00010000,
            ),
          ],
          functionStartOffsets: const [0, 0x0c],
          codeSignatureBytes: sigBytes,
        );

        final parsed = parser.parse(bytes);
        expect(parsed.isFat, isFalse);
        expect(parsed.slices, hasLength(1));

        final slice = parsed.slices.single;
        expect(slice.header.cpuType, MachOCpuType.arm64);
        expect(slice.header.fileType, MachOFileType.execute);
        expect(slice.uuid, equals(MachOBuilder.defaultUuid));
        expect(slice.objcClassNames, ['AppDelegate', 'ViewController']);
        expect(slice.objcSelectors, ['viewDidLoad', 'initWithFrame:']);
        expect(
          slice.swiftSections['__TEXT,__swift5_types'],
          equals(swiftTypes),
        );
        expect(slice.cstrings, ['hello_world', 'com.example.channel']);
        expect(slice.constSections['__DATA,__const'], equals(constData));
        expect(
          slice.dwarfCompilePaths,
          containsAll([
            '/Users/builder/Runner.o',
            '/Users/builder/project/ios',
          ]),
        );
        expect(slice.functionStarts, [0x1000, 0x100c]);
        expect(slice.stubTargetNames[0x1040], '_objc_msgSend');
        expect(slice.callsSymbol('_objc_msgSend'), isTrue);
        expect(slice.callsSymbol('_main'), isFalse);

        expect(slice.dylibs, hasLength(3));
        expect(slice.dylibs[0].isWeak, isFalse);
        expect(slice.dylibs[0].isReexport, isFalse);
        expect(
          MachODylib.formatVersion(slice.dylibs[0].currentVersion),
          '1.2.3',
        );
        expect(slice.dylibs[1].isWeak, isTrue);
        expect(slice.dylibs[2].isReexport, isTrue);

        expect(slice.exportedSymbols, hasLength(3));
        final reexp = slice.exportedSymbols.firstWhere(
          (e) => e.name == '_reexported_sym',
        );
        expect(reexp.isReexport, isTrue);
        expect(reexp.reexportOrdinal, 1);
        expect(reexp.importedName, '_orig_sym');

        expect(slice.codeSignature, isNotNull);
        expect(slice.codeSignature!.dataoff, greaterThan(0));
        expect(slice.codeSignature!.datasize, sigBytes.length);
        expect(slice.codeSignature!.bytes, equals(sigBytes));

        const weakRefSym = MachOSymbol(
          name: '_weak_import',
          nType: 0x01,
          nSect: 0,
          nDesc: 0x0040,
          nValue: 0,
        );
        expect(weakRefSym.isWeakRef, isTrue);

        const emptyInsn = MachOCanonicalInstruction(address: 0, tokens: '');
        expect(emptyInsn.exceedsTokens(1), isFalse);

        final dysym = slice.dysymtab!;
        expect(dysym.ilocalsym, 0);
        expect(dysym.nlocalsym, 2);
        expect(dysym.iextdefsym, 2);
        expect(dysym.nextdefsym, 1);
        expect(dysym.iundefsym, 3);
        expect(dysym.nundefsym, 1);
        expect(dysym.indirectsymoff, greaterThan(0));
        expect(dysym.nindirectsyms, 3);

        final textSect = slice.textSection!;
        expect(textSect.offset, greaterThan(0));
        expect(textSect.align, 2);
        expect(textSect.reloff, 0);
        expect(textSect.nreloc, 0);
        expect(textSect.reserved3, 0);

        final textSeg = slice.segments.first;
        expect(textSeg.vmsize, greaterThan(0));
        expect(textSeg.maxprot, 5);
        expect(textSeg.initprot, 5);
        expect(textSeg.flags, 0);

        final firstSym = slice.symbols.first;
        expect(firstSym.nSect, 1);
        expect(firstSym.nDesc, 0);
        expect(firstSym.isWeakRef, isFalse);
      });

      test('parses exports from legacy LC_DYLD_INFO_ONLY command', () {
        final bytes = MachOBuilder.buildThin(
          exportedSymbols: const [
            MachOExportedSymbol(name: '_legacy_export', flags: 0, offset: 0),
            MachOExportedSymbol(
              name: '_same_name_reexport',
              flags: 0x08,
              offset: 0,
              reexportOrdinal: 1,
            ),
          ],
          useLegacyDyldInfo: true,
        );

        final slice = parser.parse(bytes).slices.single;
        expect(
          slice.exportedSymbols.map((e) => e.name),
          containsAll(['_legacy_export', '_same_name_reexport']),
        );
      });
    });

    group('Universal (fat) Mach-O parsing', () {
      test('parses 32-bit fat Mach-O (0xcafebabe) and sorts slices', () {
        final x86Slice = MachOBuilder.buildThin(
          cpuType: MachOCpuType.x86_64,
          textInstructions: [0x90909090],
        );
        final armSliceSub1 = MachOBuilder.buildThin(
          cpuSubtype: 1,
          textInstructions: [Arm64Encoder.ret()],
        );
        final armSliceSub0 = MachOBuilder.buildThin(
          textInstructions: [Arm64Encoder.ret()],
        );

        final fatBytes = MachOBuilder.buildFat([
          armSliceSub1,
          armSliceSub0,
          x86Slice,
        ]);
        final parsed = parser.parse(fatBytes);

        expect(parsed.isFat, isTrue);
        expect(parsed.slices, hasLength(3));
        expect(parsed.slices[0].header.cpuType, MachOCpuType.x86_64);
        expect(parsed.slices[1].header.cpuType, MachOCpuType.arm64);
        expect(parsed.slices[1].header.cpuSubtype, 0);
        expect(parsed.slices[2].header.cpuSubtype, 1);
      });

      test('parses 64-bit fat Mach-O (0xcafebabf)', () {
        final armSlice = MachOBuilder.buildThin(
          textInstructions: [Arm64Encoder.ret()],
        );
        final fat64Bytes = MachOBuilder.buildFat(
          [armSlice],
          is64BitFat: true,
        );
        final parsed = parser.parse(fat64Bytes);

        expect(parsed.isFat, isTrue);
        expect(parsed.slices, hasLength(1));
        expect(parsed.slices.single.header.cpuType, MachOCpuType.arm64);
      });
    });

    group('companion .dSYM resolution and instruction canonicalization', () {
      test('resolves stripped function names via companion dSYM and '
          'canonicalizes b, bl, and adrp instructions', () {
        // Stripped binary: no symbols in LC_SYMTAB, only LC_FUNCTION_STARTS
        // and __TEXT,__cstring at 0x2000.
        final binaryBytes = MachOBuilder.buildThin(
          cstrings: const ['greeting'],
          cstringVmaddr: 0x2000,
          textInstructions: [
            // 0x1000: func 0 (_first_func in dSYM)
            // ADRP x0, +1 page (0x2000) + ADD x0, x0, #0 -> resolves S:greeting
            Arm64Encoder.adrp(0, 1),
            Arm64Encoder.addImm(0, 0, 0),
            // Intra-function branch to +0xc (0x100c) from pc=0x1008 (+4)
            Arm64Encoder.b(4),
            Arm64Encoder.ret(),
            // 0x1010: func 1 (_second_func in dSYM)
            // Branch to func 0 at 0x1000 from pc=0x1010 (-16)
            Arm64Encoder.bl(-16),
            // ADRP xzr, +1 page without following ADD -> section-relative page
            Arm64Encoder.adrp(31, 1),
            // ADRP x1, -1 page -> page 0x0 (in __TEXT)
            Arm64Encoder.adrp(1, -1),
            // ADRP x2, +100 pages -> unmapped page
            Arm64Encoder.adrp(2, 100),
            // Branch to unmapped address 0x1800 from pc=0x1020
            Arm64Encoder.b(0x1800 - 0x1020),
          ],
          functionStartOffsets: const [0, 0x10],
        );

        final dsymBytes = MachOBuilder.buildDsym(
          textSize: 0x24,
          symbols: const [
            MachOSymbolSpec(name: '_first_func'),
            MachOSymbolSpec(name: '_second_func', nValue: 0x1010),
          ],
        );

        final binSlice = parser.parse(binaryBytes).slices.single;
        final dsymSlice = parser.parse(dsymBytes).slices.single;

        // Without dSYM, functions are named sub_0 and sub_1.
        final strippedFuncs = binSlice.resolveFunctions();
        expect(strippedFuncs.map((f) => f.name), ['sub_0', 'sub_1']);
        expect(strippedFuncs[0].isAnonymous, isTrue);

        // With dSYM, functions are named _first_func and _second_func.
        final resolvedFuncs = binSlice.resolveFunctions(dsymSlice: dsymSlice);
        expect(
          resolvedFuncs.map((f) => f.name),
          ['_first_func', '_second_func'],
        );
        expect(resolvedFuncs[0].isAnonymous, isFalse);
        expect(resolvedFuncs[0].tokensAt(0), 'adrp,x0,S:greeting,');
        expect(resolvedFuncs[0].tokensAt(2), 'b,+0xc,');
        expect(resolvedFuncs[1].tokensAt(0), 'bl,_first_func,');
        expect(resolvedFuncs[1].tokensAt(1), 'adrp,xzr,__TEXT,__cstring+0x0,');
        expect(resolvedFuncs[1].tokensAt(2), 'adrp,x1,page(0x0),');
        expect(resolvedFuncs[1].tokensAt(3), 'adrp,x2,page(0x65000),');
        expect(resolvedFuncs[1].tokensAt(4), 'b,0x1800,');
      });

      test('handles non-ARM64 or unaligned text bytes', () {
        final slice = MachOSlice(
          header: const MachOHeader(
            cpuType: MachOCpuType.x86_64,
            cpuSubtype: 3,
            fileType: MachOFileType.execute,
            ncmds: 0,
            sizeofcmds: 0,
            flags: 0,
          ),
          uuid: null,
          segments: const [],
          sections: [
            MachOSection(
              segname: '__TEXT',
              sectname: '__text',
              addr: 0x1000,
              size: 5,
              offset: 0,
              align: 0,
              reloff: 0,
              nreloc: 0,
              flags: 0,
              reserved1: 0,
              reserved2: 0,
              reserved3: 0,
              bytes: Uint8List.fromList([0x55, 0x48, 0x89, 0xe5, 0xc3]),
            ),
          ],
          symbols: const [],
          dysymtab: null,
          exportedSymbols: const [],
          dylibs: const [],
          functionStarts: const [],
          codeSignature: null,
          linkeditPaddingBytes: Uint8List(0),
          objcClassNames: const [],
          objcSelectors: const [],
          swiftSections: const {},
          cstrings: const [],
          constSections: const {},
          dwarfCompilePaths: const [],
          stubTargetNames: const {},
          referencedSymbols: const {},
        );

        final funcs = slice.resolveFunctions();
        expect(funcs, hasLength(1));
        expect(funcs.single.name, '__TEXT,__text');
        expect(funcs.single.instructionCount, 2);
        expect(funcs.single.tokensAt(0), 'word,0xe5894855,');
        expect(funcs.single.tokensAt(1), 'byte,0xc3,');
      });
    });

    group('corruption and truncation handling', () {
      test('throws MachOFormatException on empty or tiny input', () {
        expect(
          () => parser.parse(Uint8List(0)),
          throwsA(isA<MachOFormatException>()),
        );
        expect(
          () => parser.parse(Uint8List(3)),
          throwsA(isA<MachOFormatException>()),
        );
      });

      test('throws MachOFormatException on unrecognized magic', () {
        expect(
          () => parser.parse(Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46])),
          throwsA(isA<MachOFormatException>()),
        );
      });

      test('throws MachOFormatException on truncated thin header', () {
        final bytes = Uint8List(16);
        ByteData.sublistView(bytes).setUint32(
          0,
          MachOMagic.mhMagic64,
          Endian.little,
        );
        expect(
          () => parser.parse(bytes),
          throwsA(isA<MachOFormatException>()),
        );
      });

      test('throws MachOFormatException when sizeofcmds exceeds file size', () {
        final bytes = MachOBuilder.buildThin();
        ByteData.sublistView(bytes).setUint32(20, 999999, Endian.little);
        expect(
          () => parser.parse(bytes),
          throwsA(isA<MachOFormatException>()),
        );
      });

      test(
        'throws MachOFormatException on truncated or invalid load command',
        () {
          final bytes = MachOBuilder.buildThin();
          // Set first load command cmdsize to 4 (< 8).
          ByteData.sublistView(bytes).setUint32(36, 4, Endian.little);
          expect(
            () => parser.parse(bytes),
            throwsA(isA<MachOFormatException>()),
          );
        },
      );

      test(
        'throws MachOFormatException on out-of-bounds segment or section',
        () {
          final bytes = MachOBuilder.buildThin();
          // Set __TEXT filesize (at offset 32 + 48 = 80) past end of file.
          ByteData.sublistView(bytes).setUint64(80, 999999, Endian.little);
          expect(
            () => parser.parse(bytes),
            throwsA(isA<MachOFormatException>()),
          );

          final bytes2 = MachOBuilder.buildThin();
          // Set __TEXT,__text section size (at 32 + 72 + 40 = 144) past EOF.
          ByteData.sublistView(bytes2).setUint64(144, 999999, Endian.little);
          expect(
            () => parser.parse(bytes2),
            throwsA(isA<MachOFormatException>()),
          );
        },
      );

      test('throws MachOFormatException on out-of-bounds symtab or strx', () {
        final bytes = MachOBuilder.buildThin(
          symbols: const [MachOSymbolSpec(name: '_main')],
        );
        final data = ByteData.sublistView(bytes);
        // Find LC_SYMTAB and corrupt n_strx or symoff.
        var off = 32;
        final ncmds = data.getUint32(16, Endian.little);
        for (var i = 0; i < ncmds; i++) {
          final cmd = data.getUint32(off, Endian.little);
          final cmdsize = data.getUint32(off + 4, Endian.little);
          if (cmd == MachOLoadCommandType.symtab) {
            final symoff = data.getUint32(off + 8, Endian.little);
            // Set symbol[0].n_strx out of bounds.
            data.setUint32(symoff, 999999, Endian.little);
            break;
          }
          off += cmdsize;
        }
        expect(
          () => parser.parse(bytes),
          throwsA(isA<MachOFormatException>()),
        );
      });

      test(
        'throws MachOFormatException on cyclic or out-of-bounds export trie',
        () {
          final bytes = MachOBuilder.buildThin(
            exportedSymbols: const [
              MachOExportedSymbol(name: '_foo', flags: 0, offset: 0),
            ],
          );
          final data = ByteData.sublistView(bytes);
          var off = 32;
          final ncmds = data.getUint32(16, Endian.little);
          for (var i = 0; i < ncmds; i++) {
            final cmd = data.getUint32(off, Endian.little);
            final cmdsize = data.getUint32(off + 4, Endian.little);
            if (cmd == MachOLoadCommandType.dyldExportsTrie) {
              final trieOff = data.getUint32(off + 8, Endian.little);
              // Root has 0 terminalSize, 1 child "_foo\0", then child offset.
              // Set child offset to 0 (cycle back to root!).
              bytes[trieOff + 2 + 5] = 0;
              break;
            }
            off += cmdsize;
          }
          expect(
            () => parser.parse(bytes),
            throwsA(isA<MachOFormatException>()),
          );
        },
      );

      test('throws MachOFormatException on corrupted fat headers', () {
        // Truncated fat header (< 8 bytes).
        final tinyFat = Uint8List(6);
        ByteData.sublistView(tinyFat).setUint32(
          0,
          MachOMagic.fatMagic,
        );
        expect(
          () => parser.parse(tinyFat),
          throwsA(isA<MachOFormatException>()),
        );

        // nfat_arch == 0.
        final zeroFat = Uint8List(8);
        ByteData.sublistView(zeroFat).setUint32(
          0,
          MachOMagic.fatMagic,
        );
        expect(
          () => parser.parse(zeroFat),
          throwsA(isA<MachOFormatException>()),
        );

        // fat_arch table truncated.
        final truncTable = Uint8List(12);
        ByteData.sublistView(truncTable)
          ..setUint32(0, MachOMagic.fatMagic)
          ..setUint32(4, 2);
        expect(
          () => parser.parse(truncTable),
          throwsA(isA<MachOFormatException>()),
        );

        // fat_arch slice out of bounds.
        final armSlice = MachOBuilder.buildThin();
        final badSliceOff = MachOBuilder.buildFat([armSlice]);
        ByteData.sublistView(badSliceOff).setUint32(16, 999999);
        expect(
          () => parser.parse(badSliceOff),
          throwsA(isA<MachOFormatException>()),
        );

        // fat_arch CPU type mismatch with slice header.
        final mismatchCpu = MachOBuilder.buildFat([armSlice]);
        ByteData.sublistView(mismatchCpu).setUint32(
          8,
          MachOCpuType.x86_64,
        );
        expect(
          () => parser.parse(mismatchCpu),
          throwsA(isA<MachOFormatException>()),
        );

        // Slice inside fat binary has invalid magic.
        final badSliceMagic = MachOBuilder.buildFat([armSlice]);
        final sliceStart = ByteData.sublistView(badSliceMagic).getUint32(16);
        ByteData.sublistView(badSliceMagic).setUint32(
          sliceStart,
          0x12345678,
          Endian.little,
        );
        expect(
          () => parser.parse(badSliceMagic),
          throwsA(isA<MachOFormatException>()),
        );
      });

      test('throws MachOFormatException on malformed load commands, '
          'excessive counts, and ULEB128 overflow', () {
        // Load command header truncated by sizeofcmds.
        final truncCmdHdr = MachOBuilder.buildThin();
        ByteData.sublistView(truncCmdHdr).setUint32(20, 4, Endian.little);
        expect(
          () => parser.parse(truncCmdHdr),
          throwsA(isA<MachOFormatException>()),
        );

        // Segment nsects requires more bytes than cmdsize.
        final badNsects = MachOBuilder.buildThin();
        ByteData.sublistView(badNsects).setUint32(32 + 64, 99, Endian.little);
        expect(
          () => parser.parse(badNsects),
          throwsA(isA<MachOFormatException>()),
        );

        // Excessive nsyms in LC_SYMTAB and nindirectsyms in LC_DYSYMTAB.
        final symBin = MachOBuilder.buildThin(
          symbols: const [MachOSymbolSpec(name: '_main')],
        );
        final symData = ByteData.sublistView(symBin);
        var off = 32;
        final ncmds = symData.getUint32(16, Endian.little);
        var symCmdOff = 0;
        var dysymCmdOff = 0;
        for (var i = 0; i < ncmds; i++) {
          final cmd = symData.getUint32(off, Endian.little);
          final cmdsize = symData.getUint32(off + 4, Endian.little);
          if (cmd == MachOLoadCommandType.symtab) symCmdOff = off;
          if (cmd == MachOLoadCommandType.dysymtab) dysymCmdOff = off;
          off += cmdsize;
        }
        final hugeSymBin = Uint8List.fromList(symBin);
        ByteData.sublistView(hugeSymBin).setUint32(
          symCmdOff + 12,
          2000000,
          Endian.little,
        );
        expect(
          () => parser.parse(hugeSymBin),
          throwsA(isA<MachOFormatException>()),
        );

        final hugeDysymBin = Uint8List.fromList(symBin);
        ByteData.sublistView(hugeDysymBin).setUint32(
          dysymCmdOff + 60,
          2000000,
          Endian.little,
        );
        expect(
          () => parser.parse(hugeDysymBin),
          throwsA(isA<MachOFormatException>()),
        );

        // Export trie out-of-bounds child offset, unterminated edge string,
        // and >64-bit ULEB128 overflow.
        final trieBin = MachOBuilder.buildThin(
          exportedSymbols: const [
            MachOExportedSymbol(name: '_foo', flags: 0, offset: 0),
          ],
        );
        final trieData = ByteData.sublistView(trieBin);
        var trieCmdOff = 0;
        off = 32;
        for (var i = 0; i < trieData.getUint32(16, Endian.little); i++) {
          final cmd = trieData.getUint32(off, Endian.little);
          final cmdsize = trieData.getUint32(off + 4, Endian.little);
          if (cmd == MachOLoadCommandType.dyldExportsTrie) trieCmdOff = off;
          off += cmdsize;
        }
        final trieOff = trieData.getUint32(trieCmdOff + 8, Endian.little);
        final trieSize = trieData.getUint32(trieCmdOff + 12, Endian.little);

        // Out-of-bounds child offset.
        final oobChild = Uint8List.fromList(trieBin);
        oobChild[trieOff + 2 + 5] = 0x7f;
        expect(
          () => parser.parse(oobChild),
          throwsA(isA<MachOFormatException>()),
        );

        // Unterminated edge string (fill trie with non-zero bytes after child
        // count).
        final untermEdge = Uint8List.fromList(trieBin);
        for (var i = trieOff + 2; i < trieOff + trieSize; i++) {
          untermEdge[i] = 0x41;
        }
        expect(
          () => parser.parse(untermEdge),
          throwsA(isA<MachOFormatException>()),
        );

        // ULEB128 > 64-bit overflow (10 continuation bytes with 0x80 set).
        final ulebOverflow = Uint8List.fromList(trieBin);
        for (var i = 0; i < 11 && trieOff + i < trieOff + trieSize; i++) {
          ulebOverflow[trieOff + i] = 0x81;
        }
        expect(
          () => parser.parse(ulebOverflow),
          throwsA(isA<MachOFormatException>()),
        );

        // dylib_command nameOffset out of bounds.
        final dylibBin = MachOBuilder.buildThin(
          dylibs: const [
            MachODylib(
              name: '/usr/lib/libSystem.B.dylib',
              cmd: MachOLoadCommandType.loadDylib,
              timestamp: 2,
              currentVersion: 1,
              compatibilityVersion: 1,
            ),
          ],
        );
        final dylibData = ByteData.sublistView(dylibBin);
        off = 32;
        for (var i = 0; i < dylibData.getUint32(16, Endian.little); i++) {
          final cmd = dylibData.getUint32(off, Endian.little);
          final cmdsize = dylibData.getUint32(off + 4, Endian.little);
          if (cmd == MachOLoadCommandType.loadDylib) {
            dylibData.setUint32(off + 8, 9999, Endian.little);
            break;
          }
          off += cmdsize;
        }
        expect(
          () => parser.parse(dylibBin),
          throwsA(isA<MachOFormatException>()),
        );

        // Non-null-terminated trailing string in __TEXT,__cstring and N_SO /
        // N_SOL stabs.
        final untermCstr = MachOBuilder.buildThin(
          extraSections: [
            MachOSectionSpec(
              segname: '__TEXT',
              sectname: '__cstring',
              bytes: Uint8List.fromList([0x61, 0x62, 0x63]),
            ),
          ],
          symbols: const [
            MachOSymbolSpec(
              name: '/src/main.c',
              nType: MachOSymbolType.nSo,
              nSect: 0,
              nValue: 0,
            ),
            MachOSymbolSpec(
              name: '/src/header.h',
              nType: MachOSymbolType.nSol,
              nSect: 0,
              nValue: 0,
            ),
          ],
        );
        final untermSlice = parser.parse(untermCstr).slices.single;
        expect(untermSlice.cstrings, ['abc']);
        expect(
          untermSlice.dwarfCompilePaths,
          containsAll(['/src/main.c', '/src/header.h']),
        );
      });
    });
  });
}
