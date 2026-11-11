// cspell:words aarch addralign addrs adrp debuglink descsz dynstr dynsym ehdr
// cspell:words ehsize elfclass elfdata entsize execinstr fini ifunc immhi
// cspell:words immlo insn insns movz namesz nobits notype phdr phentsize phnum
// cspell:words phoff progbits rela riscv rodata shdr shentsize shndx shnum
// cspell:words shoff shstrndx shstrtab soname strtab symtab undef
import 'dart:convert';
import 'dart:typed_data';

import 'package:elf/src/elf_parser.dart';

/// Pure-Dart ARM64 (AArch64) instruction encoder for constructing synthetic
/// `.text` function bodies in ELF tests.
abstract final class ElfArm64Encoder {
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

/// Specification for a symbol when building a synthetic ELF binary via
/// [ElfBuilder].
class ElfSymbolSpec {
  /// Creates a defined [ElfSymbolSpec].
  const ElfSymbolSpec({
    required this.name,
    this.value = 0x1000,
    this.size = 8,
    this.binding = ElfSymbolBinding.global,
    this.type = ElfSymbolType.func,
    this.visibility = ElfSymbolVisibility.defaultVisibility,
    this.sectionName = '.text',
    this.shndx,
  });

  /// Creates an undefined imported symbol (`SHN_UNDEF`).
  const ElfSymbolSpec.undefined(
    this.name, {
    this.binding = ElfSymbolBinding.global,
    this.type = ElfSymbolType.func,
    this.visibility = ElfSymbolVisibility.defaultVisibility,
  }) : value = 0,
       size = 0,
       sectionName = null,
       shndx = ElfSectionIndex.undef;

  /// Symbol name.
  final String name;

  /// Symbol virtual address (`st_value`).
  final int value;

  /// Symbol byte size (`st_size`).
  final int size;

  /// Symbol binding (`STB_LOCAL`, `STB_GLOBAL`, `STB_WEAK`).
  final int binding;

  /// Symbol type (`STT_FUNC`, `STT_OBJECT`, etc.).
  final int type;

  /// Symbol visibility (`STV_DEFAULT`, `STV_HIDDEN`, `STV_PROTECTED`, etc.).
  final int visibility;

  /// Target section name (e.g. `.text`, `.rodata`, `.data`), or `null` when
  /// [shndx] is set directly.
  final String? sectionName;

  /// Explicit `st_shndx` override (used when [sectionName] is `null`).
  final int? shndx;
}

/// Specification for an arbitrary section when building a synthetic ELF binary
/// via [ElfBuilder].
class ElfSectionSpec {
  /// Creates an [ElfSectionSpec].
  const ElfSectionSpec({
    required this.name,
    required this.bytes,
    this.type = ElfSectionType.progbits,
    this.flags = ElfSectionFlags.alloc,
    this.addr = 0,
    this.link = 0,
    this.info = 0,
    this.addralign = 8,
    this.entsize = 0,
    this.nobitsSize,
  });

  /// Section name (e.g. `.custom`, `.rodata.str1.1`).
  final String name;

  /// Raw section payload bytes (ignored when `type == ElfSectionType.nobits`).
  final Uint8List bytes;

  /// Section header type (`sh_type`).
  final int type;

  /// Section flags (`sh_flags`).
  final int flags;

  /// Virtual address (`sh_addr`, auto-assigned if `0` and `SHF_ALLOC` is set).
  final int addr;

  /// Linked section index (`sh_link`).
  final int link;

  /// Section info (`sh_info`).
  final int info;

  /// Section alignment (`sh_addralign`).
  final int addralign;

  /// Table entry size (`sh_entsize`).
  final int entsize;

  /// Virtual size override when `type == ElfSectionType.nobits`.
  final int? nobitsSize;
}

/// {@template elf_builder}
/// Pure-Dart in-memory synthesizer for ELF32 and ELF64 shared objects (`.so`)
/// and executables.
/// {@endtemplate}
abstract final class ElfBuilder {
  /// Default 20-byte SHA-1 GNU build ID (`01020304...14`).
  static final Uint8List defaultBuildId = Uint8List.fromList(
    List<int>.generate(20, (i) => i + 1),
  );

