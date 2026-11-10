// cspell:words adrp addrs bebafeca cafebabe cafebabf chkstk cputype cpusubtype
// cspell:words cstring cstrings dataoff datasize dsym dsyms dysymtab extdef
// cspell:words feedface feedfacf fieldmd fileoff filesize func iextdefsym
// cspell:words ilocalsym immhi immlo indirects indirectsymoff initprot insn
// cspell:words insns iundefsym linkedit ltmp maxprot methname ncmds nextdefsym
// cspell:words nfat nindirectsyms nlist nlocalsym nreloc nsects nsyms nundefsym
// cspell:words objc pext reexport reflstr reloff sectname segname sizeofcmds
// cspell:words stab stroff strsize strx symoff symtab typeref uleb undf
// cspell:words vmaddr vmsize zerofill
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Exception thrown when a Mach-O binary is malformed, truncated, or uses an
/// unsupported header format.
class MachOFormatException extends FormatException {
  /// Creates a [MachOFormatException] with the given [message].
  const MachOFormatException(super.message);
}

/// Magic numbers identifying Mach-O thin and universal (fat) binaries.
abstract final class MachOMagic {
  /// 32-bit little-endian Mach-O magic (`MH_MAGIC`).
  static const int mhMagic32 = 0xfeedface;

  /// 64-bit little-endian Mach-O magic (`MH_MAGIC_64`).
  static const int mhMagic64 = 0xfeedfacf;

  /// 32-bit big-endian Universal (fat) magic (`FAT_MAGIC`).
  static const int fatMagic = 0xcafebabe;

  /// 64-bit big-endian Universal (fat) magic (`FAT_MAGIC_64`).
  static const int fatMagic64 = 0xcafebabf;
}

/// Mach-O CPU type constants (`cputype`).
abstract final class MachOCpuType {
  /// x86_64 architecture (`CPU_TYPE_X86_64`).
  static const int x86_64 = 0x01000007;

  /// 64-bit ARM architecture (`CPU_TYPE_ARM64`).
  static const int arm64 = 0x0100000c;
}

/// Mach-O file type constants (`filetype`).
abstract final class MachOFileType {
  /// Relocatable object file (`MH_OBJECT`).
  static const int object = 0x1;

  /// Demand paged executable file (`MH_EXECUTE`).
  static const int execute = 0x2;

  /// Dynamically bound shared library (`MH_DYLIB`).
  static const int dylib = 0x6;

  /// Dynamically bound bundle file (`MH_BUNDLE`).
  static const int bundle = 0x8;

  /// Companion debug symbol file (`MH_DSYM`).
  static const int dsym = 0xa;
}

/// Mach-O load command type constants (`cmd`).
abstract final class MachOLoadCommandType {
  /// Link-edit stab symbol table info (`LC_SYMTAB`).
  static const int symtab = 0x02;

  /// Dynamic link-edit symbol table info (`LC_DYSYMTAB`).
  static const int dysymtab = 0x0b;

  /// Load a dynamically linked shared library (`LC_LOAD_DYLIB`).
  static const int loadDylib = 0x0c;

  /// 64-bit segment of this file to be mapped (`LC_SEGMENT_64`).
  static const int segment64 = 0x19;

  /// 128-bit UUID of the binary (`LC_UUID`).
  static const int uuid = 0x1b;

  /// Local of code signature (`LC_CODE_SIGNATURE`).
  static const int codeSignature = 0x1d;

  /// Delay load of dylib until first use (`LC_LAZY_LOAD_DYLIB`).
  static const int lazyLoadDylib = 0x20;

  /// Compressed dyld information (`LC_DYLD_INFO`).
  static const int dyldInfo = 0x22;

  /// Compressed table of function start addresses (`LC_FUNCTION_STARTS`).
  static const int functionStarts = 0x26;

  /// Load a weak dynamically linked shared library (`LC_LOAD_WEAK_DYLIB`).
  static const int loadWeakDylib = 0x80000018;

  /// Load and re-export a dylib (`LC_REEXPORT_DYLIB`).
  static const int reexportDylib = 0x8000001f;

  /// Compressed dyld information only (`LC_DYLD_INFO_ONLY`).
  static const int dyldInfoOnly = 0x80000022;

  /// Load upward dylib (`LC_LOAD_UPWARD_DYLIB`).
  static const int loadUpwardDylib = 0x80000023;

  /// Exports trie (`LC_DYLD_EXPORTS_TRIE`).
  static const int dyldExportsTrie = 0x80000033;
}

/// Mach-O symbol table `n_type` bit masks and stab constants.
abstract final class MachOSymbolType {
  /// Mask for symbolic debugging entries (`N_STAB`).
  static const int nStab = 0xe0;

  /// Private external symbol bit (`N_PEXT`).
  static const int nPext = 0x10;

  /// Mask for symbol type bits (`N_TYPE`).
  static const int nTypeMask = 0x0e;

  /// External symbol bit (`N_EXT`).
  static const int nExt = 0x01;

  /// Undefined symbol (`N_UNDF`).
  static const int nUndf = 0x00;

  /// Absolute symbol (`N_ABS`).
  static const int nAbs = 0x02;

  /// Defined in section number `n_sect` (`N_SECT`).
  static const int nSect = 0x0e;

  /// Source file name stab (`N_SO`).
  static const int nSo = 0x64;

  /// Object file name stab (`N_OSO`).
  static const int nOso = 0x66;

  /// Included source file name stab (`N_SOL`).
  static const int nSol = 0x84;

  /// Special indirect symbol value for local symbols (`INDIRECT_SYMBOL_LOCAL`).
  static const int indirectSymbolLocal = 0x80000000;

  /// Special indirect symbol value for absolute symbols
  /// (`INDIRECT_SYMBOL_ABS`).
  static const int indirectSymbolAbs = 0x40000000;
}

/// Mach-O section type constants (`flags & SECTION_TYPE`).
abstract final class MachOSectionType {
  /// Regular section (`S_REGULAR`).
  static const int regular = 0x00;

  /// Zero fill on demand section (`S_ZEROFILL`).
  static const int zerofill = 0x01;

  /// Section with only literal C strings (`S_CSTRING_LITERALS`).
  static const int cstringLiterals = 0x02;

  /// Section with only symbol stubs (`S_SYMBOL_STUBS`).
  static const int symbolStubs = 0x08;

  /// Zero fill on demand section >4GB (`S_GB_ZEROFILL`).
  static const int gbZerofill = 0x0c;
}

/// {@template macho_file}
/// A parsed Mach-O binary (either a thin 64-bit binary or a Universal fat
/// binary containing multiple architecture slices).
/// {@endtemplate}
@immutable
class MachOFile {
  /// {@macro macho_file}
  const MachOFile({
    required this.slices,
    required this.isFat,
  });

  /// Architecture slices contained in this Mach-O file, sorted by
  /// `(cpuType, cpuSubtype)`.
  final List<MachOSlice> slices;

  /// Whether this file was parsed from a Universal (fat) header.
  final bool isFat;
}

/// {@template macho_header}
/// The 64-bit Mach-O header (`mach_header_64`) for a single architecture slice.
/// {@endtemplate}
@immutable
class MachOHeader {
  /// {@macro macho_header}
  const MachOHeader({
    required this.cpuType,
    required this.cpuSubtype,
    required this.fileType,
    required this.ncmds,
    required this.sizeofcmds,
    required this.flags,
  });

  /// CPU family identifier (`cputype`).
  final int cpuType;

  /// Specific CPU subtype (`cpusubtype`).
  final int cpuSubtype;

  /// Usage and alignment of the file (`filetype`).
  final int fileType;

  /// Number of load commands following the header (`ncmds`).
  final int ncmds;

  /// Total byte size of all load commands (`sizeofcmds`).
  final int sizeofcmds;

  /// Bit flags for dyld and the kernel (`flags`).
  final int flags;
}

/// {@template macho_segment}
/// A parsed 64-bit segment load command (`LC_SEGMENT_64`).
/// {@endtemplate}
@immutable
class MachOSegment {
  /// {@macro macho_segment}
  const MachOSegment({
    required this.name,
    required this.vmaddr,
    required this.vmsize,
    required this.fileoff,
    required this.filesize,
    required this.maxprot,
    required this.initprot,
    required this.flags,
    required this.sections,
  });

  /// Segment name (e.g. `__TEXT`, `__DATA`, `__LINKEDIT`).
  final String name;

  /// Starting virtual memory address (`vmaddr`).
  final int vmaddr;

  /// Virtual memory size (`vmsize`).
  final int vmsize;

