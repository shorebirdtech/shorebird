// cspell:words aarch abiversion addralign addrs adrp debuglink descsz dynstr
// cspell:words dynsym ehdr ehsize elfclass elfdata entsize execinstr fini
// cspell:words ifunc immhi immlo insn insns loreserve namesz nobits notype
// cspell:words osabi phdr phentsize phnum phoff preemptable progbits rela
// cspell:words riscv rodata shdr shentsize shndx shnum shoff shstrndx shstrtab
// cspell:words soname strtab symtab undef
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Exception thrown when an ELF binary is malformed, truncated, or uses an
/// unsupported header format.
class ElfFormatException extends FormatException {
  /// Creates an [ElfFormatException] with the given [message].
  const ElfFormatException(super.message);
}

/// Magic number identifying ELF binaries (`\x7fELF`).
abstract final class ElfMagic {
  /// Big-endian 32-bit representation of `\x7fELF` (`0x7f454c46`).
  static const int magic = 0x7f454c46;
}

/// ELF file class constants (`e_ident[EI_CLASS]`).
abstract final class ElfClass {
  /// 32-bit ELF (`ELFCLASS32`).
  static const int elfClass32 = 1;

  /// 64-bit ELF (`ELFCLASS64`).
  static const int elfClass64 = 2;
}

/// ELF data encoding constants (`e_ident[EI_DATA]`).
abstract final class ElfData {
  /// Two's complement, little-endian (`ELFDATA2LSB`).
  static const int lsb = 1;

  /// Two's complement, big-endian (`ELFDATA2MSB`).
  static const int msb = 2;
}

/// ELF object file type constants (`e_type`).
abstract final class ElfFileType {
  /// Relocatable file (`ET_REL`).
  static const int rel = 1;

  /// Executable file (`ET_EXEC`).
  static const int exec = 2;

  /// Shared object file (`ET_DYN`).
  static const int dyn = 3;

  /// Core file (`ET_CORE`).
  static const int core = 4;
}

/// ELF machine architecture constants (`e_machine`).
abstract final class ElfMachine {
  /// Intel 80386 (`EM_386`).
  static const int x86 = 3;

  /// ARM 32-bit (`EM_ARM`).
  static const int arm = 40;

  /// AMD x86-64 (`EM_X86_64`).
  static const int x86_64 = 62;

  /// ARM 64-bit (`EM_AARCH64`).
  static const int aarch64 = 183;

  /// RISC-V (`EM_RISCV`).
  static const int riscv = 243;
}

/// ELF section header type constants (`sh_type`).
abstract final class ElfSectionType {
  /// Inactive section header (`SHT_NULL`).
  static const int shtNull = 0;

  /// Program-defined information (`SHT_PROGBITS`).
  static const int progbits = 1;

  /// Static symbol table (`SHT_SYMTAB`).
  static const int symtab = 2;

  /// String table (`SHT_STRTAB`).
  static const int strtab = 3;

  /// Relocation entries with explicit addends (`SHT_RELA`).
  static const int rela = 4;

  /// Symbol hash table (`SHT_HASH`).
  static const int hash = 5;

  /// Dynamic linking information (`SHT_DYNAMIC`).
  static const int dynamicSection = 6;

  /// Note information (`SHT_NOTE`).
  static const int note = 7;

  /// Uninitialized space occupying no file bytes (`SHT_NOBITS`, e.g. `.bss`).
  static const int nobits = 8;

  /// Relocation entries without explicit addends (`SHT_REL`).
  static const int rel = 9;

  /// Dynamic linker symbol table (`SHT_DYNSYM`).
  static const int dynsym = 11;
}

/// ELF section attribute flag bits (`sh_flags`).
abstract final class ElfSectionFlags {
  /// Writable during execution (`SHF_WRITE`).
  static const int write = 0x1;

  /// Occupies memory during execution (`SHF_ALLOC`).
  static const int alloc = 0x2;

  /// Executable machine instructions (`SHF_EXECINSTR`).
  static const int execinstr = 0x4;
}

/// Special ELF section header indices (`st_shndx`).
abstract final class ElfSectionIndex {
  /// Undefined symbol reference (`SHN_UNDEF`).
  static const int undef = 0;

  /// Start of reserved section index range (`SHN_LORESERVE`).
  static const int loreserve = 0xff00;

  /// Absolute symbol value not affected by relocation (`SHN_ABS`).
  static const int abs = 0xfff1;

  /// Common unallocated block (`SHN_COMMON`).
  static const int common = 0xfff2;
}

/// ELF symbol binding constants (`ELF_ST_BIND(st_info)`).
abstract final class ElfSymbolBinding {
  /// Local symbol (`STB_LOCAL`).
  static const int local = 0;

  /// Global symbol (`STB_GLOBAL`).
  static const int global = 1;

  /// Weak symbol (`STB_WEAK`).
  static const int weak = 2;
}

/// ELF symbol type constants (`ELF_ST_TYPE(st_info)`).
abstract final class ElfSymbolType {
  /// Unspecified symbol type (`STT_NOTYPE`).
  static const int notype = 0;

  /// Data object such as a variable or array (`STT_OBJECT`).
  static const int object = 1;

  /// Function or executable code (`STT_FUNC`).
  static const int func = 2;

  /// Section symbol (`STT_SECTION`).
  static const int section = 3;

  /// Source file symbol (`STT_FILE`).
  static const int file = 4;

