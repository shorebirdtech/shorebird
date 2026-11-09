// cspell:words adrp cafebabe cafebabf chkstk cputype cpusubtype cstring
// cspell:words cstrings dataoff datasize dsym dsyms dysymtab extdef feedfacf
// cspell:words fieldmd fileoff filesize func iextdefsym ilocalsym immhi immlo
// cspell:words indirectsymoff initprot insn insns iundefsym linkedit maxprot
// cspell:words methname movz ncmds nextdef nextdefsym nfat nindirectsyms nlist
// cspell:words nlocal nlocalsym nreloc nsects nsyms nundef nundefsym objc pext
// cspell:words reexport reflstr reloff sectname segname sizeofcmds stab stroff
// cspell:words strsize strx symoff symtab typeref uleb undf vmaddr vmsize
import 'dart:convert';
import 'dart:typed_data';

import 'package:macho/src/macho_parser.dart';

/// Pure-Dart ARM64 (AArch64) instruction encoder for constructing synthetic
/// `__TEXT,__text` function bodies in tests.
abstract final class Arm64Encoder {
  /// Encodes `NOP` (`0xd503201f`).
  static int nop() => 0xd503201f;

  /// Encodes `RET` (`0xd65f03c0`).
  static int ret() => 0xd65f03c0;

  /// Encodes `MOVZ x<rd>, #<imm16>` (`0xd2800000 | (imm16 << 5) | rd`).
  static int movz(int rd, int imm16) =>
      0xd2800000 | ((imm16 & 0xffff) << 5) | (rd & 0x1f);

  /// Encodes unconditional `B <offsetBytes>` (`0x14000000 | imm26`).
  static int b(int offsetBytes) {
    final imm26 = (offsetBytes ~/ 4) & 0x03ffffff;
    return 0x14000000 | imm26;
  }

  /// Encodes `BL <offsetBytes>` (`0x94000000 | imm26`).
  static int bl(int offsetBytes) {
    final imm26 = (offsetBytes ~/ 4) & 0x03ffffff;
    return 0x94000000 | imm26;
  }

  /// Encodes `ADRP x<rd>, <pageDelta>` (`0x90000000 | immlo | immhi | rd`).
  static int adrp(int rd, int pageDelta) {
    final imm21 = pageDelta & 0x1fffff;
    final immlo = imm21 & 0x3;
    final immhi = (imm21 >>> 2) & 0x7ffff;
    return 0x90000000 | (immlo << 29) | (immhi << 5) | (rd & 0x1f);
  }

  /// Encodes `ADD x<rd>, x<rn>, #<imm12>` (`0x91000000 | ...`).
  static int addImm(int rd, int rn, int imm12, {bool shift12 = false}) {
    final sh = shift12 ? 1 : 0;
    return 0x91000000 |
        (sh << 22) |
        ((imm12 & 0xfff) << 10) |
        ((rn & 0x1f) << 5) |
        (rd & 0x1f);
  }

  /// Packs a list of 32-bit ARM64 instruction words into little-endian bytes.
  static Uint8List encodeInstructions(List<int> instructions) {
    final bytes = Uint8List(instructions.length * 4);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < instructions.length; i++) {
      data.setUint32(i * 4, instructions[i], Endian.little);
    }
    return bytes;
  }
}

/// Specification for a symbol when building a synthetic Mach-O binary via
/// [MachOBuilder].
class MachOSymbolSpec {
  /// Creates a [MachOSymbolSpec].
  const MachOSymbolSpec({
    required this.name,
    this.nType = 0x0f, // N_SECT | N_EXT
    this.nSect = 1,
    this.nDesc = 0,
    this.nValue = 0x1000,
  });

  /// Creates an undefined external symbol (`N_UNDF | N_EXT`).
  const MachOSymbolSpec.undefined(
    this.name, {
    this.nDesc = 0,
  }) : nType = MachOSymbolType.nExt,
       nSect = 0,
       nValue = 0;

  /// Creates an `N_OSO` debug stab symbol recording an object file build path.
  const MachOSymbolSpec.oso(this.name)
    : nType = MachOSymbolType.nOso,
      nSect = 0,
      nDesc = 1,
      nValue = 0;

  /// Symbol name.
  final String name;

  /// `n_type` byte.
  final int nType;

  /// 1-based section index (`n_sect`).
  final int nSect;

  /// `n_desc` flags.
  final int nDesc;

  /// `n_value` address.
  final int nValue;
}

/// Specification for a section when building a synthetic Mach-O binary via
/// [MachOBuilder].
class MachOSectionSpec {
  /// Creates a [MachOSectionSpec].
  const MachOSectionSpec({
    required this.segname,
    required this.sectname,
    required this.bytes,
    this.addr = 0,
    this.flags = MachOSectionType.regular,
    this.reserved1 = 0,
    this.reserved2 = 0,
    this.unbacked = false,
  });