  /// File offset of this segment (`fileoff`).
  final int fileoff;

  /// Number of bytes to map from the file (`filesize`).
  final int filesize;

  /// Maximum virtual memory protection (`maxprot`).
  final int maxprot;

  /// Initial virtual memory protection (`initprot`).
  final int initprot;

  /// Segment flags (`flags`).
  final int flags;

  /// Sections belonging to this segment.
  final List<MachOSection> sections;
}

/// {@template macho_section}
/// A parsed 64-bit section (`section_64`) within an `LC_SEGMENT_64` command.
/// {@endtemplate}
@immutable
class MachOSection {
  /// {@macro macho_section}
  const MachOSection({
    required this.segname,
    required this.sectname,
    required this.addr,
    required this.size,
    required this.offset,
    required this.align,
    required this.reloff,
    required this.nreloc,
    required this.flags,
    required this.reserved1,
    required this.reserved2,
    required this.reserved3,
    required this.bytes,
  });

  /// Segment name (e.g. `__TEXT`).
  final String segname;

  /// Section name (e.g. `__text`, `__cstring`).
  final String sectname;

  /// Virtual memory address (`addr`).
  final int addr;

  /// Size in bytes of the section (`size`).
  final int size;

  /// File offset of the section payload (`offset`).
  final int offset;

  /// Power-of-two alignment of the section (`align`).
  final int align;

  /// File offset of relocation entries (`reloff`).
  final int reloff;

  /// Number of relocation entries (`nreloc`).
  final int nreloc;

  /// Section type and attribute flags (`flags`).
  final int flags;

  /// Reserved field 1 (for stub/pointer sections, the start index into the
  /// indirect symbol table).
  final int reserved1;

  /// Reserved field 2 (for `S_SYMBOL_STUBS`, the byte size of each stub).
  final int reserved2;

  /// Reserved field 3.
  final int reserved3;

  /// Raw section bytes from the file (`empty` for zero-fill or unbacked
  /// `.dSYM` sections).
  final Uint8List bytes;

  /// Combined `<segname>,<sectname>` identifier (e.g. `__TEXT,__text`).
  String get fullName => '$segname,$sectname';

  /// The low 8-bit section type (`flags & 0xff`).
  int get sectionType => flags & 0xff;
}

/// {@template macho_symbol}
/// A parsed symbol table entry (`nlist_64`) from `LC_SYMTAB`.
/// {@endtemplate}
@immutable
class MachOSymbol {
  /// {@macro macho_symbol}
  const MachOSymbol({
    required this.name,
    required this.nType,
    required this.nSect,
    required this.nDesc,
    required this.nValue,
    this.sectionName,
  });

  /// Symbol name resolved from the string table.
  final String name;

  /// Raw `n_type` byte.
  final int nType;

  /// 1-based section index (`n_sect`), or `0` (`NO_SECT`).
  final int nSect;

  /// 16-bit symbol description flags (`n_desc`).
  final int nDesc;

  /// 64-bit symbol value / virtual address (`n_value`).
  final int nValue;

  /// Resolved `<segname>,<sectname>` for `nSect`, if defined in a section.
  final String? sectionName;

  /// Whether this entry is a symbolic debugging entry (`N_STAB`).
  bool get isDebugStab => (nType & MachOSymbolType.nStab) != 0;

  /// Whether this entry is an undefined external reference (`N_UNDF`).
  bool get isUndefined =>
      !isDebugStab &&
      (nType & MachOSymbolType.nTypeMask) == MachOSymbolType.nUndf &&
      nValue == 0;

  /// Whether this entry is defined in a section (`N_SECT`).
  bool get isDefinedInSection =>
      !isDebugStab &&
      (nType & MachOSymbolType.nTypeMask) == MachOSymbolType.nSect;

  /// Whether the external bit (`N_EXT`) is set.
  bool get isExternal => (nType & MachOSymbolType.nExt) != 0;

  /// Whether the private external bit (`N_PEXT`) is set.
  bool get isPrivateExternal => (nType & MachOSymbolType.nPext) != 0;

  /// Whether the weak definition bit (`N_WEAK_DEF`) is set in `nDesc`.
  bool get isWeakDef => (nDesc & 0x0080) != 0;

  /// Whether the weak reference bit (`N_WEAK_REF`) is set in `nDesc`.
  bool get isWeakRef => (nDesc & 0x0040) != 0;
}

/// {@template macho_dysymtab}
/// Parsed dynamic symbol table metadata (`LC_DYSYMTAB`).
/// {@endtemplate}
@immutable
class MachODysymtab {
  /// {@macro macho_dysymtab}
  const MachODysymtab({
    required this.ilocalsym,
    required this.nlocalsym,
    required this.iextdefsym,
    required this.nextdefsym,
    required this.iundefsym,
    required this.nundefsym,
    required this.indirectsymoff,
    required this.nindirectsyms,
    required this.indirectSymbols,
  });

  /// Index to local symbols.
  final int ilocalsym;

  /// Number of local symbols.
  final int nlocalsym;

  /// Index to externally defined symbols.
  final int iextdefsym;

  /// Number of externally defined symbols.
  final int nextdefsym;

  /// Index to undefined symbols.
  final int iundefsym;

  /// Number of undefined symbols.
  final int nundefsym;

  /// File offset to the indirect symbol table.
  final int indirectsymoff;

  /// Number of indirect symbol table entries.
  final int nindirectsyms;

  /// Entries of the indirect symbol table (indices into `LC_SYMTAB`).
  final Uint32List indirectSymbols;
}

/// {@template macho_exported_symbol}
/// An exported symbol decoded from `LC_DYLD_EXPORTS_TRIE` or `LC_DYLD_INFO`.
/// {@endtemplate}
@immutable
class MachOExportedSymbol {
  /// {@macro macho_exported_symbol}
  const MachOExportedSymbol({
    required this.name,
    required this.flags,
    required this.offset,
    this.reexportOrdinal,
    this.importedName,
  });

  /// Exported symbol name.
  final String name;

  /// Export flags (`EXPORT_SYMBOL_FLAGS_*`).
  final int flags;

  /// Symbol offset from the base of `__TEXT` (0 for re-exports).
  final int offset;

  /// 1-based dylib ordinal if this export is a re-export (`flags & 0x08 != 0`).
  final int? reexportOrdinal;

  /// Original imported name if re-exported under an alias.
  final String? importedName;

  /// Whether this export re-exports a symbol from a dependent dylib.
  bool get isReexport => (flags & 0x08) != 0;
}

/// {@template macho_dylib}
/// A linked dynamic library from `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`,
/// `LC_REEXPORT_DYLIB`, `LC_LAZY_LOAD_DYLIB`, or `LC_LOAD_UPWARD_DYLIB`.
/// {@endtemplate}
@immutable
class MachODylib {
  /// {@macro macho_dylib}
  const MachODylib({
    required this.name,
    required this.cmd,
    required this.timestamp,
    required this.currentVersion,
    required this.compatibilityVersion,
  });

  /// Install name / path of the dynamic library.
  final String name;

  /// Load command type (`LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, etc.).
  final int cmd;

  /// Build timestamp (`timestamp`).
  final int timestamp;

  /// Packed `X.Y.Z` current version (`current_version`).
  final int currentVersion;

  /// Packed `X.Y.Z` compatibility version (`compatibility_version`).
  final int compatibilityVersion;

  /// Whether this dylib is weakly linked (`LC_LOAD_WEAK_DYLIB`).
  bool get isWeak => cmd == MachOLoadCommandType.loadWeakDylib;

  /// Whether this dylib is re-exported (`LC_REEXPORT_DYLIB`).
  bool get isReexport => cmd == MachOLoadCommandType.reexportDylib;

  /// Formats a packed 32-bit Mach-O version (`xxxx.yy.zz`) as `X.Y.Z`.
  static String formatVersion(int version) {
    final major = version >>> 16;
    final minor = (version >>> 8) & 0xff;
    final patch = version & 0xff;
    return '$major.$minor.$patch';
  }
}

/// {@template macho_code_signature}
/// Code signature location and payload (`LC_CODE_SIGNATURE`).
/// {@endtemplate}
@immutable
class MachOCodeSignature {
  /// {@macro macho_code_signature}
  const MachOCodeSignature({
    required this.dataoff,
    required this.datasize,
    required this.bytes,
  });

  /// File offset of the signature blob in `__LINKEDIT`.
  final int dataoff;

  /// Byte size of the signature blob.
  final int datasize;

  /// Raw signature bytes.
  final Uint8List bytes;
}