  /// Uninitialized common block (`STT_COMMON`).
  static const int common = 5;

  /// Thread-local storage entity (`STT_TLS`).
  static const int tls = 6;

  /// Indirect function resolved at runtime (`STT_GNU_IFUNC`).
  static const int gnuIfunc = 10;
}

/// ELF symbol visibility constants (`ELF_ST_VISIBILITY(st_other)`).
abstract final class ElfSymbolVisibility {
  /// Default visibility (`STV_DEFAULT`).
  static const int defaultVisibility = 0;

  /// Processor-specific hidden class (`STV_INTERNAL`).
  static const int internal = 1;

  /// Invisible to other components (`STV_HIDDEN`).
  static const int hidden = 2;

  /// Visible in other components but not preemptable (`STV_PROTECTED`).
  static const int protectedVisibility = 3;
}

/// ELF `.dynamic` tag constants (`d_tag`).
abstract final class ElfDynamicTag {
  /// Marks end of `.dynamic` array (`DT_NULL`).
  static const int dtNull = 0;

  /// String table offset of a needed shared library name (`DT_NEEDED`).
  static const int needed = 1;

  /// String table offset of shared object name (`DT_SONAME`).
  static const int soname = 14;
}

/// {@template elf_header}
/// Parsed ELF32 or ELF64 file header (`Elf32_Ehdr` / `Elf64_Ehdr`).
/// {@endtemplate}
@immutable
class ElfHeader {
  /// {@macro elf_header}
  const ElfHeader({
    required this.elfClass,
    required this.dataEncoding,
    required this.osAbi,
    required this.abiVersion,
    required this.fileType,
    required this.machine,
    required this.version,
    required this.entry,
    required this.phoff,
    required this.shoff,
    required this.flags,
    required this.ehsize,
    required this.phentsize,
    required this.phnum,
    required this.shentsize,
    required this.shnum,
    required this.shstrndx,
  });

  /// Address class (`ElfClass.elfClass32` or `ElfClass.elfClass64`).
  final int elfClass;

  /// Byte order encoding (`ElfData.lsb` or `ElfData.msb`).
  final int dataEncoding;

  /// OS/ABI identification (`e_ident[EI_OSABI]`).
  final int osAbi;

  /// ABI version (`e_ident[EI_ABIVERSION]`).
  final int abiVersion;

  /// Object file type (`e_type`, e.g. `ElfFileType.dyn`).
  final int fileType;

  /// Target instruction set architecture (`e_machine`, e.g.
  /// `ElfMachine.aarch64`).
  final int machine;

  /// Object file version (`e_version`).
  final int version;

  /// Virtual address of the entry point (`e_entry`).
  final int entry;

  /// Program header table file offset (`e_phoff`).
  final int phoff;

  /// Section header table file offset (`e_shoff`).
  final int shoff;

  /// Processor-specific flags (`e_flags`).
  final int flags;

  /// ELF header size in bytes (`e_ehsize`).
  final int ehsize;

  /// Program header table entry size (`e_phentsize`).
  final int phentsize;

  /// Number of program header entries (`e_phnum`).
  final int phnum;

  /// Section header table entry size (`e_shentsize`).
  final int shentsize;

  /// Number of section header entries (`e_shnum`).
  final int shnum;

  /// Section header table index of the section name string table
  /// (`e_shstrndx`).
  final int shstrndx;

  /// Whether this is a 64-bit ELF binary (`ELFCLASS64`).
  bool get is64Bit => elfClass == ElfClass.elfClass64;

  /// Whether this binary uses little-endian byte order (`ELFDATA2LSB`).
  bool get isLittleEndian => dataEncoding == ElfData.lsb;

  /// Byte endianness used across this ELF binary.
  Endian get endian => isLittleEndian ? Endian.little : Endian.big;
}

/// {@template elf_section}
/// A parsed ELF32 or ELF64 section header (`Elf32_Shdr` / `Elf64_Shdr`) and
/// its file payload.
/// {@endtemplate}
@immutable
class ElfSection {
  /// {@macro elf_section}
  const ElfSection({
    required this.name,
    required this.nameOffset,
    required this.type,
    required this.flags,
    required this.addr,
    required this.offset,
    required this.size,
    required this.link,
    required this.info,
    required this.addralign,
    required this.entsize,
    required this.bytes,
  });

  /// Resolved section name from `.shstrtab` (e.g. `.text`, `.dynsym`).
  final String name;

  /// Byte offset into `.shstrtab` (`sh_name`).
  final int nameOffset;

  /// Section type (`sh_type`).
  final int type;

  /// Section attribute flags (`sh_flags`).
  final int flags;

  /// Virtual memory address (`sh_addr`).
  final int addr;

  /// File byte offset (`sh_offset`).
  final int offset;

  /// Section byte size (`sh_size`).
  final int size;

  /// Associated section header index (`sh_link`).
  final int link;

  /// Extra section information (`sh_info`).
  final int info;

  /// Address alignment constraint (`sh_addralign`).
  final int addralign;

  /// Entry size if the section holds a fixed-size table (`sh_entsize`).
  final int entsize;

  /// Raw section payload bytes (empty for `SHT_NOBITS` or zero-size sections).
  final Uint8List bytes;

  /// Whether this section occupies no bytes in the file (`SHT_NOBITS`).
  bool get isNoBits => type == ElfSectionType.nobits;

  /// Whether this section contains executable instructions (`SHF_EXECINSTR`).
  bool get isExecutable => (flags & ElfSectionFlags.execinstr) != 0;