  /// Segment name (e.g. `__TEXT`).
  final String segname;

  /// Section name (e.g. `__text`).
  final String sectname;

  /// Payload bytes (or virtual size placeholder when [unbacked] is true).
  final Uint8List bytes;

  /// Optional explicit virtual address (auto-assigned if `0`).
  final int addr;

  /// Section flags.
  final int flags;

  /// Reserved1 (`indirectsymoff` start index for symbol stubs).
  final int reserved1;

  /// Reserved2 (stub byte size for `S_SYMBOL_STUBS`).
  final int reserved2;

  /// Whether the section has `offset = 0` and no file payload (as in `.dSYM`
  /// `__TEXT,__text` sections).
  final bool unbacked;
}

/// {@template macho_builder}
/// Pure-Dart in-memory synthesizer for thin 64-bit Mach-O, Universal (fat)
/// Mach-O (`0xcafebabe` / `0xcafebabf`), and companion `.dSYM` binaries.
/// {@endtemplate}
abstract final class MachOBuilder {
  /// Default 16-byte UUID (`01020304-0506-0708-090a-0b0c0d0e0f10`).
  static final Uint8List defaultUuid = Uint8List.fromList(
    List<int>.generate(16, (i) => i + 1),
  );

  /// Alternate 16-byte UUID (`f1f2f3f4-f5f6-f7f8-f9fa-fbfcfdfeff00`).
  static final Uint8List alternateUuid = Uint8List.fromList(
    List<int>.generate(16, (i) => 0xf1 + i),
  );