/// {@template macho_canonical_instruction}
/// A single canonicalized instruction within a Mach-O function.
/// {@endtemplate}
@immutable
class MachOCanonicalInstruction {
  /// {@macro macho_canonical_instruction}
  const MachOCanonicalInstruction({
    required this.address,
    required this.tokens,
  });

  /// Byte offset of this instruction relative to the start of the function.
  final int address;

  /// Canonical token representation (trailing comma stripped if rendered).
  final String tokens;

  /// Whether this instruction carries a resolved string literal (`S:...`).
  bool get hasStringLiteral => tokens.contains('S:');

  /// Splits [tokens] into comma-separated tokens.
  List<String> _splitTokens() {
    final trimmed = tokens.endsWith(',')
        ? tokens.substring(0, tokens.length - 1)
        : tokens;
    if (trimmed.isEmpty) return const [];
    return trimmed.split(',');
  }

  /// Whether this instruction has more than [limit] tokens.
  bool exceedsTokens(int limit) => _splitTokens().length > limit;

  /// Renders the instruction tokens for human-readable diff output.
  String render({required bool showLiterals, int? limit}) {
    final parts = _splitTokens();
    final rendered = <String>[];
    final count = limit != null && parts.length > limit ? limit : parts.length;
    for (var i = 0; i < count; i++) {
      final part = parts[i];
      if (!showLiterals && part.startsWith('S:')) {
        final literal = part.substring(2);
        rendered.add('string(len=${literal.length})');
      } else {
        rendered.add(part);
      }
    }
    if (limit != null && parts.length > limit) {
      rendered.add('...');
    }
    return rendered.join(' ');
  }
}

/// {@template macho_function}
/// A resolved function slice from `__TEXT,__text` with canonicalized
/// instructions.
/// {@endtemplate}
@immutable
class MachOFunction {
  /// {@macro macho_function}
  const MachOFunction({
    required this.name,
    required this.address,
    required this.size,
    required this.isAnonymous,
    required this.canonicalInstructions,
    required this.instructionStarts,
    required this.instructionAddresses,
  });

  /// Resolved symbol name (from `.dSYM` or `LC_SYMTAB`), or ordinal `sub_<N>`
  /// when stripped.
  final String name;

  /// Virtual address of the function start in `__TEXT,__text`.
  final int address;

  /// Size in bytes of the function body.
  final int size;

  /// Whether the function had no symbol name and was named by ordinal.
  final bool isAnonymous;

  /// Concatenated canonical instruction tokens.
  final String canonicalInstructions;

  /// Start indices into [canonicalInstructions] for each instruction.
  final Uint32List instructionStarts;

  /// Function-relative byte offset of each instruction.
  final Uint32List instructionAddresses;

  /// Number of instructions in this function.
  int get instructionCount => instructionStarts.length;

  /// Returns the canonical token string for instruction at [index].
  String tokensAt(int index) => canonicalInstructions.substring(
    instructionStarts[index],
    index + 1 < instructionStarts.length
        ? instructionStarts[index + 1]
        : canonicalInstructions.length,
  );

  /// Materializes the [MachOCanonicalInstruction] at [index].
  MachOCanonicalInstruction instructionAt(int index) =>
      MachOCanonicalInstruction(
        address: instructionAddresses[index],
        tokens: tokensAt(index),
      );
}

/// {@template macho_slice}
/// A single parsed 64-bit Mach-O architecture slice.
/// {@endtemplate}
@immutable
class MachOSlice {
  /// {@macro macho_slice}
  const MachOSlice({
    required this.header,
    required this.uuid,
    required this.segments,
    required this.sections,
    required this.symbols,
    required this.dysymtab,
    required this.exportedSymbols,
    required this.dylibs,
    required this.functionStarts,
    required this.codeSignature,
    required this.linkeditPaddingBytes,
    required this.objcClassNames,
    required this.objcSelectors,
    required this.swiftSections,
    required this.cstrings,
    required this.constSections,
    required this.dwarfCompilePaths,
    required this.stubTargetNames,
    required this.referencedSymbols,
  });

  /// The 64-bit Mach-O header.
  final MachOHeader header;

  /// The 16-byte UUID from `LC_UUID`, or `null` if absent.
  final Uint8List? uuid;

  /// Parsed `LC_SEGMENT_64` segments.
  final List<MachOSegment> segments;

  /// All sections across all segments, in load-command order (1-indexed by
  /// `n_sect`).
  final List<MachOSection> sections;

  /// Parsed symbols from `LC_SYMTAB`.
  final List<MachOSymbol> symbols;

  /// Parsed dynamic symbol table metadata (`LC_DYSYMTAB`), or `null` if absent.
  final MachODysymtab? dysymtab;

  /// Exported symbols decoded from `LC_DYLD_EXPORTS_TRIE` or `LC_DYLD_INFO`.
  final List<MachOExportedSymbol> exportedSymbols;

  /// Linked dynamic libraries (`LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, etc.).
  final List<MachODylib> dylibs;

  /// Function start virtual addresses decoded from `LC_FUNCTION_STARTS`.
  final List<int> functionStarts;

  /// Parsed `LC_CODE_SIGNATURE` command, or `null` if unsigned.
  final MachOCodeSignature? codeSignature;

  /// Non-semantic padding and code-signature bytes in `__LINKEDIT`.
  final Uint8List linkeditPaddingBytes;

  /// Objective-C class names from `__objc_classname`.
  final List<String> objcClassNames;

  /// Objective-C method selector names from `__objc_methname`.
  final List<String> objcSelectors;

  /// Swift metadata descriptor sections (`__swift5_*`), keyed by
  /// `<segname>,<sectname>`.
  final Map<String, Uint8List> swiftSections;

  /// C string literals from `__TEXT,__cstring`.
  final List<String> cstrings;

  /// Constant/initialized data sections (`__DATA,__const`,
  /// `__DATA_CONST,__const`, `__TEXT,__const`, `__DATA,__data`), keyed by
  /// `<segname>,<sectname>`.
  final Map<String, Uint8List> constSections;

  /// Compile-directory and object-file paths extracted from `N_OSO` / `N_SO`
  /// debug stabs and `__DWARF` string tables.
  final List<String> dwarfCompilePaths;

  /// Maps stub virtual addresses in `__TEXT,__stubs` / `__TEXT,__auth_stubs`
  /// to the imported symbol name they jump to.
  final Map<int, String> stubTargetNames;

  /// Symbol names referenced by branch instructions in `__TEXT,__text`.
  final Set<String> referencedSymbols;

  /// Returns the `__TEXT,__text` section, or `null` if absent.
  MachOSection? get textSection {
    for (final s in sections) {
      if (s.segname == '__TEXT' && s.sectname == '__text') return s;
    }
    return null;
  }

  /// Whether any instruction in `__TEXT,__text` branches to [symbolName]
  /// (either directly or via a symbol stub).
  bool callsSymbol(String symbolName) => referencedSymbols.contains(symbolName);