  /// Whether this section contains writable data (`SHF_WRITE`).
  bool get isWritable => (flags & ElfSectionFlags.write) != 0;
}

/// {@template elf_symbol}
/// A parsed symbol table entry (`Elf32_Sym` / `Elf64_Sym`) from `.dynsym` or
/// `.symtab`.
/// {@endtemplate}
@immutable
class ElfSymbol {
  /// {@macro elf_symbol}
  const ElfSymbol({
    required this.name,
    required this.value,
    required this.size,
    required this.info,
    required this.other,
    required this.shndx,
    this.sectionName,
  });

  /// Symbol name resolved from `.dynstr` or `.strtab`.
  final String name;

  /// Symbol value / virtual address (`st_value`).
  final int value;

  /// Symbol byte size (`st_size`).
  final int size;

  /// Packed symbol binding and type byte (`st_info`).
  final int info;

  /// Symbol visibility byte (`st_other`).
  final int other;

  /// Defining section header index (`st_shndx`).
  final int shndx;

  /// Resolved defining section name (e.g. `.text`, `.rodata`, `.data`), or
  /// `null` for `SHN_UNDEF` / special indices.
  final String? sectionName;

  /// Symbol binding (`st_info >>> 4`, e.g. `ElfSymbolBinding.global`).
  int get binding => info >>> 4;

  /// Symbol type (`st_info & 0x0f`, e.g. `ElfSymbolType.func`).
  int get type => info & 0x0f;

  /// Symbol visibility (`st_other & 0x03`, e.g.
  /// `ElfSymbolVisibility.defaultVisibility`).
  int get visibility => other & 0x03;

  /// Whether this symbol is an imported/undefined reference (`SHN_UNDEF`).
  bool get isUndefined => shndx == ElfSectionIndex.undef;

  /// Whether this symbol has local binding (`STB_LOCAL`).
  bool get isLocal => binding == ElfSymbolBinding.local;

  /// Whether this symbol has global binding (`STB_GLOBAL`).
  bool get isGlobal => binding == ElfSymbolBinding.global;

  /// Whether this symbol has weak binding (`STB_WEAK`).
  bool get isWeak => binding == ElfSymbolBinding.weak;

  /// Whether this symbol is defined and externally visible to dynamic callers.
  bool get isExported =>
      !isUndefined &&
      (isGlobal || isWeak) &&
      (visibility == ElfSymbolVisibility.defaultVisibility ||
          visibility == ElfSymbolVisibility.protectedVisibility);

  /// Whether this symbol is a function (`STT_FUNC` or `STT_GNU_IFUNC`).
  bool get isFunction =>
      type == ElfSymbolType.func || type == ElfSymbolType.gnuIfunc;

  /// Packs [binding] and [type] into an ELF `st_info` byte.
  static int packInfo(int binding, int type) =>
      ((binding & 0x0f) << 4) | (type & 0x0f);
}

/// {@template elf_canonical_instruction}
/// A single canonicalized instruction or word within an ELF `.text` function.
/// {@endtemplate}
@immutable
class ElfCanonicalInstruction {
  /// {@macro elf_canonical_instruction}
  const ElfCanonicalInstruction({
    required this.address,
    required this.tokens,
  });

  /// Byte offset of this instruction relative to the start of the function.
  final int address;

  /// Canonical token representation (with trailing comma).
  final String tokens;

  /// Whether this instruction carries a resolved string literal (`S:...`).
  bool get hasStringLiteral => tokens.contains('S:');

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

/// {@template elf_function}
/// A resolved function slice from `.text` with canonicalized instructions.
/// {@endtemplate}
@immutable
class ElfFunction {
  /// {@macro elf_function}
  const ElfFunction({
    required this.name,
    required this.address,
    required this.size,
    required this.isAnonymous,
    required this.canonicalInstructions,
    required this.instructionStarts,
    required this.instructionAddresses,
  });

  /// Resolved symbol name from `.dynsym` / `.symtab`, or `.text` / `sub_<N>`
  /// when unnamed.
  final String name;

  /// Virtual address of the function start in `.text`.
  final int address;

  /// Size in bytes of the function slice.
  final int size;

  /// Whether the function slice had no symbol name at its start address.
  final bool isAnonymous;

  /// Concatenated canonical instruction tokens.
  final String canonicalInstructions;

  /// Start indices into [canonicalInstructions] for each instruction.
  final Uint32List instructionStarts;

  /// Function-relative byte offset of each instruction.
  final Uint32List instructionAddresses;

  /// Number of instructions/words in this function slice.
  int get instructionCount => instructionStarts.length;

  /// Returns the canonical token string for the instruction at [index].
  String tokensAt(int index) => canonicalInstructions.substring(
    instructionStarts[index],
    index + 1 < instructionStarts.length
        ? instructionStarts[index + 1]
        : canonicalInstructions.length,
  );

  /// Materializes the [ElfCanonicalInstruction] at [index].
  ElfCanonicalInstruction instructionAt(int index) => ElfCanonicalInstruction(
    address: instructionAddresses[index],
    tokens: tokensAt(index),
  );
}

/// {@template elf_file}
/// A parsed ELF32 or ELF64 shared object or executable binary.
/// {@endtemplate}
@immutable
class ElfFile {
  /// {@macro elf_file}
  const ElfFile({
    required this.header,
    required this.sections,
    required this.dynamicSymbols,
    required this.staticSymbols,
    required this.neededLibraries,
    required this.soname,
    required this.buildId,
    required this.debugLink,
    required this.debugLinkName,
    required this.debugSections,
    required this.rodataSections,
    required this.dataSections,
    required this.bssSize,
  });