  /// Synthesizes a valid 64-bit thin Mach-O binary in memory.
  static Uint8List buildThin({
    int cpuType = MachOCpuType.arm64,
    int cpuSubtype = 0,
    int fileType = MachOFileType.execute,
    int flags = 0x00200085,
    Uint8List? uuid,
    bool includeUuid = true,
    List<int>? textInstructions,
    int textVmaddr = 0x1000,
    List<String> objcClassNames = const [],
    List<String> objcSelectors = const [],
    Map<String, Uint8List> swiftSections = const {},
    List<String> cstrings = const [],
    int? cstringVmaddr,
    Map<String, Uint8List> constSections = const {},
    List<MachOSectionSpec> extraSections = const [],
    List<String> dwarfStrings = const [],
    List<MachOSymbolSpec> symbols = const [],
    List<int> indirectSymbols = const [],
    List<MachOExportedSymbol> exportedSymbols = const [],
    bool useLegacyDyldInfo = false,
    List<MachODylib> dylibs = const [],
    List<int> functionStartOffsets = const [],
    Uint8List? codeSignatureBytes,
    Uint8List? linkeditTrailingPadding,
  }) {
    final effectiveUuid = includeUuid ? (uuid ?? defaultUuid) : null;
    final textBytes = Arm64Encoder.encodeInstructions(
      textInstructions ?? [Arm64Encoder.movz(0, 0), Arm64Encoder.ret()],
    );

    // Collect sections grouped by segment.
    final textSects = <MachOSectionSpec>[
      if (textBytes.isNotEmpty)
        MachOSectionSpec(
          segname: '__TEXT',
          sectname: '__text',
          bytes: textBytes,
          addr: textVmaddr,
          flags: 0x80000400,
        ),
      if (objcClassNames.isNotEmpty)
        MachOSectionSpec(
          segname: '__TEXT',
          sectname: '__objc_classname',
          bytes: _packNullTerminatedStrings(objcClassNames),
          flags: MachOSectionType.cstringLiterals,
        ),
      if (objcSelectors.isNotEmpty)
        MachOSectionSpec(
          segname: '__TEXT',
          sectname: '__objc_methname',
          bytes: _packNullTerminatedStrings(objcSelectors),
          flags: MachOSectionType.cstringLiterals,
        ),
      if (cstrings.isNotEmpty)
        MachOSectionSpec(
          segname: '__TEXT',
          sectname: '__cstring',
          bytes: _packNullTerminatedStrings(cstrings),
          addr: cstringVmaddr ?? 0,
          flags: MachOSectionType.cstringLiterals,
        ),
      for (final entry in swiftSections.entries)
        MachOSectionSpec(
          segname: entry.key.split(',').first,
          sectname: entry.key.split(',').last,
          bytes: entry.value,
        ),
    ];

    final dataSects = <MachOSectionSpec>[
      for (final entry in constSections.entries)
        MachOSectionSpec(
          segname: entry.key.split(',').first,
          sectname: entry.key.split(',').last,
          bytes: entry.value,
        ),
    ];

    final dwarfSects = <MachOSectionSpec>[
      if (dwarfStrings.isNotEmpty)
        MachOSectionSpec(
          segname: '__DWARF',
          sectname: '__debug_str',
          bytes: _packNullTerminatedStrings(dwarfStrings),
        ),
    ];

    for (final s in extraSections) {
      if (s.segname == '__TEXT') {
        textSects.add(s);
      } else if (s.segname == '__DWARF') {
        dwarfSects.add(s);
      } else {
        dataSects.add(s);
      }
    }

    // Encode __LINKEDIT tables before computing load command offsets.
    final (symtabBytes, strtabBytes) = _encodeSymtab(symbols);
    final indirectBytes = _encodeIndirectSymbols(indirectSymbols);
    final exportTrieBytes = exportedSymbols.isNotEmpty
        ? _encodeExportTrie(exportedSymbols)
        : Uint8List(0);
    final funcStartsBytes = functionStartOffsets.isNotEmpty
        ? _encodeFunctionStarts(functionStartOffsets, textVmaddr)
        : Uint8List(0);

    // Pre-calculate load commands size.
    var ncmds = 0;
    var sizeofcmds = 0;

    // 1. __TEXT segment (always included so __TEXT.vmaddr is well-defined).
    ncmds++;
    sizeofcmds += 72 + textSects.length * 80;

    // 2. __DATA segment (if any data sections exist).
    if (dataSects.isNotEmpty) {
      ncmds++;
      sizeofcmds += 72 + dataSects.length * 80;
    }

    // 3. __DWARF segment (if any dwarf sections exist).
    if (dwarfSects.isNotEmpty) {
      ncmds++;
      sizeofcmds += 72 + dwarfSects.length * 80;
    }

    // 4. __LINKEDIT segment.
    final hasLinkedit =
        symbols.isNotEmpty ||
        indirectSymbols.isNotEmpty ||
        exportedSymbols.isNotEmpty ||
        functionStartOffsets.isNotEmpty ||
        codeSignatureBytes != null ||
        linkeditTrailingPadding != null;
    if (hasLinkedit) {
      ncmds++;
      sizeofcmds += 72;
    }

    // 5. LC_UUID.
    if (effectiveUuid != null) {
      ncmds++;
      sizeofcmds += 24;
    }

    // 6. LC_SYMTAB.
    if (symbols.isNotEmpty) {
      ncmds++;
      sizeofcmds += 24;
    }

    // 7. LC_DYSYMTAB.
    if (indirectSymbols.isNotEmpty || symbols.isNotEmpty) {
      ncmds++;
      sizeofcmds += 80;
    }

    // 8. LC_DYLD_EXPORTS_TRIE or LC_DYLD_INFO.
    if (exportedSymbols.isNotEmpty) {
      ncmds++;
      sizeofcmds += useLegacyDyldInfo ? 48 : 16;
    }

    // 9. LC_FUNCTION_STARTS.
    if (functionStartOffsets.isNotEmpty) {
      ncmds++;
      sizeofcmds += 16;
    }

    // 10. Dylibs.
    final encodedDylibCmds = <Uint8List>[];
    for (final dylib in dylibs) {
      final cmdBytes = _encodeDylibCommand(dylib);
      encodedDylibCmds.add(cmdBytes);
      ncmds++;
      sizeofcmds += cmdBytes.length;
    }

    // 11. LC_CODE_SIGNATURE.
    if (codeSignatureBytes != null) {
      ncmds++;
      sizeofcmds += 16;
    }

    // Layout section payloads starting after header + load commands, aligned to
    // 16 bytes, or at 0x1000 so fileoff matches vmaddr when textVmaddr >=
    // headerEnd.
    final headerAndCmdsEnd = _alignUp(32 + sizeofcmds, 16);
    var fileCursor = textVmaddr >= headerAndCmdsEnd
        ? textVmaddr
        : headerAndCmdsEnd;
    var vmCursor = textVmaddr;

    final resolvedTextSects = <_ResolvedSection>[];
    for (final spec in textSects) {
      fileCursor = _alignUp(fileCursor, 8);
      final sectVmaddr = spec.addr != 0 ? spec.addr : vmCursor;
      final sectFileOff = spec.unbacked ? 0 : fileCursor;
      resolvedTextSects.add(
        _ResolvedSection(
          spec: spec,
          addr: sectVmaddr,
          fileOff: sectFileOff,
        ),
      );
      if (!spec.unbacked) {
        fileCursor += spec.bytes.length;
      }
      final nextVm = sectVmaddr + spec.bytes.length;
      if (nextVm > vmCursor) {
        vmCursor = _alignUp(nextVm, 8);
      }
    }

    final textSegFileOff = resolvedTextSects.every((s) => s.spec.unbacked)
        ? 0
        : 0;
    final textSegFileSize = resolvedTextSects.every((s) => s.spec.unbacked)
        ? 0
        : fileCursor;
    final textSegVmSize = _alignUp(
      (vmCursor - textVmaddr).clamp(0x1000, 0x7fffffff),
      0x1000,
    );

    fileCursor = _alignUp(fileCursor, 16);
    vmCursor = _alignUp(textVmaddr + textSegVmSize, 0x1000);
    final dataSegVmaddr = vmCursor;
    final dataSegFileOff = fileCursor;

    final resolvedDataSects = <_ResolvedSection>[];
    for (final spec in dataSects) {
      fileCursor = _alignUp(fileCursor, 8);
      final sectVmaddr = spec.addr != 0 ? spec.addr : vmCursor;
      final sectFileOff = spec.unbacked ? 0 : fileCursor;
      resolvedDataSects.add(
        _ResolvedSection(
          spec: spec,
          addr: sectVmaddr,
          fileOff: sectFileOff,
        ),
      );
      if (!spec.unbacked) {
        fileCursor += spec.bytes.length;
      }
      final nextVm = sectVmaddr + spec.bytes.length;
      if (nextVm > vmCursor) {
        vmCursor = _alignUp(nextVm, 8);
      }
    }
    final dataSegFileSize = fileCursor - dataSegFileOff;
    final dataSegVmSize = _alignUp(
      (vmCursor - dataSegVmaddr).clamp(0x1000, 0x7fffffff),
      0x1000,
    );

    fileCursor = _alignUp(fileCursor, 16);
    vmCursor = _alignUp(vmCursor + 0x1000, 0x1000);
    final dwarfSegVmaddr = vmCursor;
    final dwarfSegFileOff = fileCursor;

    final resolvedDwarfSects = <_ResolvedSection>[];
    for (final spec in dwarfSects) {
      fileCursor = _alignUp(fileCursor, 8);
      final sectVmaddr = spec.addr != 0 ? spec.addr : vmCursor;
      resolvedDwarfSects.add(
        _ResolvedSection(
          spec: spec,
          addr: sectVmaddr,
          fileOff: fileCursor,
        ),
      );
      fileCursor += spec.bytes.length;
      vmCursor = _alignUp(sectVmaddr + spec.bytes.length, 8);
    }
    final dwarfSegFileSize = fileCursor - dwarfSegFileOff;
    final dwarfSegVmSize = _alignUp(
      (vmCursor - dwarfSegVmaddr).clamp(0x1000, 0x7fffffff),
      0x1000,
    );

    // Layout __LINKEDIT tables.
    fileCursor = _alignUp(fileCursor, 16);
    final linkeditFileOff = fileCursor;
    final linkeditVmaddr = _alignUp(vmCursor + 0x1000, 0x1000);

    final exportTrieOff = fileCursor;
    fileCursor += exportTrieBytes.length;

    final funcStartsOff = fileCursor;
    fileCursor += funcStartsBytes.length;

    fileCursor = _alignUp(fileCursor, 8);
    final symoff = fileCursor;
    fileCursor += symtabBytes.length;

    final indirectsymoff = fileCursor;
    fileCursor += indirectBytes.length;

    final stroff = fileCursor;
    fileCursor += strtabBytes.length;

    if (linkeditTrailingPadding != null && linkeditTrailingPadding.isNotEmpty) {
      fileCursor += linkeditTrailingPadding.length;
    }

    final codeSigOff = fileCursor;
    if (codeSignatureBytes != null) {
      fileCursor += codeSignatureBytes.length;
    }

    final linkeditFileSize = fileCursor - linkeditFileOff;
    final linkeditVmSize = _alignUp(
      linkeditFileSize.clamp(0x1000, 0x7fffffff),
      0x1000,
    );

    final totalSize = fileCursor;
    final out = Uint8List(totalSize);
    final data = ByteData.sublistView(out)
      // Write mach_header_64 (32 bytes).
      ..setUint32(0, MachOMagic.mhMagic64, Endian.little)
      ..setUint32(4, cpuType, Endian.little)
      ..setUint32(8, cpuSubtype, Endian.little)
      ..setUint32(12, fileType, Endian.little)
      ..setUint32(16, ncmds, Endian.little)
      ..setUint32(20, sizeofcmds, Endian.little)
      ..setUint32(24, flags, Endian.little)
      ..setUint32(28, 0, Endian.little);

    var cmdCursor = 32;

    // Write __TEXT segment command (starts at vmaddr 0 covering the header).
    cmdCursor = _writeSegment64Command(
      out: out,
      data: data,
      offset: cmdCursor,
      segname: '__TEXT',
      vmaddr: 0,
      vmsize: textVmaddr + textSegVmSize,
      fileoff: textSegFileOff,
      filesize: textSegFileSize,
      maxprot: 5,
      initprot: 5,
      sections: resolvedTextSects,
    );

    // Write __DATA segment command.
    if (resolvedDataSects.isNotEmpty) {
      cmdCursor = _writeSegment64Command(
        out: out,
        data: data,
        offset: cmdCursor,
        segname: '__DATA',
        vmaddr: dataSegVmaddr,
        vmsize: dataSegVmSize,
        fileoff: dataSegFileOff,
        filesize: dataSegFileSize,
        maxprot: 3,
        initprot: 3,
        sections: resolvedDataSects,
      );
    }

    // Write __DWARF segment command.
    if (resolvedDwarfSects.isNotEmpty) {
      cmdCursor = _writeSegment64Command(
        out: out,
        data: data,
        offset: cmdCursor,
        segname: '__DWARF',
        vmaddr: dwarfSegVmaddr,
        vmsize: dwarfSegVmSize,
        fileoff: dwarfSegFileOff,
        filesize: dwarfSegFileSize,
        maxprot: 0,
        initprot: 0,
        sections: resolvedDwarfSects,
      );
    }

    // Write __LINKEDIT segment command.
    if (hasLinkedit) {
      cmdCursor = _writeSegment64Command(
        out: out,
        data: data,
        offset: cmdCursor,
        segname: '__LINKEDIT',
        vmaddr: linkeditVmaddr,
        vmsize: linkeditVmSize,
        fileoff: linkeditFileOff,
        filesize: linkeditFileSize,
        maxprot: 1,
        initprot: 1,
        sections: const [],
      );
    }

    // Write LC_UUID.
    if (effectiveUuid != null) {
      data
        ..setUint32(cmdCursor, MachOLoadCommandType.uuid, Endian.little)
        ..setUint32(cmdCursor + 4, 24, Endian.little);
      out.setRange(cmdCursor + 8, cmdCursor + 24, effectiveUuid);
      cmdCursor += 24;
    }

    // Write LC_SYMTAB.
    if (symbols.isNotEmpty) {
      data
        ..setUint32(cmdCursor, MachOLoadCommandType.symtab, Endian.little)
        ..setUint32(cmdCursor + 4, 24, Endian.little)
        ..setUint32(cmdCursor + 8, symoff, Endian.little)
        ..setUint32(cmdCursor + 12, symbols.length, Endian.little)
        ..setUint32(cmdCursor + 16, stroff, Endian.little)
        ..setUint32(cmdCursor + 20, strtabBytes.length, Endian.little);
      cmdCursor += 24;
    }

    // Write LC_DYSYMTAB.
    if (indirectSymbols.isNotEmpty || symbols.isNotEmpty) {
      final nlocal = symbols
          .where((s) => (s.nType & MachOSymbolType.nExt) == 0)
          .length;
      final nextdef = symbols
          .where(
            (s) =>
                (s.nType & MachOSymbolType.nExt) != 0 &&
                (s.nType & MachOSymbolType.nTypeMask) != MachOSymbolType.nUndf,
          )
          .length;
      final nundef = symbols.length - nlocal - nextdef;
      data
        ..setUint32(cmdCursor, MachOLoadCommandType.dysymtab, Endian.little)
        ..setUint32(cmdCursor + 4, 80, Endian.little)
        ..setUint32(cmdCursor + 8, 0, Endian.little)
        ..setUint32(cmdCursor + 12, nlocal, Endian.little)
        ..setUint32(cmdCursor + 16, nlocal, Endian.little)
        ..setUint32(cmdCursor + 20, nextdef, Endian.little)
        ..setUint32(cmdCursor + 24, nlocal + nextdef, Endian.little)
        ..setUint32(cmdCursor + 28, nundef, Endian.little)
        ..setUint32(
          cmdCursor + 56,
          indirectSymbols.isNotEmpty ? indirectsymoff : 0,
          Endian.little,
        )
        ..setUint32(cmdCursor + 60, indirectSymbols.length, Endian.little);
      cmdCursor += 80;
    }

    // Write LC_DYLD_EXPORTS_TRIE or LC_DYLD_INFO.
    if (exportedSymbols.isNotEmpty) {
      if (useLegacyDyldInfo) {
        data
          ..setUint32(
            cmdCursor,
            MachOLoadCommandType.dyldInfoOnly,
            Endian.little,
          )
          ..setUint32(cmdCursor + 4, 48, Endian.little)
          ..setUint32(cmdCursor + 40, exportTrieOff, Endian.little)
          ..setUint32(cmdCursor + 44, exportTrieBytes.length, Endian.little);
        cmdCursor += 48;
      } else {
        data
          ..setUint32(
            cmdCursor,
            MachOLoadCommandType.dyldExportsTrie,
            Endian.little,
          )
          ..setUint32(cmdCursor + 4, 16, Endian.little)
          ..setUint32(cmdCursor + 8, exportTrieOff, Endian.little)
          ..setUint32(cmdCursor + 12, exportTrieBytes.length, Endian.little);
        cmdCursor += 16;
      }
    }

    // Write LC_FUNCTION_STARTS.
    if (functionStartOffsets.isNotEmpty) {
      data
        ..setUint32(
          cmdCursor,
          MachOLoadCommandType.functionStarts,
          Endian.little,
        )
        ..setUint32(cmdCursor + 4, 16, Endian.little)
        ..setUint32(cmdCursor + 8, funcStartsOff, Endian.little)
        ..setUint32(cmdCursor + 12, funcStartsBytes.length, Endian.little);
      cmdCursor += 16;
    }

    // Write dylib load commands.
    for (final dylibCmd in encodedDylibCmds) {
      out.setRange(cmdCursor, cmdCursor + dylibCmd.length, dylibCmd);
      cmdCursor += dylibCmd.length;
    }

    // Write LC_CODE_SIGNATURE.
    if (codeSignatureBytes != null) {
      data
        ..setUint32(
          cmdCursor,
          MachOLoadCommandType.codeSignature,
          Endian.little,
        )
        ..setUint32(cmdCursor + 4, 16, Endian.little)
        ..setUint32(cmdCursor + 8, codeSigOff, Endian.little)
        ..setUint32(cmdCursor + 12, codeSignatureBytes.length, Endian.little);
      cmdCursor += 16;
    }

    // Write section payloads.
    for (final resolved in [
      ...resolvedTextSects,
      ...resolvedDataSects,
      ...resolvedDwarfSects,
    ]) {
      if (!resolved.spec.unbacked && resolved.spec.bytes.isNotEmpty) {
        out.setRange(
          resolved.fileOff,
          resolved.fileOff + resolved.spec.bytes.length,
          resolved.spec.bytes,
        );
      }
    }

    // Write __LINKEDIT payloads.
    if (exportTrieBytes.isNotEmpty) {
      out.setRange(
        exportTrieOff,
        exportTrieOff + exportTrieBytes.length,
        exportTrieBytes,
      );
    }
    if (funcStartsBytes.isNotEmpty) {
      out.setRange(
        funcStartsOff,
        funcStartsOff + funcStartsBytes.length,
        funcStartsBytes,
      );
    }
    if (symtabBytes.isNotEmpty) {
      out.setRange(symoff, symoff + symtabBytes.length, symtabBytes);
    }
    if (indirectBytes.isNotEmpty) {
      out.setRange(
        indirectsymoff,
        indirectsymoff + indirectBytes.length,
        indirectBytes,
      );
    }
    if (strtabBytes.isNotEmpty) {
      out.setRange(stroff, stroff + strtabBytes.length, strtabBytes);
    }
    if (linkeditTrailingPadding != null && linkeditTrailingPadding.isNotEmpty) {
      final padOff = stroff + strtabBytes.length;
      out.setRange(
        padOff,
        padOff + linkeditTrailingPadding.length,
        linkeditTrailingPadding,
      );
    }
    if (codeSignatureBytes != null && codeSignatureBytes.isNotEmpty) {
      out.setRange(
        codeSigOff,
        codeSigOff + codeSignatureBytes.length,
        codeSignatureBytes,
      );
    }

    return out;
  }