  /// Resolves per-function slices in `__TEXT,__text`, optionally enriched by a
  /// companion [dsymSlice]'s symbol table (`LC_SYMTAB`).
  ///
  /// PC-relative branch (`b`, `bl`) and page-address (`adrp`) targets are
  /// canonicalized so linker layout shifts do not produce false-positive code
  /// diffs while real instruction or target changes are caught.
  List<MachOFunction> resolveFunctions({MachOSlice? dsymSlice}) {
    final text = textSection;
    if (text == null || text.bytes.isEmpty) return const [];

    final textStart = text.addr;
    final textEnd = text.addr + text.size;

    var textSegmentVmaddr = 0;
    for (final seg in segments) {
      if (seg.name == '__TEXT') {
        textSegmentVmaddr = seg.vmaddr;
        break;
      }
    }

    final addressToName = <int, String>{};

    // 1. Exported symbols from dyld export trie.
    for (final exp in exportedSymbols) {
      if (!exp.isReexport && exp.name.isNotEmpty) {
        final baseAddr = exp.offset < textStart ? textStart : textSegmentVmaddr;
        final addr = baseAddr + exp.offset;
        if (addr >= textStart && addr < textEnd) {
          addressToName[addr] = exp.name;
        }
      }
    }

    // 2. Own LC_SYMTAB defined text symbols.
    for (final sym in symbols) {
      if (sym.isDefinedInSection &&
          sym.name.isNotEmpty &&
          !sym.name.startsWith('ltmp') &&
          sym.nValue >= textStart &&
          sym.nValue < textEnd &&
          (sym.sectionName == null || sym.sectionName == '__TEXT,__text')) {
        addressToName[sym.nValue] = sym.name;
      }
    }

    // 3. Companion .dSYM LC_SYMTAB symbols (highest priority for naming
    // stripped functions).
    if (dsymSlice != null) {
      for (final sym in dsymSlice.symbols) {
        if (sym.isDefinedInSection &&
            sym.name.isNotEmpty &&
            !sym.name.startsWith('ltmp') &&
            sym.nValue >= textStart &&
            sym.nValue < textEnd &&
            (sym.sectionName == null || sym.sectionName == '__TEXT,__text')) {
          addressToName[sym.nValue] = sym.name;
        }
      }
    }

    final startSet = <int>{
      for (final addr in functionStarts)
        if (addr >= textStart && addr < textEnd) addr,
      ...addressToName.keys,
    };

    if (startSet.isEmpty) {
      startSet.add(textStart);
    }

    final sortedStarts = startSet.toList()..sort();

    // Map cstring virtual addresses for ADRP+ADD literal resolution.
    final cstringByAddr = <int, String>{};
    for (final s in sections) {
      if (s.segname == '__TEXT' && s.sectname == '__cstring') {
        var strStart = 0;
        for (var i = 0; i < s.bytes.length; i++) {
          if (s.bytes[i] == 0) {
            final str = utf8.decode(
              s.bytes.sublist(strStart, i),
              allowMalformed: true,
            );
            cstringByAddr[s.addr + strStart] = str;
            strStart = i + 1;
          }
        }
      }
    }

    // First pass: assign function names.
    final funcNames = <int, String>{};
    final funcAnon = <int, bool>{};
    var anonIndex = 0;
    for (final startAddr in sortedStarts) {
      final symbolName = addressToName[startAddr];
      if (symbolName != null) {
        funcNames[startAddr] = symbolName;
        funcAnon[startAddr] = false;
      } else if (sortedStarts.length == 1 && functionStarts.isEmpty) {
        funcNames[startAddr] = '__TEXT,__text';
        funcAnon[startAddr] = false;
      } else {
        funcNames[startAddr] = 'sub_$anonIndex';
        funcAnon[startAddr] = true;
        anonIndex++;
      }
    }

    // Second pass: canonicalize instructions per function.
    final functions = <MachOFunction>[];
    final data = ByteData.sublistView(text.bytes);

    for (var i = 0; i < sortedStarts.length; i++) {
      final startAddr = sortedStarts[i];
      final endAddr = i + 1 < sortedStarts.length
          ? sortedStarts[i + 1]
          : textEnd;
      final byteStart = startAddr - textStart;
      final byteEnd = (endAddr - textStart).clamp(0, text.bytes.length);
      final funcSize = byteEnd - byteStart;
      if (funcSize <= 0) continue;

      final buffer = StringBuffer();
      final startsList = <int>[];
      final addrsList = <int>[];

      if (header.cpuType == MachOCpuType.arm64 && funcSize % 4 == 0) {
        final insnCount = funcSize ~/ 4;
        for (var j = 0; j < insnCount; j++) {
          final fileOff = byteStart + j * 4;
          final relOff = j * 4;
          final pc = startAddr + relOff;
          final insn = data.getUint32(fileOff, Endian.little);

          startsList.add(buffer.length);
          addrsList.add(relOff);

          final op6 = insn >>> 26;
          if (op6 == 0x05 || op6 == 0x25) {
            // Unconditional B (0x05) or BL (0x25).
            final mnemonic = op6 == 0x25 ? 'bl' : 'b';
            final imm26 = insn & 0x03ffffff;
            final signedImm26 = (imm26 & 0x02000000) != 0
                ? (imm26 | ~0x03ffffff)
                : imm26;
            final targetAddr = pc + signedImm26 * 4;

            if (targetAddr >= startAddr && targetAddr < endAddr) {
              final funcRel = targetAddr - startAddr;
              buffer.write('$mnemonic,+0x${funcRel.toRadixString(16)},');
            } else if (stubTargetNames.containsKey(targetAddr)) {
              buffer.write('$mnemonic,${stubTargetNames[targetAddr]},');
            } else if (addressToName.containsKey(targetAddr)) {
              buffer.write('$mnemonic,${addressToName[targetAddr]},');
            } else if (funcNames.containsKey(targetAddr)) {
              buffer.write('$mnemonic,${funcNames[targetAddr]},');
            } else {
              buffer.write('$mnemonic,0x${targetAddr.toRadixString(16)},');
            }
          } else if ((insn & 0x9f000000) == 0x90000000) {
            // ADRP xRd, <page>.
            final rd = insn & 0x1f;
            final regName = rd == 31 ? 'xzr' : 'x$rd';
            final immlo = (insn >>> 29) & 0x3;
            final immhi = (insn >>> 5) & 0x7ffff;
            final imm21 = (immhi << 2) | immlo;
            final signedImm21 = (imm21 & 0x100000) != 0
                ? (imm21 | ~0x1fffff)
                : imm21;
            final targetPage = (pc & ~0xfff) + (signedImm21 << 12);

            // Check if the next instruction is `ADD xRn, xRd, #imm12`
            // resolving a C string literal in `__TEXT,__cstring`.
            String? resolvedCstring;
            if (j + 1 < insnCount) {
              final nextInsn = data.getUint32(fileOff + 4, Endian.little);
              if ((nextInsn & 0xff800000) == 0x91000000 &&
                  ((nextInsn >>> 5) & 0x1f) == rd) {
                final imm12 = (nextInsn >>> 10) & 0xfff;
                final shift = ((nextInsn >>> 22) & 0x1) == 1 ? 12 : 0;
                final fullAddr = targetPage + (imm12 << shift);
                resolvedCstring = cstringByAddr[fullAddr];
              }
            }

            if (resolvedCstring != null) {
              buffer.write('adrp,$regName,S:$resolvedCstring,');
            } else {
              final targetSect = _findSectionForPage(targetPage);
              if (targetSect != null) {
                final sectBasePage = targetSect.addr & ~0xfff;
                final pageDelta = targetPage - sectBasePage;
                buffer.write(
                  'adrp,$regName,${targetSect.fullName}'
                  '+0x${pageDelta.toRadixString(16)},',
                );
              } else {
                buffer.write(
                  'adrp,$regName,page(0x${targetPage.toRadixString(16)}),',
                );
              }
            }
          } else {
            buffer.write('insn,0x${insn.toRadixString(16).padLeft(8, '0')},');
          }
        }
      } else {
        // Non-ARM64 or unaligned slice: chunk into 4-byte or 1-byte words.
        var offset = 0;
        while (offset < funcSize) {
          startsList.add(buffer.length);
          addrsList.add(offset);
          if (offset + 4 <= funcSize) {
            final word = data.getUint32(byteStart + offset, Endian.little);
            buffer.write('word,0x${word.toRadixString(16).padLeft(8, '0')},');
            offset += 4;
          } else {
            final byte = text.bytes[byteStart + offset];
            buffer.write('byte,0x${byte.toRadixString(16).padLeft(2, '0')},');
            offset += 1;
          }
        }
      }

      functions.add(
        MachOFunction(
          name: funcNames[startAddr]!,
          address: startAddr,
          size: funcSize,
          isAnonymous: funcAnon[startAddr]!,
          canonicalInstructions: buffer.toString(),
          instructionStarts: Uint32List.fromList(startsList),
          instructionAddresses: Uint32List.fromList(addrsList),
        ),
      );
    }

    return functions;
  }

  MachOSection? _findSectionForPage(int pageAddr) {
    for (final s in sections) {
      final startPage = s.addr & ~0xfff;
      final endAddr = s.addr + (s.size > 0 ? s.size : 1);
      final endPage = (endAddr + 0xfff) & ~0xfff;
      if (pageAddr >= startPage && pageAddr < endPage) {
        return s;
      }
    }
    return null;
  }
}

/// {@template macho_parser}
/// Pure-Dart parser for thin 64-bit (`0xfeedfacf`) and Universal fat
/// (`0xcafebabe` / `0xcafebabf`) Mach-O binaries and companion `.dSYM` files.
/// {@endtemplate}
class MachOParser {
  /// {@macro macho_parser}
  const MachOParser();

  static const int _header64Size = 32;
  static const int _fatHeaderSize = 8;
  static const int _fatArch32Size = 20;
  static const int _fatArch64Size = 32;
  static const int _segment64CmdSize = 72;
  static const int _section64Size = 80;
  static const int _symtabCmdSize = 24;
  static const int _nlist64Size = 16;
  static const int _dysymtabCmdSize = 80;
  static const int _uuidCmdSize = 24;
  static const int _dylibCmdMinSize = 24;
  static const int _dyldInfoCmdSize = 48;
  static const int _linkeditDataCmdSize = 16;