  /// Parsed ELF32 or ELF64 header.
  final ElfHeader header;

  /// All sections in section-header-table order.
  final List<ElfSection> sections;

  /// Dynamic symbols parsed from `.dynsym` and `.dynstr` (excluding the
  /// reserved index-0 null symbol).
  final List<ElfSymbol> dynamicSymbols;

  /// Static symbols parsed from `.symtab` and `.strtab`, if present.
  final List<ElfSymbol> staticSymbols;

  /// Shared library dependencies (`DT_NEEDED`) from `.dynamic`.
  final List<String> neededLibraries;

  /// Shared object name (`DT_SONAME`) from `.dynamic`, or `null` if absent.
  final String? soname;

  /// Build ID payload from `.note.gnu.build-id`, or `null` if absent.
  final Uint8List? buildId;

  /// Raw `.gnu_debuglink` section bytes, or `null` if absent.
  final Uint8List? debugLink;

  /// Null-terminated debug filename decoded from `.gnu_debuglink`, or `null`
  /// if absent.
  final String? debugLinkName;

  /// Debug sections (`.debug_*`), keyed by section name.
  final Map<String, Uint8List> debugSections;

  /// Read-only data sections (`.rodata`, `.rodata.*`), keyed by section name.
  final Map<String, Uint8List> rodataSections;

  /// Initialized data sections (`.data`, `.data.*`, `.data.rel.ro`,
  /// `.init_array`, `.fini_array`), keyed by section name.
  final Map<String, Uint8List> dataSections;

  /// Total size in bytes of `.bss` (`SHT_NOBITS`) sections.
  final int bssSize;

  /// Alias for [dynamicSymbols].
  List<ElfSymbol> get symbols => dynamicSymbols;

  /// Names of all defined, externally visible symbols in `.dynsym`.
  Set<String> get exportedSymbolNames => {
    for (final s in dynamicSymbols)
      if (s.isExported && s.name.isNotEmpty) s.name,
  };

  /// Names of all undefined (imported) symbols in `.dynsym`.
  Set<String> get importedSymbolNames => {
    for (final s in dynamicSymbols)
      if (s.isUndefined && s.name.isNotEmpty) s.name,
  };