  /// Alternate 20-byte SHA-1 GNU build ID (`a1a2a3a4...b4`).
  static final Uint8List alternateBuildId = Uint8List.fromList(
    List<int>.generate(20, (i) => 0xa1 + i),
  );

  /// Synthesizes a valid ELF32 or ELF64 binary in memory.
  static Uint8List build({
    bool is64Bit = true,
    int dataEncoding = ElfData.lsb,
    int osAbi = 0,
    int abiVersion = 0,
    int fileType = ElfFileType.dyn,
    int? machine,
    int entry = 0x1000,
    int flags = 0,
    bool includeProgramHeader = false,
    Uint8List? buildId,
    bool includeBuildId = true,
    bool rawBuildIdSection = false,
    List<int>? textInstructions,
    Uint8List? textBytes,
    int textAddr = 0x1000,
    Uint8List? pltBytes,
    int pltAddr = 0x0f00,
    Uint8List? rodataBytes,
    List<String> rodataStrings = const [],
    int rodataAddr = 0x2000,
    Uint8List? dataBytes,
    int dataAddr = 0x3000,
    int bssSize = 0,
    List<ElfSymbolSpec> symbols = const [],
    List<ElfSymbolSpec> staticSymbols = const [],
    List<String> neededLibraries = const [],
    String? soname,
    String? debugLinkName,
    Uint8List? debugLinkBytes,
    Map<String, Uint8List> debugSections = const {},
    List<ElfSectionSpec> extraSections = const [],
    bool reverseSectionOrder = false,
  }) {
    final effectiveMachine =
        machine ?? (is64Bit ? ElfMachine.aarch64 : ElfMachine.arm);
    final endian = dataEncoding == ElfData.lsb ? Endian.little : Endian.big;

    final effectiveTextBytes =
        textBytes ??
        ElfArm64Encoder.encodeInstructions(
          textInstructions ??
              [ElfArm64Encoder.movz(0, 0), ElfArm64Encoder.ret()],
        );

    final effectiveRodataBytes =
        rodataBytes ??
        (rodataStrings.isNotEmpty
            ? _packNullTerminatedStrings(rodataStrings)
            : null);

    final effectiveBuildId = includeBuildId
        ? (buildId ?? defaultBuildId)
        : null;
    final buildIdNoteBytes = effectiveBuildId != null
        ? (rawBuildIdSection
              ? effectiveBuildId
              : _encodeGnuBuildIdNote(effectiveBuildId, endian))
        : null;

    final effectiveDebugLinkBytes =
        debugLinkBytes ??
        (debugLinkName != null
            ? _encodeDebugLink(debugLinkName, endian)
            : null);

    // Collect payload sections first so we can assign indices and build
    // .dynsym / .dynamic / .shstrtab.
    final payloadSpecs = <ElfSectionSpec>[
      if (buildIdNoteBytes != null)
        ElfSectionSpec(
          name: '.note.gnu.build-id',
          bytes: buildIdNoteBytes,
          type: ElfSectionType.note,
          addr: 0x0200,
          addralign: 4,
        ),
      if (pltBytes != null)
        ElfSectionSpec(
          name: '.plt',
          bytes: pltBytes,
          flags: ElfSectionFlags.alloc | ElfSectionFlags.execinstr,
          addr: pltAddr,
          addralign: 16,
        ),
      if (effectiveTextBytes.isNotEmpty)
        ElfSectionSpec(
          name: '.text',
          bytes: effectiveTextBytes,
          flags: ElfSectionFlags.alloc | ElfSectionFlags.execinstr,
          addr: textAddr,
          addralign: 16,
        ),
      if (effectiveRodataBytes != null)
        ElfSectionSpec(
          name: '.rodata',
          bytes: effectiveRodataBytes,
          addr: rodataAddr,
        ),
      if (dataBytes != null)
        ElfSectionSpec(
          name: '.data',
          bytes: dataBytes,
          flags: ElfSectionFlags.alloc | ElfSectionFlags.write,
          addr: dataAddr,
        ),
      if (bssSize > 0)
        ElfSectionSpec(
          name: '.bss',
          bytes: Uint8List(0),
          type: ElfSectionType.nobits,
          flags: ElfSectionFlags.alloc | ElfSectionFlags.write,
          addr: dataAddr + (dataBytes?.length ?? 0),
          nobitsSize: bssSize,
        ),
      ...extraSections,
      if (effectiveDebugLinkBytes != null)
        ElfSectionSpec(
          name: '.gnu_debuglink',
          bytes: effectiveDebugLinkBytes,
          flags: 0,
          addralign: 4,
        ),
      for (final entry in debugSections.entries)
        ElfSectionSpec(
          name: entry.key,
          bytes: entry.value,
          flags: 0,
          addralign: 1,
        ),
    ];

    final orderedPayloads = reverseSectionOrder
        ? payloadSpecs.reversed.toList()
        : payloadSpecs;

    // Assign 1-based section indices for payload sections (0 is SHT_NULL).
    final sectionIndexByName = <String, int>{};
    for (var i = 0; i < orderedPayloads.length; i++) {
      sectionIndexByName[orderedPayloads[i].name] = 1 + i;
    }

    // Build .dynstr and .dynsym / .dynamic.
    final dynstrBuilder = _StringTableBuilder();
    final neededOffsets = <int>[
      for (final lib in neededLibraries) dynstrBuilder.add(lib),
    ];
    final sonameOffset = soname != null ? dynstrBuilder.add(soname) : null;
    final dynSymNameOffsets = <int>[
      for (final sym in symbols) dynstrBuilder.add(sym.name),
    ];
    final dynstrBytes = dynstrBuilder.toBytes();

    final dynsymBytes = _encodeSymbols(
      symbols: symbols,
      nameOffsets: dynSymNameOffsets,
      sectionIndexByName: sectionIndexByName,
      is64Bit: is64Bit,
      endian: endian,
    );

    final hasDynamic = neededLibraries.isNotEmpty || soname != null;
    final dynamicBytes = hasDynamic
        ? _encodeDynamic(
            neededOffsets: neededOffsets,
            sonameOffset: sonameOffset,
            is64Bit: is64Bit,
            endian: endian,
          )
        : null;

    // Optional .strtab and .symtab.
    Uint8List? strtabBytes;
    Uint8List? symtabBytes;
    if (staticSymbols.isNotEmpty) {
      final strtabBuilder = _StringTableBuilder();
      final staticNameOffsets = <int>[
        for (final sym in staticSymbols) strtabBuilder.add(sym.name),
      ];
      strtabBytes = strtabBuilder.toBytes();
      symtabBytes = _encodeSymbols(
        symbols: staticSymbols,
        nameOffsets: staticNameOffsets,
        sectionIndexByName: sectionIndexByName,
        is64Bit: is64Bit,
        endian: endian,
      );
    }

    // Finalize all sections before .shstrtab.
    final allSpecs = <ElfSectionSpec>[
      ...orderedPayloads,
    ];

    final dynstrIndex = 1 + allSpecs.length;
    allSpecs.add(
      ElfSectionSpec(
        name: '.dynstr',
        bytes: dynstrBytes,
        type: ElfSectionType.strtab,
        addralign: 1,
      ),
    );

    final symEntrySize = is64Bit ? 24 : 16;
    allSpecs.add(
      ElfSectionSpec(
        name: '.dynsym',
        bytes: dynsymBytes,
        type: ElfSectionType.dynsym,
        link: dynstrIndex,
        info: 1,
        entsize: symEntrySize,
      ),
    );

    if (dynamicBytes != null) {
      allSpecs.add(
        ElfSectionSpec(
          name: '.dynamic',
          bytes: dynamicBytes,
          type: ElfSectionType.dynamicSection,
          flags: ElfSectionFlags.alloc | ElfSectionFlags.write,
          link: dynstrIndex,
          entsize: is64Bit ? 16 : 8,
        ),
      );
    }

    if (strtabBytes != null && symtabBytes != null) {
      final strtabIndex = 1 + allSpecs.length;
      allSpecs
        ..add(
          ElfSectionSpec(
            name: '.strtab',
            bytes: strtabBytes,
            type: ElfSectionType.strtab,
            flags: 0,
            addralign: 1,
          ),
        )
        ..add(
          ElfSectionSpec(
            name: '.symtab',
            bytes: symtabBytes,
            type: ElfSectionType.symtab,
            flags: 0,
            link: strtabIndex,
            info: 1,
            entsize: symEntrySize,
          ),
        );
    }

    // Build .shstrtab with names of all sections + .shstrtab itself.
    final shstrtabBuilder = _StringTableBuilder();
    final shNameOffsets = <int>[
      for (final spec in allSpecs) shstrtabBuilder.add(spec.name),
    ];
    final shstrtabNameOff = shstrtabBuilder.add('.shstrtab');
    final shstrtabBytes = shstrtabBuilder.toBytes();

    final shstrtabIndex = 1 + allSpecs.length;
    allSpecs.add(
      ElfSectionSpec(
        name: '.shstrtab',
        bytes: shstrtabBytes,
        type: ElfSectionType.strtab,
        flags: 0,
        addralign: 1,
      ),
    );
    shNameOffsets.add(shstrtabNameOff);

    // Compute file layout.
    final ehdrSize = is64Bit ? 64 : 52;
    final phdrSize = is64Bit ? 56 : 32;
    final shdrSize = is64Bit ? 64 : 40;
    final phnum = includeProgramHeader ? 1 : 0;
    final phoff = includeProgramHeader ? ehdrSize : 0;

    var cursor = _alignUp(ehdrSize + phnum * phdrSize, 16);
    var autoVmCursor = 0x4000;

    final sectionFileOffsets = <int>[];
    final sectionAddrs = <int>[];
    final sectionSizes = <int>[];

    for (final spec in allSpecs) {
      final align = spec.addralign > 1 ? spec.addralign : 1;
      if (spec.type == ElfSectionType.nobits) {
        sectionFileOffsets.add(cursor);
        final sz = spec.nobitsSize ?? spec.bytes.length;
        sectionSizes.add(sz);
        final addr = spec.addr != 0 ? spec.addr : autoVmCursor;
        sectionAddrs.add(addr);
        autoVmCursor = _alignUp(addr + sz, 16);
      } else {
        cursor = _alignUp(cursor, align);
        sectionFileOffsets.add(cursor);
        sectionSizes.add(spec.bytes.length);
        if (spec.addr != 0) {
          sectionAddrs.add(spec.addr);
        } else if ((spec.flags & ElfSectionFlags.alloc) != 0) {
          final addr = _alignUp(autoVmCursor, align);
          sectionAddrs.add(addr);
          autoVmCursor = _alignUp(addr + spec.bytes.length, 16);
        } else {
          sectionAddrs.add(0);
        }
        cursor += spec.bytes.length;
      }
    }

    cursor = _alignUp(cursor, 8);
    final shoff = cursor;
    final shnum = 1 + allSpecs.length; // SHT_NULL + allSpecs
    final totalSize = shoff + shnum * shdrSize;

    final out = Uint8List(totalSize);
    final data = ByteData.sublistView(out)
      // Write e_ident (16 bytes).
      ..setUint32(0, ElfMagic.magic);
    out[4] = is64Bit ? ElfClass.elfClass64 : ElfClass.elfClass32;
    out[5] = dataEncoding;
    out[6] = 1; // EV_CURRENT
    out[7] = osAbi;
    out[8] = abiVersion;

    data
      ..setUint16(16, fileType, endian)
      ..setUint16(18, effectiveMachine, endian)
      ..setUint32(20, 1, endian);

    if (is64Bit) {
      data
        ..setUint64(24, entry, endian)
        ..setUint64(32, phoff, endian)
        ..setUint64(40, shoff, endian)
        ..setUint32(48, flags, endian)
        ..setUint16(52, ehdrSize, endian)
        ..setUint16(54, includeProgramHeader ? phdrSize : 0, endian)
        ..setUint16(56, phnum, endian)
        ..setUint16(58, shdrSize, endian)
        ..setUint16(60, shnum, endian)
        ..setUint16(62, shstrtabIndex, endian);
    } else {
      data
        ..setUint32(24, entry, endian)
        ..setUint32(28, phoff, endian)
        ..setUint32(32, shoff, endian)
        ..setUint32(36, flags, endian)
        ..setUint16(40, ehdrSize, endian)
        ..setUint16(42, includeProgramHeader ? phdrSize : 0, endian)
        ..setUint16(44, phnum, endian)
        ..setUint16(46, shdrSize, endian)
        ..setUint16(48, shnum, endian)
        ..setUint16(50, shstrtabIndex, endian);
    }

    if (includeProgramHeader) {
      // PT_LOAD = 1
      data.setUint32(phoff, 1, endian);
    }

    // Copy section bytes.
    for (var i = 0; i < allSpecs.length; i++) {
      final spec = allSpecs[i];
      if (spec.type != ElfSectionType.nobits && spec.bytes.isNotEmpty) {
        final fileOff = sectionFileOffsets[i];
        out.setRange(fileOff, fileOff + spec.bytes.length, spec.bytes);
      }
    }

    // Write section headers (index 0 is SHT_NULL, already zero-initialized).
    for (var i = 0; i < allSpecs.length; i++) {
      final spec = allSpecs[i];
      final shdrOff = shoff + (i + 1) * shdrSize;
      data
        ..setUint32(shdrOff, shNameOffsets[i], endian)
        ..setUint32(shdrOff + 4, spec.type, endian);

      if (is64Bit) {
        data
          ..setUint64(shdrOff + 8, spec.flags, endian)
          ..setUint64(shdrOff + 16, sectionAddrs[i], endian)
          ..setUint64(shdrOff + 24, sectionFileOffsets[i], endian)
          ..setUint64(shdrOff + 32, sectionSizes[i], endian)
          ..setUint32(shdrOff + 40, spec.link, endian)
          ..setUint32(shdrOff + 44, spec.info, endian)
          ..setUint64(shdrOff + 48, spec.addralign, endian)
          ..setUint64(shdrOff + 56, spec.entsize, endian);
      } else {
        data
          ..setUint32(shdrOff + 8, spec.flags, endian)
          ..setUint32(shdrOff + 12, sectionAddrs[i], endian)
          ..setUint32(shdrOff + 16, sectionFileOffsets[i], endian)
          ..setUint32(shdrOff + 20, sectionSizes[i], endian)
          ..setUint32(shdrOff + 24, spec.link, endian)
          ..setUint32(shdrOff + 28, spec.info, endian)
          ..setUint32(shdrOff + 32, spec.addralign, endian)
          ..setUint32(shdrOff + 36, spec.entsize, endian);
      }
    }

    return out;
  }