  /// Synthesizes a companion `.dSYM` Mach-O binary (`MH_DSYM`) with unbacked
  /// `__TEXT,__text` virtual addresses, `LC_SYMTAB` symbols, and optional
  /// `__DWARF,__debug_str` compile-path strings.
  static Uint8List buildDsym({
    int cpuType = MachOCpuType.arm64,
    int cpuSubtype = 0,
    Uint8List? uuid,
    int textVmaddr = 0x1000,
    int textSize = 64,
    List<MachOSymbolSpec> symbols = const [],
    List<String> dwarfStrings = const [],
  }) {
    return buildThin(
      cpuType: cpuType,
      cpuSubtype: cpuSubtype,
      fileType: MachOFileType.dsym,
      uuid: uuid,
      textInstructions: const [],
      extraSections: [
        MachOSectionSpec(
          segname: '__TEXT',
          sectname: '__text',
          bytes: Uint8List(textSize),
          addr: textVmaddr,
          unbacked: true,
        ),
      ],
      symbols: symbols,
      dwarfStrings: dwarfStrings,
    );
  }

  /// Synthesizes a Universal (fat) Mach-O binary (`0xcafebabe` or `0xcafebabf`)
  /// wrapping one or more thin 64-bit Mach-O slices.
  static Uint8List buildFat(
    List<Uint8List> sliceBytesList, {
    bool is64BitFat = false,
  }) {
    final entrySize = is64BitFat ? 32 : 20;
    final headerEnd = 8 + sliceBytesList.length * entrySize;
    var cursor = _alignUp(headerEnd, 64);

    final offsets = <int>[];
    for (final slice in sliceBytesList) {
      cursor = _alignUp(cursor, 64);
      offsets.add(cursor);
      cursor += slice.length;
    }

    final out = Uint8List(cursor);
    final data = ByteData.sublistView(out)
      ..setUint32(
        0,
        is64BitFat ? MachOMagic.fatMagic64 : MachOMagic.fatMagic,
      )
      ..setUint32(4, sliceBytesList.length);

    for (var i = 0; i < sliceBytesList.length; i++) {
      final slice = sliceBytesList[i];
      final sliceData = ByteData.sublistView(slice);
      final cpuType = sliceData.getUint32(4, Endian.little);
      final cpuSubtype = sliceData.getUint32(8, Endian.little);
      final entryOff = 8 + i * entrySize;

      data
        ..setUint32(entryOff, cpuType)
        ..setUint32(entryOff + 4, cpuSubtype);
      if (is64BitFat) {
        data
          ..setUint64(entryOff + 8, offsets[i])
          ..setUint64(entryOff + 16, slice.length)
          ..setUint32(entryOff + 24, 6)
          ..setUint32(entryOff + 28, 0);
      } else {
        data
          ..setUint32(entryOff + 8, offsets[i])
          ..setUint32(entryOff + 12, slice.length)
          ..setUint32(entryOff + 16, 6);
      }

      out.setRange(offsets[i], offsets[i] + slice.length, slice);
    }

    return out;
  }