  /// Returns the first section with [name], or `null` if absent.
  ElfSection? sectionByName(String name) {
    for (final s in sections) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// Returns the `.text` section, or `null` if absent.
  ElfSection? get textSection => sectionByName('.text');

  /// Returns the `.plt` section, or `null` if absent.
  ElfSection? get pltSection => sectionByName('.plt');

  /// Resolves per-symbol function slices in `.text` with canonicalized
  /// instructions.
  ///
  /// On `EM_AARCH64`, PC-relative branch (`b`, `bl`) and page-address (`adrp`)
  /// targets are canonicalized so linker layout shifts do not produce false
  /// positives while real instruction or target mutations are caught.
  List<ElfFunction> resolveFunctions() {
    final text = textSection;
    if (text == null || text.bytes.isEmpty) return const [];

    final textStart = text.addr;
    final textEnd = text.addr + text.size;

    final addressToName = <int, String>{};
    for (final sym in [...staticSymbols, ...dynamicSymbols]) {
      if (sym.isUndefined || sym.name.isEmpty) continue;
      if (sym.type == ElfSymbolType.section || sym.type == ElfSymbolType.file) {
        continue;
      }
      if (sym.sectionName != null && sym.sectionName != '.text') continue;
      final normAddr = header.machine == ElfMachine.arm
          ? (sym.value & ~1)
          : sym.value;
      if (normAddr >= textStart && normAddr < textEnd) {
        addressToName[normAddr] = sym.name;
      }
    }

    final startSet = <int>{
      textStart,
      ...addressToName.keys,
    };
    final sortedStarts = startSet.toList()..sort();

    // Map null-terminated C strings in .rodata for ADRP+ADD resolution.
    final rodataStringsByAddr = <int, String>{};
    for (final s in sections) {
      if (s.name == '.rodata' || s.name.startsWith('.rodata.')) {
        var strStart = 0;
        for (var i = 0; i < s.bytes.length; i++) {
          if (s.bytes[i] == 0) {
            final str = utf8.decode(
              s.bytes.sublist(strStart, i),
              allowMalformed: true,
            );
            rodataStringsByAddr[s.addr + strStart] = str;
            strStart = i + 1;
          }
        }
      }
    }

    final funcNames = <int, String>{};
    final funcAnon = <int, bool>{};
    var anonIndex = 0;
    for (final startAddr in sortedStarts) {
      final symbolName = addressToName[startAddr];
      if (symbolName != null) {
        funcNames[startAddr] = symbolName;
        funcAnon[startAddr] = false;
      } else if (sortedStarts.length == 1) {
        funcNames[startAddr] = '.text';
        funcAnon[startAddr] = false;
      } else {
        funcNames[startAddr] = 'sub_$anonIndex';
        funcAnon[startAddr] = true;
        anonIndex++;
      }
    }

    final functions = <ElfFunction>[];
    final data = ByteData.sublistView(text.bytes);
    final endian = header.endian;

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

      if (header.machine == ElfMachine.aarch64 &&
          header.isLittleEndian &&
          funcSize % 4 == 0) {
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
            final mnemonic = op6 == 0x25 ? 'bl' : 'b';
            final imm26 = insn & 0x03ffffff;
            final signedImm26 = (imm26 & 0x02000000) != 0
                ? (imm26 | ~0x03ffffff)
                : imm26;
            final targetAddr = pc + signedImm26 * 4;

            final targetSymName =
                addressToName[targetAddr] ?? funcNames[targetAddr];
            if (targetAddr >= startAddr && targetAddr < endAddr) {
              final funcRel = targetAddr - startAddr;
              buffer.write('$mnemonic,+0x${funcRel.toRadixString(16)},');
            } else if (targetSymName != null) {
              buffer.write('$mnemonic,$targetSymName,');
            } else {
              buffer.write('$mnemonic,0x${targetAddr.toRadixString(16)},');
            }
          } else if ((insn & 0x9f000000) == 0x90000000) {
            final rd = insn & 0x1f;
            final regName = rd == 31 ? 'xzr' : 'x$rd';
            final immlo = (insn >>> 29) & 0x3;
            final immhi = (insn >>> 5) & 0x7ffff;
            final imm21 = (immhi << 2) | immlo;
            final signedImm21 = (imm21 & 0x100000) != 0
                ? (imm21 | ~0x1fffff)
                : imm21;
            final targetPage = (pc & ~0xfff) + (signedImm21 << 12);

            String? resolvedString;
            if (j + 1 < insnCount) {
              final nextInsn = data.getUint32(fileOff + 4, Endian.little);
              if ((nextInsn & 0xff800000) == 0x91000000 &&
                  ((nextInsn >>> 5) & 0x1f) == rd) {
                final imm12 = (nextInsn >>> 10) & 0xfff;
                final shift = ((nextInsn >>> 22) & 0x1) == 1 ? 12 : 0;
                final fullAddr = targetPage + (imm12 << shift);
                resolvedString = rodataStringsByAddr[fullAddr];
              }
            }

            if (resolvedString != null) {
              buffer.write('adrp,$regName,S:$resolvedString,');
            } else {
              final targetSect = _findSectionForPage(targetPage);
              if (targetSect != null) {
                final sectBasePage = targetSect.addr & ~0xfff;
                final pageDelta = targetPage - sectBasePage;
                buffer.write(
                  'adrp,$regName,${targetSect.name}'
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
        var offset = 0;
        while (offset < funcSize) {
          startsList.add(buffer.length);
          addrsList.add(offset);
          if (offset + 4 <= funcSize) {
            final word = data.getUint32(byteStart + offset, endian);
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
        ElfFunction(
          name: funcNames[startAddr] ?? '.text',
          address: startAddr,
          size: funcSize,
          isAnonymous: funcAnon[startAddr] ?? true,
          canonicalInstructions: buffer.toString(),
          instructionStarts: Uint32List.fromList(startsList),
          instructionAddresses: Uint32List.fromList(addrsList),
        ),
      );
    }

    return functions;
  }

  ElfSection? _findSectionForPage(int pageAddr) {
    for (final s in sections) {
      if (s.type == ElfSectionType.shtNull || s.addr == 0) continue;
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

/// {@template elf_parser}
/// Pure-Dart parser for ELF32 and ELF64 shared objects (`.so`) and executables.
/// {@endtemplate}
class ElfParser {
  /// {@macro elf_parser}
  const ElfParser();

  static const int _identSize = 16;
  static const int _ehdr32Size = 52;
  static const int _ehdr64Size = 64;
  static const int _shdr32Size = 40;
  static const int _shdr64Size = 64;
  static const int _sym32Size = 16;
  static const int _sym64Size = 24;
  static const int _dyn32Size = 8;
  static const int _dyn64Size = 16;

  /// Returns `true` if [bytes] begins with the 4-byte ELF magic (`\x7fELF`).
  static bool isElfBytes(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final magic = ByteData.sublistView(bytes).getUint32(0);
    return magic == ElfMagic.magic;
  }

  /// Parses [bytes] into an [ElfFile].
  ///
  /// Throws an [ElfFormatException] if [bytes] is truncated, corrupted, or not
  /// a valid ELF32/ELF64 binary.
  ElfFile parse(Uint8List bytes) {
    if (bytes.length < _identSize) {
      throw const ElfFormatException(
        'File too small to contain ELF identification header',
      );
    }

    final data = ByteData.sublistView(bytes);
    final magic = data.getUint32(0);
    if (magic != ElfMagic.magic) {
      throw ElfFormatException(
        'Invalid ELF magic: 0x${magic.toRadixString(16).padLeft(8, '0')}',
      );
    }

    final elfClass = bytes[4];
    if (elfClass != ElfClass.elfClass32 && elfClass != ElfClass.elfClass64) {
      throw ElfFormatException('Unsupported ELF class: $elfClass');
    }

    final dataEncoding = bytes[5];
    if (dataEncoding != ElfData.lsb && dataEncoding != ElfData.msb) {
      throw ElfFormatException(
        'Unsupported ELF data encoding: $dataEncoding',
      );
    }

    final identVersion = bytes[6];
    if (identVersion != 1) {
      throw ElfFormatException(
        'Unsupported ELF ident version: $identVersion',
      );
    }

    final is64Bit = elfClass == ElfClass.elfClass64;
    final endian = dataEncoding == ElfData.lsb ? Endian.little : Endian.big;
    final minHeaderSize = is64Bit ? _ehdr64Size : _ehdr32Size;
    if (bytes.length < minHeaderSize) {
      throw ElfFormatException(
        'Truncated ELF${is64Bit ? 64 : 32} header '
        '(length ${bytes.length} < $minHeaderSize)',
      );
    }

    final osAbi = bytes[7];
    final abiVersion = bytes[8];
    final fileType = data.getUint16(16, endian);
    final machine = data.getUint16(18, endian);
    final version = data.getUint32(20, endian);

    final int entry;
    final int phoff;
    final int shoff;
    final int flags;
    final int ehsize;
    final int phentsize;
    final int phnum;
    final int shentsize;
    final int shnum;
    final int shstrndx;

    if (is64Bit) {
      entry = data.getUint64(24, endian);
      phoff = data.getUint64(32, endian);
      shoff = data.getUint64(40, endian);
      flags = data.getUint32(48, endian);
      ehsize = data.getUint16(52, endian);
      phentsize = data.getUint16(54, endian);
      phnum = data.getUint16(56, endian);
      shentsize = data.getUint16(58, endian);
      shnum = data.getUint16(60, endian);
      shstrndx = data.getUint16(62, endian);
    } else {
      entry = data.getUint32(24, endian);
      phoff = data.getUint32(28, endian);
      shoff = data.getUint32(32, endian);
      flags = data.getUint32(36, endian);
      ehsize = data.getUint16(40, endian);
      phentsize = data.getUint16(42, endian);
      phnum = data.getUint16(44, endian);
      shentsize = data.getUint16(46, endian);
      shnum = data.getUint16(48, endian);
      shstrndx = data.getUint16(50, endian);
    }

    if (phnum > 0) {
      final phEnd = phoff + phnum * phentsize;
      if (phentsize == 0 || phEnd > bytes.length || phEnd < phoff) {
        throw const ElfFormatException(
          'Program header table extends past end of file',
        );
      }
    }

    final header = ElfHeader(
      elfClass: elfClass,
      dataEncoding: dataEncoding,
      osAbi: osAbi,
      abiVersion: abiVersion,
      fileType: fileType,
      machine: machine,
      version: version,
      entry: entry,
      phoff: phoff,
      shoff: shoff,
      flags: flags,
      ehsize: ehsize,
      phentsize: phentsize,
      phnum: phnum,
      shentsize: shentsize,
      shnum: shnum,
      shstrndx: shstrndx,
    );

    final sections = _parseSections(bytes, data, header);

    // Locate .dynsym / .dynstr and .symtab / .strtab.
    ElfSection? dynsymSect;
    ElfSection? symtabSect;
    ElfSection? dynamicSect;

    for (final s in sections) {
      if (s.type == ElfSectionType.dynsym || s.name == '.dynsym') {
        dynsymSect = s;
      } else if (s.type == ElfSectionType.symtab || s.name == '.symtab') {
        symtabSect = s;
      } else if (s.type == ElfSectionType.dynamicSection ||
          s.name == '.dynamic') {
        dynamicSect = s;
      }
    }

    final dynamicSymbols = dynsymSect != null
        ? _parseSymbolTable(
            symSection: dynsymSect,
            fallbackStrtabName: '.dynstr',
            sections: sections,
            header: header,
          )
        : const <ElfSymbol>[];

    final staticSymbols = symtabSect != null
        ? _parseSymbolTable(
            symSection: symtabSect,
            fallbackStrtabName: '.strtab',
            sections: sections,
            header: header,
          )
        : const <ElfSymbol>[];

    final (neededLibraries, soname) = dynamicSect != null
        ? _parseDynamic(
            dynamicSection: dynamicSect,
            sections: sections,
            header: header,
          )
        : (const <String>[], null);

    Uint8List? buildId;
    Uint8List? debugLink;
    String? debugLinkName;
    final debugSections = <String, Uint8List>{};
    final rodataSections = <String, Uint8List>{};
    final dataSections = <String, Uint8List>{};
    var bssSize = 0;

    for (final s in sections) {
      if (s.name == '.note.gnu.build-id') {
        buildId = _extractBuildId(s.bytes, header.endian);
      } else if (s.name == '.gnu_debuglink') {
        debugLink = s.bytes;
        debugLinkName = _readNullTerminatedString(s.bytes, 0, s.bytes.length);
      } else if (s.name.startsWith('.debug_')) {
        debugSections[s.name] = s.bytes;
      } else if (s.name == '.rodata' || s.name.startsWith('.rodata.')) {
        rodataSections[s.name] = s.bytes;
      } else if (s.name == '.data' ||
          s.name.startsWith('.data.') ||
          s.name == '.init_array' ||
          s.name == '.fini_array') {
        dataSections[s.name] = s.bytes;
      } else if (s.isNoBits || s.name == '.bss') {
        bssSize += s.size;
      }
    }

    return ElfFile(
      header: header,
      sections: sections,
      dynamicSymbols: dynamicSymbols,
      staticSymbols: staticSymbols,
      neededLibraries: neededLibraries,
      soname: soname,
      buildId: buildId,
      debugLink: debugLink,
      debugLinkName: debugLinkName,
      debugSections: debugSections,
      rodataSections: rodataSections,
      dataSections: dataSections,
      bssSize: bssSize,
    );
  }

  List<ElfSection> _parseSections(
    Uint8List bytes,
    ByteData data,
    ElfHeader header,
  ) {
    if (header.shnum == 0) {
      return const [];
    }

    final minShdrSize = header.is64Bit ? _shdr64Size : _shdr32Size;
    if (header.shentsize < minShdrSize) {
      throw ElfFormatException(
        'Invalid e_shentsize ${header.shentsize} (expected >= $minShdrSize)',
      );
    }

    final shEnd = header.shoff + header.shnum * header.shentsize;
    if (header.shoff == 0 || shEnd > bytes.length || shEnd < header.shoff) {
      throw ElfFormatException(
        'Section header table [${header.shoff}..$shEnd) extends past end of '
        'file (${bytes.length})',
      );
    }

    if (header.shstrndx >= header.shnum) {
      throw ElfFormatException(
        'e_shstrndx (${header.shstrndx}) out of bounds '
        '(e_shnum=${header.shnum})',
      );
    }

    final endian = header.endian;
    final rawSections = <ElfSection>[];

    for (var i = 0; i < header.shnum; i++) {
      final off = header.shoff + i * header.shentsize;
      final nameOffset = data.getUint32(off, endian);
      final type = data.getUint32(off + 4, endian);

      final int flags;
      final int addr;
      final int offset;
      final int size;
      final int link;
      final int info;
      final int addralign;
      final int entsize;

      if (header.is64Bit) {
        flags = data.getUint64(off + 8, endian);
        addr = data.getUint64(off + 16, endian);
        offset = data.getUint64(off + 24, endian);
        size = data.getUint64(off + 32, endian);
        link = data.getUint32(off + 40, endian);
        info = data.getUint32(off + 44, endian);
        addralign = data.getUint64(off + 48, endian);
        entsize = data.getUint64(off + 56, endian);
      } else {
        flags = data.getUint32(off + 8, endian);
        addr = data.getUint32(off + 12, endian);
        offset = data.getUint32(off + 16, endian);
        size = data.getUint32(off + 20, endian);
        link = data.getUint32(off + 24, endian);
        info = data.getUint32(off + 28, endian);
        addralign = data.getUint32(off + 32, endian);
        entsize = data.getUint32(off + 36, endian);
      }

      Uint8List sectBytes;
      if (type == ElfSectionType.shtNull ||
          type == ElfSectionType.nobits ||
          size == 0) {
        sectBytes = Uint8List(0);
      } else {
        final end = offset + size;
        if (end > bytes.length || end < offset) {
          throw ElfFormatException(
            'Section $i range [$offset..$end) exceeds file length '
            '${bytes.length}',
          );
        }
        sectBytes = bytes.sublist(offset, end);
      }

      rawSections.add(
        ElfSection(
          name: '',
          nameOffset: nameOffset,
          type: type,
          flags: flags,
          addr: addr,
          offset: offset,
          size: size,
          link: link,
          info: info,
          addralign: addralign,
          entsize: entsize,
          bytes: sectBytes,
        ),
      );
    }

    final shstrtabBytes = header.shstrndx > 0
        ? rawSections[header.shstrndx].bytes
        : Uint8List(0);

    final namedSections = <ElfSection>[];
    for (var i = 0; i < rawSections.length; i++) {
      final s = rawSections[i];
      String name;
      if (shstrtabBytes.isEmpty) {
        if (s.nameOffset != 0) {
          throw ElfFormatException(
            'Section $i has sh_name=${s.nameOffset} but .shstrtab is empty',
          );
        }
        name = '';
      } else {
        if (s.nameOffset >= shstrtabBytes.length) {
          throw ElfFormatException(
            'Section $i sh_name (${s.nameOffset}) exceeds .shstrtab length '
            '(${shstrtabBytes.length})',
          );
        }
        name = _readNullTerminatedString(
          shstrtabBytes,
          s.nameOffset,
          shstrtabBytes.length,
        );
      }

      namedSections.add(
        ElfSection(
          name: name,
          nameOffset: s.nameOffset,
          type: s.type,
          flags: s.flags,
          addr: s.addr,
          offset: s.offset,
          size: s.size,
          link: s.link,
          info: s.info,
          addralign: s.addralign,
          entsize: s.entsize,
          bytes: s.bytes,
        ),
      );
    }

    return namedSections;
  }

  List<ElfSymbol> _parseSymbolTable({
    required ElfSection symSection,
    required String fallbackStrtabName,
    required List<ElfSection> sections,
    required ElfHeader header,
  }) {
    final defaultEntrySize = header.is64Bit ? _sym64Size : _sym32Size;
    final entrySize = symSection.entsize > 0
        ? symSection.entsize
        : defaultEntrySize;
    if (entrySize < defaultEntrySize ||
        symSection.bytes.length % entrySize != 0) {
      throw ElfFormatException(
        'Invalid symbol table section ${symSection.name} '
        '(size=${symSection.bytes.length}, entsize=$entrySize)',
      );
    }

    final strtabBytes = _resolveLinkedStringTable(
      section: symSection,
      fallbackName: fallbackStrtabName,
      sections: sections,
    );

    final count = symSection.bytes.length ~/ entrySize;
    final data = ByteData.sublistView(symSection.bytes);
    final endian = header.endian;
    final symbols = <ElfSymbol>[];

    // Skip index 0 (the reserved STN_UNDEF null entry) unless it carries
    // non-zero data.
    for (var i = 0; i < count; i++) {
      final off = i * entrySize;
      final int stName;
      final int stValue;
      final int stSize;
      final int stInfo;
      final int stOther;
      final int stShndx;

      if (header.is64Bit) {
        stName = data.getUint32(off, endian);
        stInfo = symSection.bytes[off + 4];
        stOther = symSection.bytes[off + 5];
        stShndx = data.getUint16(off + 6, endian);
        stValue = data.getUint64(off + 8, endian);
        stSize = data.getUint64(off + 16, endian);
      } else {
        stName = data.getUint32(off, endian);
        stValue = data.getUint32(off + 4, endian);
        stSize = data.getUint32(off + 8, endian);
        stInfo = symSection.bytes[off + 12];
        stOther = symSection.bytes[off + 13];
        stShndx = data.getUint16(off + 14, endian);
      }

      if (i == 0 &&
          stName == 0 &&
          stValue == 0 &&
          stSize == 0 &&
          stInfo == 0 &&
          stShndx == ElfSectionIndex.undef) {
        continue;
      }

      if (stName >= strtabBytes.length &&
          (strtabBytes.isNotEmpty || stName > 0)) {
        throw ElfFormatException(
          'Symbol $i st_name ($stName) exceeds string table length '
          '(${strtabBytes.length})',
        );
      }

      final name = strtabBytes.isEmpty
          ? ''
          : _readNullTerminatedString(strtabBytes, stName, strtabBytes.length);

      String? sectionName;
      if (stShndx > ElfSectionIndex.undef &&
          stShndx < ElfSectionIndex.loreserve) {
        if (stShndx >= sections.length) {
          throw ElfFormatException(
            'Symbol "$name" st_shndx ($stShndx) out of bounds '
            '(sections=${sections.length})',
          );
        }
        sectionName = sections[stShndx].name;
      }

      symbols.add(
        ElfSymbol(
          name: name,
          value: stValue,
          size: stSize,
          info: stInfo,
          other: stOther,
          shndx: stShndx,
          sectionName: sectionName,
        ),
      );
    }

    return symbols;
  }

  (List<String>, String?) _parseDynamic({
    required ElfSection dynamicSection,
    required List<ElfSection> sections,
    required ElfHeader header,
  }) {
    final defaultEntrySize = header.is64Bit ? _dyn64Size : _dyn32Size;
    final entrySize = dynamicSection.entsize > 0
        ? dynamicSection.entsize
        : defaultEntrySize;
    if (entrySize < defaultEntrySize ||
        dynamicSection.bytes.length % entrySize != 0) {
      throw ElfFormatException(
        'Invalid .dynamic section (size=${dynamicSection.bytes.length}, '
        'entsize=$entrySize)',
      );
    }

    final strtabBytes = _resolveLinkedStringTable(
      section: dynamicSection,
      fallbackName: '.dynstr',
      sections: sections,
    );

    final count = dynamicSection.bytes.length ~/ entrySize;
    final data = ByteData.sublistView(dynamicSection.bytes);
    final endian = header.endian;
    final needed = <String>[];
    String? soname;

    for (var i = 0; i < count; i++) {
      final off = i * entrySize;
      final int dTag;
      final int dVal;
      if (header.is64Bit) {
        dTag = data.getInt64(off, endian);
        dVal = data.getUint64(off + 8, endian);
      } else {
        dTag = data.getInt32(off, endian);
        dVal = data.getUint32(off + 4, endian);
      }

      if (dTag == ElfDynamicTag.dtNull) {
        break;
      } else if (dTag == ElfDynamicTag.needed) {
        if (dVal >= strtabBytes.length) {
          throw ElfFormatException(
            'DT_NEEDED string offset ($dVal) exceeds .dynstr length '
            '(${strtabBytes.length})',
          );
        }
        final lib = _readNullTerminatedString(
          strtabBytes,
          dVal,
          strtabBytes.length,
        );
        if (lib.isNotEmpty) {
          needed.add(lib);
        }
      } else if (dTag == ElfDynamicTag.soname) {
        if (dVal >= strtabBytes.length) {
          throw ElfFormatException(
            'DT_SONAME string offset ($dVal) exceeds .dynstr length '
            '(${strtabBytes.length})',
          );
        }
        soname = _readNullTerminatedString(
          strtabBytes,
          dVal,
          strtabBytes.length,
        );
      }
    }

    return (needed, soname);
  }

  Uint8List _resolveLinkedStringTable({
    required ElfSection section,
    required String fallbackName,
    required List<ElfSection> sections,
  }) {
    if (section.link > 0) {
      if (section.link >= sections.length) {
        throw ElfFormatException(
          'Section ${section.name} sh_link (${section.link}) out of bounds '
          '(sections=${sections.length})',
        );
      }
      return sections[section.link].bytes;
    }

    for (final s in sections) {
      if (s.name == fallbackName) {
        return s.bytes;
      }
    }
    return Uint8List(0);
  }

  Uint8List _extractBuildId(Uint8List noteBytes, Endian endian) {
    if (noteBytes.length >= 12) {
      final data = ByteData.sublistView(noteBytes);
      final namesz = data.getUint32(0, endian);
      final descsz = data.getUint32(4, endian);
      final alignedNamesz = (namesz + 3) & ~3;
      final descStart = 12 + alignedNamesz;
      final descEnd = descStart + descsz;
      if (descsz > 0 && descEnd <= noteBytes.length && descEnd >= descStart) {
        return noteBytes.sublist(descStart, descEnd);
      }
    }
    return noteBytes;
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
}