  /// Returns `true` if [bytes] begins with a recognized Mach-O thin or
  /// Universal fat magic number.
  static bool isMachOBytes(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final data = ByteData.sublistView(bytes);
    final leMagic = data.getUint32(0, Endian.little);
    if (leMagic == MachOMagic.mhMagic64 || leMagic == MachOMagic.mhMagic32) {
      return true;
    }
    final beMagic = data.getUint32(0);
    return beMagic == MachOMagic.fatMagic || beMagic == MachOMagic.fatMagic64;
  }

  /// Parses [bytes] into a [MachOFile].
  ///
  /// Throws a [MachOFormatException] if [bytes] is truncated, corrupted, or
  /// not a supported Mach-O binary.
  MachOFile parse(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const MachOFormatException(
        'File too small to contain Mach-O magic',
      );
    }

    final data = ByteData.sublistView(bytes);
    final leMagic = data.getUint32(0, Endian.little);
    if (leMagic == MachOMagic.mhMagic64) {
      return MachOFile(
        slices: [_parseSlice(bytes)],
        isFat: false,
      );
    }

    final beMagic = data.getUint32(0);
    if (beMagic == MachOMagic.fatMagic || beMagic == MachOMagic.fatMagic64) {
      return _parseFat(bytes, is64BitFat: beMagic == MachOMagic.fatMagic64);
    }