  static int _writeSegment64Command({
    required Uint8List out,
    required ByteData data,
    required int offset,
    required String segname,
    required int vmaddr,
    required int vmsize,
    required int fileoff,
    required int filesize,
    required int maxprot,
    required int initprot,
    required List<_ResolvedSection> sections,
  }) {
    final cmdsize = 72 + sections.length * 80;
    data
      ..setUint32(offset, MachOLoadCommandType.segment64, Endian.little)
      ..setUint32(offset + 4, cmdsize, Endian.little);
    _writeFixedString(out, offset + 8, 16, segname);
    data
      ..setUint64(offset + 24, vmaddr, Endian.little)
      ..setUint64(offset + 32, vmsize, Endian.little)
      ..setUint64(offset + 40, fileoff, Endian.little)
      ..setUint64(offset + 48, filesize, Endian.little)
      ..setUint32(offset + 56, maxprot, Endian.little)
      ..setUint32(offset + 60, initprot, Endian.little)
      ..setUint32(offset + 64, sections.length, Endian.little)
      ..setUint32(offset + 68, 0, Endian.little);

    for (var i = 0; i < sections.length; i++) {
      final sect = sections[i];
      final sOff = offset + 72 + i * 80;
      _writeFixedString(out, sOff, 16, sect.spec.sectname);
      _writeFixedString(out, sOff + 16, 16, sect.spec.segname);
      data
        ..setUint64(sOff + 32, sect.addr, Endian.little)
        ..setUint64(sOff + 40, sect.spec.bytes.length, Endian.little)
        ..setUint32(sOff + 48, sect.fileOff, Endian.little)
        ..setUint32(sOff + 52, 2, Endian.little)
        ..setUint32(sOff + 56, 0, Endian.little)
        ..setUint32(sOff + 60, 0, Endian.little)
        ..setUint32(sOff + 64, sect.spec.flags, Endian.little)
        ..setUint32(sOff + 68, sect.spec.reserved1, Endian.little)
        ..setUint32(sOff + 72, sect.spec.reserved2, Endian.little)
        ..setUint32(sOff + 76, 0, Endian.little);
    }

    return offset + cmdsize;
  }