  static Uint8List _encodeSymbols({
    required List<ElfSymbolSpec> symbols,
    required List<int> nameOffsets,
    required Map<String, int> sectionIndexByName,
    required bool is64Bit,
    required Endian endian,
  }) {
    final entrySize = is64Bit ? 24 : 16;
    // Entry 0 is the reserved STN_UNDEF null symbol.
    final bytes = Uint8List((1 + symbols.length) * entrySize);
    final data = ByteData.sublistView(bytes);

    for (var i = 0; i < symbols.length; i++) {
      final sym = symbols[i];
      final off = (i + 1) * entrySize;
      final stInfo = ElfSymbol.packInfo(sym.binding, sym.type);
      final stOther = sym.visibility & 0x03;
      final sectName = sym.sectionName;
      final stShndx =
          sym.shndx ??
          (sectName != null
              ? (sectionIndexByName[sectName] ?? 1)
              : ElfSectionIndex.undef);

      if (is64Bit) {
        data.setUint32(off, nameOffsets[i], endian);
        bytes[off + 4] = stInfo;
        bytes[off + 5] = stOther;
        data
          ..setUint16(off + 6, stShndx, endian)
          ..setUint64(off + 8, sym.value, endian)
          ..setUint64(off + 16, sym.size, endian);
      } else {
        data
          ..setUint32(off, nameOffsets[i], endian)
          ..setUint32(off + 4, sym.value, endian)
          ..setUint32(off + 8, sym.size, endian);
        bytes[off + 12] = stInfo;
        bytes[off + 13] = stOther;
        data.setUint16(off + 14, stShndx, endian);
      }
    }

    return bytes;
  }