    throw MachOFormatException(
      'Unsupported or unrecognized Mach-O magic: '
      '0x${beMagic.toRadixString(16).padLeft(8, '0')}',
    );
  }

  MachOFile _parseFat(Uint8List bytes, {required bool is64BitFat}) {
    if (bytes.length < _fatHeaderSize) {
      throw const MachOFormatException('Truncated fat_header');
    }
    final data = ByteData.sublistView(bytes);
    final nfatArch = data.getUint32(4);
    if (nfatArch == 0 || nfatArch > 64) {
      throw MachOFormatException('Invalid nfat_arch count: $nfatArch');
    }

    final archEntrySize = is64BitFat ? _fatArch64Size : _fatArch32Size;
    final tableEnd = _fatHeaderSize + nfatArch * archEntrySize;
    if (tableEnd > bytes.length) {
      throw const MachOFormatException(
        'fat_arch table extends past end of file',
      );
    }

    final slices = <MachOSlice>[];
    for (var i = 0; i < nfatArch; i++) {
      final entryOff = _fatHeaderSize + i * archEntrySize;
      final expectedCpuType = data.getUint32(entryOff);
      final expectedCpuSubtype = data.getUint32(entryOff + 4);
      final int sliceOff;
      final int sliceSize;
      if (is64BitFat) {
        sliceOff = data.getUint64(entryOff + 8);
        sliceSize = data.getUint64(entryOff + 16);
      } else {
        sliceOff = data.getUint32(entryOff + 8);
        sliceSize = data.getUint32(entryOff + 12);
      }

      if (sliceOff < tableEnd ||
          sliceSize < _header64Size ||
          sliceOff + sliceSize > bytes.length ||
          sliceOff + sliceSize < sliceOff) {
        throw MachOFormatException(
          'fat_arch[$i] slice range [$sliceOff..${sliceOff + sliceSize}) '
          'is out of bounds (file length ${bytes.length})',
        );
      }

      final sliceBytes = Uint8List.sublistView(
        bytes,
        sliceOff,
        sliceOff + sliceSize,
      );
      final slice = _parseSlice(sliceBytes);
      if (slice.header.cpuType != expectedCpuType ||
          slice.header.cpuSubtype != expectedCpuSubtype) {
        throw MachOFormatException(
          'fat_arch[$i] CPU type mismatch: fat header has '
          '(${expectedCpuType.toRadixString(16)}, '
          '${expectedCpuSubtype.toRadixString(16)}) but slice has '
          '(${slice.header.cpuType.toRadixString(16)}, '
          '${slice.header.cpuSubtype.toRadixString(16)})',
        );
      }
      slices.add(slice);
    }

    slices.sort((a, b) {
      final cmp = a.header.cpuType.compareTo(b.header.cpuType);
      return cmp != 0
          ? cmp
          : a.header.cpuSubtype.compareTo(b.header.cpuSubtype);
    });

    return MachOFile(slices: slices, isFat: true);
  }

  MachOSlice _parseSlice(Uint8List bytes) {
    if (bytes.length < _header64Size) {
      throw const MachOFormatException('Truncated mach_header_64');
    }
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint32(0, Endian.little);
    if (magic != MachOMagic.mhMagic64) {
      throw MachOFormatException(
        'Expected MH_MAGIC_64 (0xfeedfacf), got 0x${magic.toRadixString(16)}',
      );
    }

    final header = MachOHeader(
      cpuType: data.getUint32(4, Endian.little),
      cpuSubtype: data.getUint32(8, Endian.little),
      fileType: data.getUint32(12, Endian.little),
      ncmds: data.getUint32(16, Endian.little),
      sizeofcmds: data.getUint32(20, Endian.little),
      flags: data.getUint32(24, Endian.little),
    );

    final cmdsEnd = _header64Size + header.sizeofcmds;
    if (cmdsEnd > bytes.length || header.ncmds > 16384) {
      throw MachOFormatException(
        'Load commands extend past end of slice '
        '(cmdsEnd=$cmdsEnd, length=${bytes.length})',
      );
    }

    Uint8List? uuid;
    final segments = <MachOSegment>[];
    final allSections = <MachOSection>[];
    final dylibs = <MachODylib>[];

    int? symoff;
    int? nsyms;
    int? stroff;
    int? strsize;

    MachODysymtab? dysymtab;
    int? exportTrieOff;
    int? exportTrieSize;
    int? funcStartsOff;
    int? funcStartsSize;
    MachOCodeSignature? codeSignature;

    final semanticLinkeditRanges = <(int, int)>[];

    var cmdOffset = _header64Size;
    for (var i = 0; i < header.ncmds; i++) {
      if (cmdOffset + 8 > cmdsEnd) {
        throw MachOFormatException('Load command $i header truncated');
      }
      final cmd = data.getUint32(cmdOffset, Endian.little);
      final cmdsize = data.getUint32(cmdOffset + 4, Endian.little);
      if (cmdsize < 8 || cmdOffset + cmdsize > cmdsEnd) {
        throw MachOFormatException(
          'Load command $i has invalid cmdsize $cmdsize at offset $cmdOffset',
        );
      }

      switch (cmd) {
        case MachOLoadCommandType.segment64:
          final segment = _parseSegment64(bytes, data, cmdOffset, cmdsize);
          segments.add(segment);
          allSections.addAll(segment.sections);

        case MachOLoadCommandType.uuid:
          if (cmdsize < _uuidCmdSize) {
            throw const MachOFormatException('LC_UUID cmdsize < 24');
          }
          uuid = bytes.sublist(cmdOffset + 8, cmdOffset + 24);

        case MachOLoadCommandType.symtab:
          if (cmdsize < _symtabCmdSize) {
            throw const MachOFormatException('LC_SYMTAB cmdsize < 24');
          }
          symoff = data.getUint32(cmdOffset + 8, Endian.little);
          nsyms = data.getUint32(cmdOffset + 12, Endian.little);
          stroff = data.getUint32(cmdOffset + 16, Endian.little);
          strsize = data.getUint32(cmdOffset + 20, Endian.little);
          if (nsyms > 0) {
            semanticLinkeditRanges.add((symoff, symoff + nsyms * _nlist64Size));
          }
          if (strsize > 0) {
            semanticLinkeditRanges.add((stroff, stroff + strsize));
          }

        case MachOLoadCommandType.dysymtab:
          if (cmdsize < _dysymtabCmdSize) {
            throw const MachOFormatException('LC_DYSYMTAB cmdsize < 80');
          }
          dysymtab = _parseDysymtab(bytes, data, cmdOffset);
          if (dysymtab.nindirectsyms > 0) {
            semanticLinkeditRanges.add((
              dysymtab.indirectsymoff,
              dysymtab.indirectsymoff + dysymtab.nindirectsyms * 4,
            ));
          }

        case MachOLoadCommandType.loadDylib:
        case MachOLoadCommandType.loadWeakDylib:
        case MachOLoadCommandType.reexportDylib:
        case MachOLoadCommandType.lazyLoadDylib:
        case MachOLoadCommandType.loadUpwardDylib:
          dylibs.add(_parseDylib(bytes, data, cmdOffset, cmdsize, cmd));

        case MachOLoadCommandType.dyldInfo:
        case MachOLoadCommandType.dyldInfoOnly:
          if (cmdsize < _dyldInfoCmdSize) {
            throw const MachOFormatException('LC_DYLD_INFO cmdsize < 48');
          }
          for (var field = 0; field < 5; field++) {
            final off = data.getUint32(
              cmdOffset + 8 + field * 8,
              Endian.little,
            );
            final size = data.getUint32(
              cmdOffset + 12 + field * 8,
              Endian.little,
            );
            if (size > 0) {
              if (off + size > bytes.length || off + size < off) {
                throw const MachOFormatException(
                  'LC_DYLD_INFO range out of bounds',
                );
              }
              semanticLinkeditRanges.add((off, off + size));
            }
          }
          final expOff = data.getUint32(cmdOffset + 40, Endian.little);
          final expSize = data.getUint32(cmdOffset + 44, Endian.little);
          if (expSize > 0) {
            exportTrieOff = expOff;
            exportTrieSize = expSize;
          }

        case MachOLoadCommandType.dyldExportsTrie:
          if (cmdsize < _linkeditDataCmdSize) {
            throw const MachOFormatException(
              'LC_DYLD_EXPORTS_TRIE cmdsize < 16',
            );
          }
          final off = data.getUint32(cmdOffset + 8, Endian.little);
          final size = data.getUint32(cmdOffset + 12, Endian.little);
          if (size > 0) {
            exportTrieOff = off;
            exportTrieSize = size;
            semanticLinkeditRanges.add((off, off + size));
          }

        case MachOLoadCommandType.functionStarts:
          if (cmdsize < _linkeditDataCmdSize) {
            throw const MachOFormatException('LC_FUNCTION_STARTS cmdsize < 16');
          }
          funcStartsOff = data.getUint32(cmdOffset + 8, Endian.little);
          funcStartsSize = data.getUint32(cmdOffset + 12, Endian.little);
          if (funcStartsSize > 0) {
            semanticLinkeditRanges.add((
              funcStartsOff,
              funcStartsOff + funcStartsSize,
            ));
          }

        case MachOLoadCommandType.codeSignature:
          if (cmdsize < _linkeditDataCmdSize) {
            throw const MachOFormatException('LC_CODE_SIGNATURE cmdsize < 16');
          }
          final sigOff = data.getUint32(cmdOffset + 8, Endian.little);
          final sigSize = data.getUint32(cmdOffset + 12, Endian.little);
          if (sigOff + sigSize > bytes.length || sigOff + sigSize < sigOff) {
            throw const MachOFormatException(
              'LC_CODE_SIGNATURE range out of bounds',
            );
          }
          codeSignature = MachOCodeSignature(
            dataoff: sigOff,
            datasize: sigSize,
            bytes: bytes.sublist(sigOff, sigOff + sigSize),
          );
      }

      cmdOffset += cmdsize;
    }

    final symbols = symoff != null && nsyms != null && stroff != null
        ? _parseSymtab(
            bytes,
            data,
            symoff: symoff,
            nsyms: nsyms,
            stroff: stroff,
            strsize: strsize!,
            sections: allSections,
          )
        : const <MachOSymbol>[];

    final exportedSymbols =
        exportTrieOff != null && exportTrieSize != null && exportTrieSize > 0
        ? _parseExportTrie(bytes, exportTrieOff, exportTrieSize)
        : const <MachOExportedSymbol>[];

    var textVmaddr = 0;
    for (final seg in segments) {
      if (seg.name == '__TEXT') {
        textVmaddr = seg.vmaddr;
        break;
      }
    }

    final functionStarts =
        funcStartsOff != null && funcStartsSize != null && funcStartsSize > 0
        ? _parseFunctionStarts(bytes, funcStartsOff, funcStartsSize, textVmaddr)
        : const <int>[];

    final objcClassNames = <String>[];
    final objcSelectors = <String>[];
    final swiftSections = <String, Uint8List>{};
    final cstrings = <String>[];
    final constSections = <String, Uint8List>{};
    final dwarfCompilePaths = <String>[];

    for (final sym in symbols) {
      if (sym.isDebugStab &&
          (sym.nType == MachOSymbolType.nOso ||
              sym.nType == MachOSymbolType.nSo ||
              sym.nType == MachOSymbolType.nSol) &&
          sym.name.isNotEmpty) {
        dwarfCompilePaths.add(sym.name);
      }
    }

    for (final section in allSections) {
      if (section.sectname == '__objc_classname') {
        objcClassNames.addAll(_extractNullTerminatedStrings(section.bytes));
      } else if (section.sectname == '__objc_methname') {
        objcSelectors.addAll(_extractNullTerminatedStrings(section.bytes));
      } else if (section.sectname.startsWith('__swift5_')) {
        swiftSections[section.fullName] = section.bytes;
      } else if (section.segname == '__TEXT' &&
          section.sectname == '__cstring') {
        cstrings.addAll(_extractNullTerminatedStrings(section.bytes));
      } else if (section.sectname == '__const' ||
          (section.segname == '__DATA' && section.sectname == '__data')) {
        constSections[section.fullName] = section.bytes;
      } else if (section.segname == '__DWARF' &&
          (section.sectname == '__debug_str' ||
              section.sectname == '__debug_line_str')) {
        for (final s in _extractNullTerminatedStrings(section.bytes)) {
          if (s.startsWith('/') || s.contains('/')) {
            dwarfCompilePaths.add(s);
          }
        }
      }
    }

    final stubTargetNames = _resolveStubTargets(
      sections: allSections,
      symbols: symbols,
      dysymtab: dysymtab,
    );

    final referencedSymbols = _scanReferencedSymbols(
      sections: allSections,
      symbols: symbols,
      stubTargetNames: stubTargetNames,
      cpuType: header.cpuType,
    );

    final linkeditPaddingBytes = _extractLinkeditPadding(
      bytes: bytes,
      segments: segments,
      semanticRanges: semanticLinkeditRanges,
      codeSignature: codeSignature,
    );

    return MachOSlice(
      header: header,
      uuid: uuid,
      segments: segments,
      sections: allSections,
      symbols: symbols,
      dysymtab: dysymtab,
      exportedSymbols: exportedSymbols,
      dylibs: dylibs,
      functionStarts: functionStarts,
      codeSignature: codeSignature,
      linkeditPaddingBytes: linkeditPaddingBytes,
      objcClassNames: objcClassNames,
      objcSelectors: objcSelectors,
      swiftSections: swiftSections,
      cstrings: cstrings,
      constSections: constSections,
      dwarfCompilePaths: dwarfCompilePaths,
      stubTargetNames: stubTargetNames,
      referencedSymbols: referencedSymbols,
    );
  }

  MachOSegment _parseSegment64(
    Uint8List bytes,
    ByteData data,
    int cmdOffset,
    int cmdsize,
  ) {
    if (cmdsize < _segment64CmdSize) {
      throw const MachOFormatException('LC_SEGMENT_64 cmdsize < 72');
    }
    final segname = _readFixedString(bytes, cmdOffset + 8, 16);
    final vmaddr = data.getUint64(cmdOffset + 24, Endian.little);
    final vmsize = data.getUint64(cmdOffset + 32, Endian.little);
    final fileoff = data.getUint64(cmdOffset + 40, Endian.little);
    final filesize = data.getUint64(cmdOffset + 48, Endian.little);
    final maxprot = data.getUint32(cmdOffset + 56, Endian.little);
    final initprot = data.getUint32(cmdOffset + 60, Endian.little);
    final nsects = data.getUint32(cmdOffset + 64, Endian.little);
    final flags = data.getUint32(cmdOffset + 68, Endian.little);

    if (filesize > 0 &&
        (fileoff + filesize > bytes.length || fileoff + filesize < fileoff)) {
      throw MachOFormatException(
        'Segment $segname file range [$fileoff..${fileoff + filesize}) '
        'exceeds file length ${bytes.length}',
      );
    }

    final expectedSize = _segment64CmdSize + nsects * _section64Size;
    if (expectedSize > cmdsize) {
      throw MachOFormatException(
        'Segment $segname with $nsects sections requires $expectedSize bytes, '
        'but cmdsize is $cmdsize',
      );
    }

    final sections = <MachOSection>[];
    for (var i = 0; i < nsects; i++) {
      final sectOff = cmdOffset + _segment64CmdSize + i * _section64Size;
      final sectname = _readFixedString(bytes, sectOff, 16);
      final sectSegname = _readFixedString(bytes, sectOff + 16, 16);
      final addr = data.getUint64(sectOff + 32, Endian.little);
      final size = data.getUint64(sectOff + 40, Endian.little);
      final offset = data.getUint32(sectOff + 48, Endian.little);
      final align = data.getUint32(sectOff + 52, Endian.little);
      final reloff = data.getUint32(sectOff + 56, Endian.little);
      final nreloc = data.getUint32(sectOff + 60, Endian.little);
      final sectFlags = data.getUint32(sectOff + 64, Endian.little);
      final reserved1 = data.getUint32(sectOff + 68, Endian.little);
      final reserved2 = data.getUint32(sectOff + 72, Endian.little);
      final reserved3 = data.getUint32(sectOff + 76, Endian.little);

      final sectType = sectFlags & 0xff;
      final isZeroFill =
          sectType == MachOSectionType.zerofill ||
          sectType == MachOSectionType.gbZerofill ||
          (filesize == 0 && offset == 0);

      Uint8List sectBytes;
      if (isZeroFill || size == 0) {
        sectBytes = Uint8List(0);
      } else {
        if (offset + size > bytes.length || offset + size < offset) {
          throw MachOFormatException(
            'Section $sectSegname,$sectname range [$offset..${offset + size}) '
            'exceeds file length ${bytes.length}',
          );
        }
        sectBytes = bytes.sublist(offset, offset + size);
      }

      sections.add(
        MachOSection(
          segname: sectSegname,
          sectname: sectname,
          addr: addr,
          size: size,
          offset: offset,
          align: align,
          reloff: reloff,
          nreloc: nreloc,
          flags: sectFlags,
          reserved1: reserved1,
          reserved2: reserved2,
          reserved3: reserved3,
          bytes: sectBytes,
        ),
      );
    }

    return MachOSegment(
      name: segname,
      vmaddr: vmaddr,
      vmsize: vmsize,
      fileoff: fileoff,
      filesize: filesize,
      maxprot: maxprot,
      initprot: initprot,
      flags: flags,
      sections: sections,
    );
  }

  List<MachOSymbol> _parseSymtab(
    Uint8List bytes,
    ByteData data, {
    required int symoff,
    required int nsyms,
    required int stroff,
    required int strsize,
    required List<MachOSection> sections,
  }) {
    if (nsyms > 1000000) {
      throw MachOFormatException('Excessive nsyms count: $nsyms');
    }
    final symEnd = symoff + nsyms * _nlist64Size;
    final strEnd = stroff + strsize;
    if (symEnd > bytes.length ||
        symEnd < symoff ||
        strEnd > bytes.length ||
        strEnd < stroff) {
      throw const MachOFormatException(
        'LC_SYMTAB symbol or string table extends past end of file',
      );
    }

    final symbols = <MachOSymbol>[];
    for (var i = 0; i < nsyms; i++) {
      final entryOff = symoff + i * _nlist64Size;
      final nStrx = data.getUint32(entryOff, Endian.little);
      final nType = bytes[entryOff + 4];
      final nSect = bytes[entryOff + 5];
      final nDesc = data.getUint16(entryOff + 6, Endian.little);
      final nValue = data.getUint64(entryOff + 8, Endian.little);

      if (nStrx >= strsize && strsize > 0) {
        throw MachOFormatException(
          'Symbol $i string index $nStrx exceeds strsize $strsize',
        );
      }

      final name = strsize == 0
          ? ''
          : _readNullTerminatedString(bytes, stroff + nStrx, strEnd);

      String? sectionName;
      if (nSect >= 1 && nSect <= sections.length) {
        sectionName = sections[nSect - 1].fullName;
      }

      symbols.add(
        MachOSymbol(
          name: name,
          nType: nType,
          nSect: nSect,
          nDesc: nDesc,
          nValue: nValue,
          sectionName: sectionName,
        ),
      );
    }
    return symbols;
  }

  MachODysymtab _parseDysymtab(Uint8List bytes, ByteData data, int cmdOffset) {
    final ilocalsym = data.getUint32(cmdOffset + 8, Endian.little);
    final nlocalsym = data.getUint32(cmdOffset + 12, Endian.little);
    final iextdefsym = data.getUint32(cmdOffset + 16, Endian.little);
    final nextdefsym = data.getUint32(cmdOffset + 20, Endian.little);
    final iundefsym = data.getUint32(cmdOffset + 24, Endian.little);
    final nundefsym = data.getUint32(cmdOffset + 28, Endian.little);
    final indirectsymoff = data.getUint32(cmdOffset + 56, Endian.little);
    final nindirectsyms = data.getUint32(cmdOffset + 60, Endian.little);

    if (nindirectsyms > 1000000) {
      throw MachOFormatException(
        'Excessive nindirectsyms count: $nindirectsyms',
      );
    }
    final indirectEnd = indirectsymoff + nindirectsyms * 4;
    if (nindirectsyms > 0 &&
        (indirectEnd > bytes.length || indirectEnd < indirectsymoff)) {
      throw const MachOFormatException(
        'LC_DYSYMTAB indirect symbol table extends past end of file',
      );
    }

    final indirectSymbols = Uint32List(nindirectsyms);
    for (var i = 0; i < nindirectsyms; i++) {
      indirectSymbols[i] = data.getUint32(
        indirectsymoff + i * 4,
        Endian.little,
      );
    }

    return MachODysymtab(
      ilocalsym: ilocalsym,
      nlocalsym: nlocalsym,
      iextdefsym: iextdefsym,
      nextdefsym: nextdefsym,
      iundefsym: iundefsym,
      nundefsym: nundefsym,
      indirectsymoff: indirectsymoff,
      nindirectsyms: nindirectsyms,
      indirectSymbols: indirectSymbols,
    );
  }

  MachODylib _parseDylib(
    Uint8List bytes,
    ByteData data,
    int cmdOffset,
    int cmdsize,
    int cmd,
  ) {
    if (cmdsize < _dylibCmdMinSize) {
      throw const MachOFormatException('dylib_command cmdsize < 24');
    }
    final nameOffset = data.getUint32(cmdOffset + 8, Endian.little);
    if (nameOffset < _dylibCmdMinSize || nameOffset >= cmdsize) {
      throw MachOFormatException(
        'dylib_command name offset $nameOffset out of bounds '
        '(cmdsize=$cmdsize)',
      );
    }
    final timestamp = data.getUint32(cmdOffset + 12, Endian.little);
    final currentVersion = data.getUint32(cmdOffset + 16, Endian.little);
    final compatibilityVersion = data.getUint32(cmdOffset + 20, Endian.little);
    final name = _readNullTerminatedString(
      bytes,
      cmdOffset + nameOffset,
      cmdOffset + cmdsize,
    );

    return MachODylib(
      name: name,
      cmd: cmd,
      timestamp: timestamp,
      currentVersion: currentVersion,
      compatibilityVersion: compatibilityVersion,
    );
  }

  List<MachOExportedSymbol> _parseExportTrie(
    Uint8List bytes,
    int trieOff,
    int trieSize,
  ) {
    final trieEnd = trieOff + trieSize;
    if (trieEnd > bytes.length || trieEnd < trieOff) {
      throw const MachOFormatException(
        'Export trie extends past end of file',
      );
    }

    final exports = <MachOExportedSymbol>[];
    final visited = <int>{};

    void walk(int nodeRelOff, String prefix) {
      if (nodeRelOff < 0 || nodeRelOff >= trieSize) {
        throw MachOFormatException(
          'Export trie child offset $nodeRelOff out of bounds (size=$trieSize)',
        );
      }
      if (!visited.add(nodeRelOff)) {
        throw MachOFormatException(
          'Cycle or duplicate node detected in export trie at offset '
          '$nodeRelOff',
        );
      }

      var cursor = trieOff + nodeRelOff;
      final (terminalSize, afterTermSize) = _readUleb128(
        bytes,
        cursor,
        trieEnd,
      );
      cursor = afterTermSize;

      if (terminalSize > 0) {
        final termEnd = cursor + terminalSize;
        if (termEnd > trieEnd) {
          throw const MachOFormatException(
            'Export trie terminal node extends past end of trie',
          );
        }
        var termCursor = cursor;
        final (flags, afterFlags) = _readUleb128(bytes, termCursor, termEnd);
        termCursor = afterFlags;

        if ((flags & 0x08) != 0) {
          // EXPORT_SYMBOL_FLAGS_REEXPORT
          final (ordinal, afterOrd) = _readUleb128(bytes, termCursor, termEnd);
          termCursor = afterOrd;
          final imported = _readNullTerminatedString(
            bytes,
            termCursor,
            termEnd,
          );
          exports.add(
            MachOExportedSymbol(
              name: prefix,
              flags: flags,
              offset: 0,
              reexportOrdinal: ordinal,
              importedName: imported.isEmpty ? prefix : imported,
            ),
          );
        } else if ((flags & 0x10) != 0) {
          // EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER
          final (stubOff, afterStub) = _readUleb128(bytes, termCursor, termEnd);
          termCursor = afterStub;
          final (_, _) = _readUleb128(bytes, termCursor, termEnd);
          exports.add(
            MachOExportedSymbol(
              name: prefix,
              flags: flags,
              offset: stubOff,
            ),
          );
        } else {
          final (symOff, _) = _readUleb128(bytes, termCursor, termEnd);
          exports.add(
            MachOExportedSymbol(
              name: prefix,
              flags: flags,
              offset: symOff,
            ),
          );
        }
        cursor = termEnd;
      }

      if (cursor >= trieEnd) {
        throw const MachOFormatException(
          'Unexpected end of export trie reading child count',
        );
      }
      final childCount = bytes[cursor++];
      for (var i = 0; i < childCount; i++) {
        final nulIndex = _findNullByte(bytes, cursor, trieEnd);
        if (nulIndex < 0) {
          throw const MachOFormatException(
            'Unterminated edge string in export trie',
          );
        }
        final edgeLabel = utf8.decode(
          bytes.sublist(cursor, nulIndex),
          allowMalformed: true,
        );
        cursor = nulIndex + 1;
        final (childOff, afterChildOff) = _readUleb128(bytes, cursor, trieEnd);
        cursor = afterChildOff;
        walk(childOff, '$prefix$edgeLabel');
      }
    }

    walk(0, '');
    exports.sort((a, b) => a.name.compareTo(b.name));
    return exports;
  }

  List<int> _parseFunctionStarts(
    Uint8List bytes,
    int dataOff,
    int dataSize,
    int textVmaddr,
  ) {
    final end = dataOff + dataSize;
    if (end > bytes.length || end < dataOff) {
      throw const MachOFormatException(
        'LC_FUNCTION_STARTS extends past end of file',
      );
    }

    final starts = <int>[];
    var addr = textVmaddr;
    var cursor = dataOff;
    while (cursor < end) {
      final (delta, nextCursor) = _readUleb128(bytes, cursor, end);
      cursor = nextCursor;
      if (delta == 0) continue;
      addr += delta;
      starts.add(addr);
    }
    return starts;
  }

  Map<int, String> _resolveStubTargets({
    required List<MachOSection> sections,
    required List<MachOSymbol> symbols,
    required MachODysymtab? dysymtab,
  }) {
    if (dysymtab == null || dysymtab.indirectSymbols.isEmpty) {
      return const {};
    }
    final result = <int, String>{};
    for (final section in sections) {
      final isStubSection =
          section.sectionType == MachOSectionType.symbolStubs ||
          section.sectname == '__stubs' ||
          section.sectname == '__auth_stubs';
      if (!isStubSection) continue;
      final stubSize = section.reserved2 > 0 ? section.reserved2 : 12;
      if (section.size == 0 || stubSize == 0) continue;
      final stubCount = section.size ~/ stubSize;
      final indirectStart = section.reserved1;
      for (var i = 0; i < stubCount; i++) {
        final indirectIndex = indirectStart + i;
        if (indirectIndex >= dysymtab.indirectSymbols.length) break;
        final symIndex = dysymtab.indirectSymbols[indirectIndex];
        if (symIndex == MachOSymbolType.indirectSymbolLocal ||
            symIndex == MachOSymbolType.indirectSymbolAbs ||
            symIndex >= symbols.length) {
          continue;
        }
        final stubAddr = section.addr + i * stubSize;
        result[stubAddr] = symbols[symIndex].name;
      }
    }
    return result;
  }

  Set<String> _scanReferencedSymbols({
    required List<MachOSection> sections,
    required List<MachOSymbol> symbols,
    required Map<int, String> stubTargetNames,
    required int cpuType,
  }) {
    if (cpuType != MachOCpuType.arm64) return const {};
    MachOSection? text;
    for (final s in sections) {
      if (s.segname == '__TEXT' && s.sectname == '__text') {
        text = s;
        break;
      }
    }
    if (text == null || text.bytes.length < 4) return const {};

    final symByAddr = <int, String>{
      for (final s in symbols)
        if (s.isDefinedInSection && s.name.isNotEmpty) s.nValue: s.name,
    };

    final referenced = <String>{};
    final data = ByteData.sublistView(text.bytes);
    final insnCount = text.bytes.length ~/ 4;
    for (var i = 0; i < insnCount; i++) {
      final insn = data.getUint32(i * 4, Endian.little);
      final op6 = insn >>> 26;
      if (op6 == 0x05 || op6 == 0x25) {
        final imm26 = insn & 0x03ffffff;
        final signedImm26 = (imm26 & 0x02000000) != 0
            ? (imm26 | ~0x03ffffff)
            : imm26;
        final targetAddr = text.addr + i * 4 + signedImm26 * 4;
        final stubSym = stubTargetNames[targetAddr];
        if (stubSym != null) {
          referenced.add(stubSym);
        } else {
          final directSym = symByAddr[targetAddr];
          if (directSym != null) {
            referenced.add(directSym);
          }
        }
      }
    }
    return referenced;
  }

  Uint8List _extractLinkeditPadding({
    required Uint8List bytes,
    required List<MachOSegment> segments,
    required List<(int, int)> semanticRanges,
    required MachOCodeSignature? codeSignature,
  }) {
    MachOSegment? linkedit;
    for (final seg in segments) {
      if (seg.name == '__LINKEDIT') {
        linkedit = seg;
        break;
      }
    }
    if (linkedit == null || linkedit.filesize == 0) {
      return codeSignature?.bytes ?? Uint8List(0);
    }

    final start = linkedit.fileoff;
    final end = (start + linkedit.filesize).clamp(0, bytes.length);

    // Collect every byte inside __LINKEDIT that is not covered by a semantic
    // table (symtab, strtab, dysymtab indirects, dyld info/exports, function
    // starts). This includes alignment padding and LC_CODE_SIGNATURE bytes.
    final mask = Uint8List(end - start);
    for (final (rStart, rEnd) in semanticRanges) {
      final clampedStart = (rStart - start).clamp(0, end - start);
      final clampedEnd = (rEnd - start).clamp(0, end - start);
      for (var i = clampedStart; i < clampedEnd; i++) {
        mask[i] = 1;
      }
    }

    final padding = BytesBuilder(copy: false);
    for (var i = 0; i < end - start; i++) {
      if (mask[i] == 0) {
        padding.addByte(bytes[start + i]);
      }
    }
    return padding.takeBytes();
  }

  static (int, int) _readUleb128(Uint8List bytes, int offset, int end) {
    var result = 0;
    var shift = 0;
    var cursor = offset;
    while (true) {
      if (cursor >= end) {
        throw const MachOFormatException('Truncated ULEB128 integer');
      }
      final byte = bytes[cursor++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return (result, cursor);
      }
      shift += 7;
      if (shift > 63) {
        throw const MachOFormatException('ULEB128 integer overflow (>64 bits)');
      }
    }
  }

  static String _readFixedString(Uint8List bytes, int offset, int length) {
    var end = offset;
    final limit = offset + length;
    while (end < limit && bytes[end] != 0) {
      end++;
    }
    return utf8.decode(bytes.sublist(offset, end), allowMalformed: true);
  }

  static String _readNullTerminatedString(
    Uint8List bytes,
    int offset,
    int limit,
  ) {
    var end = offset;
    while (end < limit && bytes[end] != 0) {
      end++;
    }
    return utf8.decode(bytes.sublist(offset, end), allowMalformed: true);
  }

  static int _findNullByte(Uint8List bytes, int offset, int limit) {
    for (var i = offset; i < limit; i++) {
      if (bytes[i] == 0) return i;
    }
    return -1;
  }

  static List<String> _extractNullTerminatedStrings(Uint8List bytes) {
    if (bytes.isEmpty) return const [];
    final strings = <String>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) {
        if (i > start) {
          strings.add(
            utf8.decode(bytes.sublist(start, i), allowMalformed: true),
          );
        }
        start = i + 1;
      }
    }
    if (start < bytes.length) {
      strings.add(
        utf8.decode(bytes.sublist(start), allowMalformed: true),
      );
    }
    return strings;
  }
}