  static (Uint8List, Uint8List) _encodeSymtab(List<MachOSymbolSpec> symbols) {
    if (symbols.isEmpty) return (Uint8List(0), Uint8List(0));
    final symBytes = Uint8List(symbols.length * 16);
    final symData = ByteData.sublistView(symBytes);
    final strBuilder = BytesBuilder(copy: false)
      // Leading NUL byte at index 0.
      ..addByte(0);

    for (var i = 0; i < symbols.length; i++) {
      final sym = symbols[i];
      final strx = strBuilder.length;
      strBuilder
        ..add(utf8.encode(sym.name))
        ..addByte(0);

      final entryOff = i * 16;
      symData.setUint32(entryOff, strx, Endian.little);
      symBytes[entryOff + 4] = sym.nType;
      symBytes[entryOff + 5] = sym.nSect;
      symData
        ..setUint16(entryOff + 6, sym.nDesc, Endian.little)
        ..setUint64(entryOff + 8, sym.nValue, Endian.little);
    }

    while (strBuilder.length % 8 != 0) {
      strBuilder.addByte(0);
    }

    return (symBytes, strBuilder.takeBytes());
  }

  static Uint8List _encodeIndirectSymbols(List<int> indirectSymbols) {
    if (indirectSymbols.isEmpty) return Uint8List(0);
    final bytes = Uint8List(indirectSymbols.length * 4);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < indirectSymbols.length; i++) {
      data.setUint32(i * 4, indirectSymbols[i], Endian.little);
    }
    return bytes;
  }

  static Uint8List _encodeDylibCommand(MachODylib dylib) {
    final nameBytes = utf8.encode(dylib.name);
    final cmdsize = _alignUp(24 + nameBytes.length + 1, 8);
    final bytes = Uint8List(cmdsize);
    ByteData.sublistView(bytes)
      ..setUint32(0, dylib.cmd, Endian.little)
      ..setUint32(4, cmdsize, Endian.little)
      ..setUint32(8, 24, Endian.little)
      ..setUint32(12, dylib.timestamp, Endian.little)
      ..setUint32(16, dylib.currentVersion, Endian.little)
      ..setUint32(20, dylib.compatibilityVersion, Endian.little);
    bytes.setRange(24, 24 + nameBytes.length, nameBytes);
    return bytes;
  }

  /// Encodes a flat 1-level dyld export trie (root node with `N` children,
  /// each pointing to a leaf terminal node).
  static Uint8List _encodeExportTrie(List<MachOExportedSymbol> exports) {
    final leafNodes = <Uint8List>[];
    for (final exp in exports) {
      final termPayload = BytesBuilder(copy: false);
      _writeUleb128(termPayload, exp.flags);
      if (exp.isReexport) {
        _writeUleb128(termPayload, exp.reexportOrdinal ?? 1);
        if (exp.importedName != null && exp.importedName != exp.name) {
          termPayload.add(utf8.encode(exp.importedName!));
        }
        termPayload.addByte(0);
      } else if ((exp.flags & 0x10) != 0) {
        _writeUleb128(termPayload, exp.offset);
        _writeUleb128(termPayload, exp.offset);
      } else {
        _writeUleb128(termPayload, exp.offset);
      }
      final payloadBytes = termPayload.takeBytes();

      final leaf = BytesBuilder(copy: false);
      _writeUleb128(leaf, payloadBytes.length);
      leaf
        ..add(payloadBytes)
        ..addByte(0); // 0 children on leaf
      leafNodes.add(leaf.takeBytes());
    }

    // Iteratively compute root size until child offsets stabilize.
    var rootSize = 2;
    for (var pass = 0; pass < 4; pass++) {
      final root = BytesBuilder(copy: false)
        ..addByte(0) // root terminalSize = 0
        ..addByte(exports.length);
      var leafOff = rootSize;
      for (var i = 0; i < exports.length; i++) {
        root
          ..add(utf8.encode(exports[i].name))
          ..addByte(0);
        _writeUleb128(root, leafOff);
        leafOff += leafNodes[i].length;
      }
      rootSize = root.length;
    }

    final trie = BytesBuilder(copy: false)
      ..addByte(0)
      ..addByte(exports.length);
    var leafOff = rootSize;
    for (var i = 0; i < exports.length; i++) {
      trie
        ..add(utf8.encode(exports[i].name))
        ..addByte(0);
      _writeUleb128(trie, leafOff);
      leafOff += leafNodes[i].length;
    }
    leafNodes.forEach(trie.add);
    while (trie.length % 8 != 0) {
      trie.addByte(0);
    }
    return trie.takeBytes();
  }

  static Uint8List _encodeFunctionStarts(
    List<int> offsetsFromText,
    int textVmaddr,
  ) {
    final sorted = [
      for (final off in offsetsFromText) textVmaddr + off,
    ]..sort();
    final builder = BytesBuilder(copy: false);
    var prev = 0;
    for (final addr in sorted) {
      final delta = addr - prev;
      if (delta > 0) {
        _writeUleb128(builder, delta);
        prev = addr;
      }
    }
    while (builder.length % 8 != 0) {
      builder.addByte(0);
    }
    return builder.takeBytes();
  }

  static void _writeUleb128(BytesBuilder builder, int value) {
    var v = value;
    do {
      var byte = v & 0x7f;
      v >>>= 7;
      if (v != 0) byte |= 0x80;
      builder.addByte(byte);
    } while (v != 0);
  }

  static Uint8List _packNullTerminatedStrings(List<String> strings) {
    final builder = BytesBuilder(copy: false);
    for (final s in strings) {
      builder
        ..add(utf8.encode(s))
        ..addByte(0);
    }
    return builder.takeBytes();
  }

  static void _writeFixedString(
    Uint8List out,
    int offset,
    int maxLen,
    String value,
  ) {
    final encoded = utf8.encode(value);
    final count = encoded.length < maxLen ? encoded.length : maxLen;
    for (var i = 0; i < count; i++) {
      out[offset + i] = encoded[i];
    }
  }

  static int _alignUp(int value, int alignment) {
    final mask = alignment - 1;
    return (value + mask) & ~mask;
  }
}

class _ResolvedSection {
  const _ResolvedSection({
    required this.spec,
    required this.addr,
    required this.fileOff,
  });

  final MachOSectionSpec spec;
  final int addr;
  final int fileOff;
}