  static Uint8List _encodeDynamic({
    required List<int> neededOffsets,
    required int? sonameOffset,
    required bool is64Bit,
    required Endian endian,
  }) {
    final entries = <(int, int)>[
      for (final off in neededOffsets) (ElfDynamicTag.needed, off),
      if (sonameOffset != null) (ElfDynamicTag.soname, sonameOffset),
      (ElfDynamicTag.dtNull, 0),
    ];

    final entrySize = is64Bit ? 16 : 8;
    final bytes = Uint8List(entries.length * entrySize);
    final data = ByteData.sublistView(bytes);

    for (var i = 0; i < entries.length; i++) {
      final (tag, val) = entries[i];
      final off = i * entrySize;
      if (is64Bit) {
        data
          ..setInt64(off, tag, endian)
          ..setUint64(off + 8, val, endian);
      } else {
        data
          ..setInt32(off, tag, endian)
          ..setUint32(off + 4, val, endian);
      }
    }

    return bytes;
  }

  static Uint8List _encodeGnuBuildIdNote(Uint8List buildId, Endian endian) {
    const gnuName = [0x47, 0x4e, 0x55, 0x00]; // "GNU\0"
    final alignedDescLen = _alignUp(buildId.length, 4);
    final bytes = Uint8List(12 + gnuName.length + alignedDescLen);
    ByteData.sublistView(bytes)
      ..setUint32(0, gnuName.length, endian)
      ..setUint32(4, buildId.length, endian)
      ..setUint32(8, 3, endian); // NT_GNU_BUILD_ID = 3
    bytes
      ..setRange(12, 16, gnuName)
      ..setRange(16, 16 + buildId.length, buildId);
    return bytes;
  }

  static Uint8List _encodeDebugLink(String filename, Endian endian) {
    final nameBytes = utf8.encode(filename);
    final paddedNameLen = _alignUp(nameBytes.length + 1, 4);
    final bytes = Uint8List(paddedNameLen + 4)
      ..setRange(0, nameBytes.length, nameBytes);
    ByteData.sublistView(bytes).setUint32(paddedNameLen, 0x12345678, endian);
    return bytes;
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

  static int _alignUp(int value, int alignment) {
    final rem = value % alignment;
    return rem == 0 ? value : value + (alignment - rem);
  }
}

class _StringTableBuilder {
  _StringTableBuilder() {
    _bytes.addByte(0);
  }

  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final Map<String, int> _offsets = {'': 0};

  int add(String value) {
    final existing = _offsets[value];
    if (existing != null) return existing;
    final offset = _bytes.length;
    _bytes
      ..add(utf8.encode(value))
      ..addByte(0);
    _offsets[value] = offset;
    return offset;
  }

  Uint8List toBytes() => _bytes.toBytes();
}
