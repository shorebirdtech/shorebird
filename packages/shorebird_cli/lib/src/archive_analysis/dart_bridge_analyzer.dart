// cspell:words cstring cstrings dynsym hostapi insn methname rodata sbbr
// cspell:words sublist
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:elf/elf.dart';
import 'package:equatable/equatable.dart';
import 'package:macho/macho.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

/// Magic bytes at the start of every Dart `.dill` kernel binary (`0x90ABCDEF`).
const int dillKernelMagic = 0x90abcdef;

/// Pragma name used by the Dart compiler for `@Native` FFI bindings.
const String ffiNativePragmaName = 'vm:ffi:native';

/// Prefix used by Pigeon-generated platform channels.
const String pigeonChannelPrefix = 'dev.flutter.pigeon.';

/// The kind of platform channel used to cross the Dart-to-native boundary.
enum DartChannelKind {
  /// A `MethodChannel` invocation channel.
  methodChannel('MethodChannel'),

  /// An `EventChannel` stream channel.
  eventChannel('EventChannel'),

  /// A `BasicMessageChannel` message channel.
  basicMessageChannel('BasicMessageChannel'),

  /// A Pigeon (`dev.flutter.pigeon.*`) typed channel.
  pigeon('Pigeon channel');

  const DartChannelKind(this.label);

  /// Human-readable channel type name.
  final String label;
}

/// {@template dart_ffi_native_symbol}
/// A `@Native` (`@pragma('vm:ffi:native', ...)`) symbol referenced by a Dart
/// kernel (`app.dill`) binary.
/// {@endtemplate}
@immutable
class DartFfiNativeSymbol extends Equatable {
  /// {@macro dart_ffi_native_symbol}
  const DartFfiNativeSymbol({
    required this.symbol,
    this.dartName,
    this.assetId,
  });

  /// C, Objective-C, Swift, or Rust native symbol name.
  final String symbol;

  /// Optional Dart function or member name annotated with `@Native`.
  final String? dartName;

  /// Optional native asset identifier (`assetId`).
  final String? assetId;

  @override
  List<Object?> get props => [symbol, dartName, assetId];
}

/// {@template dart_platform_channel}
/// A platform channel (`MethodChannel`, `EventChannel`, `BasicMessageChannel`,
/// or Pigeon `dev.flutter.pigeon.*`) extracted from a Dart kernel (`app.dill`)
/// binary.
/// {@endtemplate}
@immutable
class DartPlatformChannel extends Equatable {
  /// {@macro dart_platform_channel}
  const DartPlatformChannel({
    required this.name,
    required this.kind,
  });

  /// Channel name string (e.g. `com.example/battery` or
  /// `dev.flutter.pigeon.pkg.HostApi.getLevel`).
  final String name;

  /// The type of platform channel.
  final DartChannelKind kind;

  @override
  List<Object?> get props => [name, kind];
}

/// {@template dart_bridge_contract}
/// The native FFI and platform channel bridge contract extracted from a
/// compiled `app.dill` kernel binary.
/// {@endtemplate}
@immutable
class DartBridgeContract extends Equatable {
  /// {@macro dart_bridge_contract}
  const DartBridgeContract({
    this.ffiSymbols = const [],
    this.channels = const [],
  });

  /// `@Native` (`vm:ffi:native`) symbols referenced by the Dart kernel.
  final List<DartFfiNativeSymbol> ffiSymbols;

  /// Platform channels (`MethodChannel`, `EventChannel`,
  /// `BasicMessageChannel`, and Pigeon) referenced by the Dart kernel.
  final List<DartPlatformChannel> channels;

  /// Distinct native symbol names referenced by [ffiSymbols].
  Set<String> get ffiNativeSymbolNames => {
    for (final s in ffiSymbols) s.symbol,
  };

  /// Distinct channel names referenced by [channels].
  Set<String> get channelNames => {
    for (final c in channels) c.name,
  };

  /// Whether the kernel references neither FFI symbols nor platform channels.
  bool get isEmpty => ffiSymbols.isEmpty && channels.isEmpty;

  @override
  List<Object?> get props => [ffiSymbols, channels];
}

/// The classification of a Dart-to-native bridge contract mismatch.
enum DartBridgeDiagnosticKind {
  /// An `@Native` (`vm:ffi:native`) symbol referenced by `app.dill` is missing
  /// from the release's exported native symbol tables.
  missingFfiSymbol,

  /// A `MethodChannel`, `EventChannel`, `BasicMessageChannel`, or Pigeon
  /// channel referenced by `app.dill` is owned by a modified native class or
  /// binary.
  modifiedPlatformChannel,
}

/// {@template dart_bridge_diagnostic}
/// A `[CRASH RISK]` diagnostic emitted when a patch's `app.dill` bridge
/// contract disagrees with the release's native binary symbols or changed
/// native classes.
/// {@endtemplate}
@immutable
class DartBridgeDiagnostic extends Equatable {
  /// {@macro dart_bridge_diagnostic}
  const DartBridgeDiagnostic({
    required this.kind,
    required this.symbolOrChannel,
    required this.message,
    this.channelKind,
    this.owner,
  });

  /// The classification of this bridge mismatch.
  final DartBridgeDiagnosticKind kind;

  /// The missing `@Native` symbol name or modified platform channel name.
  final String symbolOrChannel;

  /// Human-readable `[CRASH RISK]` diagnostic message.
  final String message;

  /// The channel kind when [kind] is
  /// [DartBridgeDiagnosticKind.modifiedPlatformChannel].
  final DartChannelKind? channelKind;

  /// The changed native class or binary that owns [symbolOrChannel], if
  /// applicable.
  final String? owner;

  /// Formats this diagnostic for console output.
  String describe() => message;

  @override
  List<Object?> get props => [
    kind,
    symbolOrChannel,
    message,
    channelKind,
    owner,
  ];
}

/// {@template dart_bridge_analysis_result}
/// The result of verifying a patch's `app.dill` bridge contract against the
/// release binary symbols and native archive diff.
/// {@endtemplate}
@immutable
class DartBridgeAnalysisResult extends Equatable {
  /// {@macro dart_bridge_analysis_result}
  const DartBridgeAnalysisResult({
    required this.contract,
    required this.diagnostics,
  });

  /// Creates an empty result with no extracted contract or diagnostics.
  const DartBridgeAnalysisResult.empty()
    : contract = const DartBridgeContract(),
      diagnostics = const [];

  /// The bridge contract parsed from `app.dill`.
  final DartBridgeContract contract;

  /// All `[CRASH RISK]` diagnostics detected.
  final List<DartBridgeDiagnostic> diagnostics;

  /// Whether no bridge contract mismatches were found.
  bool get isSafe => diagnostics.isEmpty;

  /// Whether one or more `[CRASH RISK]` diagnostics were found.
  bool get hasCrashRisks => diagnostics.isNotEmpty;

  @override
  List<Object?> get props => [contract, diagnostics];
}

/// {@template dill_kernel_builder}
/// Pure-Dart in-memory builder that synthesizes Dart `.dill` kernel binaries
/// containing a Kernel `StringTable` and `@Native` (`vm:ffi:native`) /
/// platform-channel bridge metadata for deterministic testing.
/// {@endtemplate}
class DillKernelBuilder {
  /// {@macro dill_kernel_builder}
  DillKernelBuilder({this.formatVersion = 120});

  /// Kernel binary format version written into the header.
  final int formatVersion;

  final List<DartFfiNativeSymbol> _ffiSymbols = [];
  final List<DartPlatformChannel> _channels = [];
  final List<String> _extraStrings = [];

  /// Adds an `@Native` (`@pragma('vm:ffi:native', ...)`) symbol reference.
  void addFfiNativeSymbol(
    String symbol, {
    String? dartName,
    String? assetId,
  }) {
    _ffiSymbols.add(
      DartFfiNativeSymbol(
        symbol: symbol,
        dartName: dartName,
        assetId: assetId,
      ),
    );
  }

  /// Adds a `MethodChannel` reference.
  void addMethodChannel(String name) {
    _channels.add(
      DartPlatformChannel(
        name: name,
        kind: name.startsWith(pigeonChannelPrefix)
            ? DartChannelKind.pigeon
            : DartChannelKind.methodChannel,
      ),
    );
  }

  /// Adds an `EventChannel` reference.
  void addEventChannel(String name) {
    _channels.add(
      DartPlatformChannel(name: name, kind: DartChannelKind.eventChannel),
    );
  }

  /// Adds a `BasicMessageChannel` reference.
  void addBasicMessageChannel(String name) {
    _channels.add(
      DartPlatformChannel(
        name: name,
        kind: name.startsWith(pigeonChannelPrefix)
            ? DartChannelKind.pigeon
            : DartChannelKind.basicMessageChannel,
      ),
    );
  }

  /// Adds a Pigeon (`dev.flutter.pigeon.*`) channel reference.
  void addPigeonChannel(String name) {
    _channels.add(
      DartPlatformChannel(name: name, kind: DartChannelKind.pigeon),
    );
  }

  /// Adds an arbitrary string to the kernel `StringTable`.
  void addRawString(String value) {
    _extraStrings.add(value);
  }

  /// Encodes the `.dill` kernel binary as a [Uint8List].
  Uint8List build() {
    final stringPool = <String>[];
    final stringIndex = <String, int>{};

    int intern(String value) {
      return stringIndex.putIfAbsent(value, () {
        final idx = stringPool.length;
        stringPool.add(value);
        return idx;
      });
    }

    final pragmaIndex = intern(ffiNativePragmaName);
    for (final kind in DartChannelKind.values) {
      intern(kind.label);
    }
    _extraStrings.forEach(intern);

    final encodedFfi = <({int pragma, int symbol, int dartName, int assetId})>[
      for (final ffi in _ffiSymbols)
        (
          pragma: pragmaIndex,
          symbol: intern(ffi.symbol),
          dartName: switch (ffi.dartName) {
            final name? => intern(name) + 1,
            null => 0,
          },
          assetId: switch (ffi.assetId) {
            final id? => intern(id) + 1,
            null => 0,
          },
        ),
    ];

    final encodedChannels = <({int kind, int name})>[
      for (final channel in _channels)
        (
          kind: channel.kind.index,
          name: intern(channel.name),
        ),
    ];

    final builder = BytesBuilder(copy: false);

    // 1. 8-byte Kernel header: magic (0x90ABCDEF) + formatVersion.
    final header = ByteData(8)
      ..setUint32(0, dillKernelMagic)
      ..setUint32(4, formatVersion);
    builder.add(header.buffer.asUint8List());

    // 2. Kernel StringTable: UInt count, UInt[count] cumulative UTF-8 end
    // offsets, and concatenated UTF-8 payload bytes.
    _writeKernelUInt(builder, stringPool.length);
    final utf8Chunks = <Uint8List>[];
    var cumulativeBytes = 0;
    for (final s in stringPool) {
      final encoded = utf8.encode(s);
      utf8Chunks.add(encoded);
      cumulativeBytes += encoded.length;
      _writeKernelUInt(builder, cumulativeBytes);
    }
    utf8Chunks.forEach(builder.add);

    // 3. Bridge contract table marker ('SBBR') and structured constant entries.
    builder.add(const [0x53, 0x42, 0x42, 0x52]); // 'SBBR'
    _writeKernelUInt(builder, encodedFfi.length);
    for (final entry in encodedFfi) {
      _writeKernelUInt(builder, entry.pragma);
      _writeKernelUInt(builder, entry.symbol);
      _writeKernelUInt(builder, entry.dartName);
      _writeKernelUInt(builder, entry.assetId);
    }

    _writeKernelUInt(builder, encodedChannels.length);
    for (final entry in encodedChannels) {
      _writeKernelUInt(builder, entry.kind);
      _writeKernelUInt(builder, entry.name);
    }

    return builder.toBytes();
  }

  static void _writeKernelUInt(BytesBuilder builder, int value) {
    if (value < 0x80) {
      builder.addByte(value);
    } else if (value < 0x4000) {
      builder
        ..addByte((value >> 8) | 0x80)
        ..addByte(value & 0xff);
    } else {
      builder
        ..addByte((value >> 24) | 0xc0)
        ..addByte((value >> 16) & 0xff)
        ..addByte((value >> 8) & 0xff)
        ..addByte(value & 0xff);
    }
  }
}

/// {@template dart_bridge_analyzer}
/// Inspects a compiled Dart kernel (`app.dill`) for `@Native` (`vm:ffi:native`)
/// symbols and `MethodChannel` / `EventChannel` / `BasicMessageChannel` /
/// Pigeon (`dev.flutter.pigeon.*`) channels, verifying them against the
/// release's native symbol tables and changed native classes.
/// {@endtemplate}
class DartBridgeAnalyzer {
  /// {@macro dart_bridge_analyzer}
  const DartBridgeAnalyzer();

  static final RegExp _dexClassDescriptorRegex = RegExp(
    r'L[A-Za-z0-9_/$]+;',
  );
  static final RegExp _quotedStringRegex = RegExp('"([^"]+)"');

  /// Parses [bytes] as a Dart `.dill` kernel binary and extracts its
  /// [DartBridgeContract].
  ///
  /// Throws a [FormatException] if [bytes] is truncated, corrupt, or does not
  /// begin with [dillKernelMagic].
  DartBridgeContract parseDill(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const FormatException(
        'Truncated Dart .dill kernel header (fewer than 8 bytes).',
      );
    }
    final header = ByteData.sublistView(bytes, 0, 8);
    final magic = header.getUint32(0);
    if (magic != dillKernelMagic) {
      throw FormatException(
        'Invalid Dart .dill kernel magic: '
        '0x${magic.toRadixString(16).padLeft(8, '0')}.',
      );
    }

    final reader = _KernelReader(bytes, offset: 8);
    final stringCount = reader.readUInt();
    final endOffsets = List<int>.filled(stringCount, 0);
    var previousEnd = 0;
    for (var i = 0; i < stringCount; i++) {
      final end = reader.readUInt();
      if (end < previousEnd) {
        throw const FormatException(
          'Non-monotonic string end offset in Dart .dill StringTable.',
        );
      }
      endOffsets[i] = end;
      previousEnd = end;
    }

    final totalStringBytes = stringCount == 0 ? 0 : endOffsets.last;
    if (reader.offset + totalStringBytes > bytes.length) {
      throw const FormatException(
        'Truncated Dart .dill StringTable UTF-8 payload.',
      );
    }

    final stringsBase = reader.offset;
    final strings = <String>[];
    var start = 0;
    for (var i = 0; i < stringCount; i++) {
      final end = endOffsets[i];
      final slice = Uint8List.sublistView(
        bytes,
        stringsBase + start,
        stringsBase + end,
      );
      strings.add(utf8.decode(slice));
      start = end;
    }
    reader.offset += totalStringBytes;

    final ffiSymbols = <DartFfiNativeSymbol>[];
    final channels = <DartPlatformChannel>[];

    if (reader.remaining >= 4 &&
        bytes[reader.offset] == 0x53 && // 'S'
        bytes[reader.offset + 1] == 0x42 && // 'B'
        bytes[reader.offset + 2] == 0x42 && // 'B'
        bytes[reader.offset + 3] == 0x52) {
      // 'R'
      reader.offset += 4;
      final ffiCount = reader.readUInt();
      for (var i = 0; i < ffiCount; i++) {
        final pragmaIdx = reader.readUInt();
        final symbolIdx = reader.readUInt();
        final dartNameIdxPlusOne = reader.readUInt();
        final assetIdIdxPlusOne = reader.readUInt();
        if (pragmaIdx >= strings.length || symbolIdx >= strings.length) {
          throw const FormatException(
            'Out-of-bounds string index in .dill FFI symbol table.',
          );
        }
        String? dartName;
        if (dartNameIdxPlusOne > 0) {
          final idx = dartNameIdxPlusOne - 1;
          if (idx >= strings.length) {
            throw const FormatException(
              'Out-of-bounds dartName index in .dill FFI symbol table.',
            );
          }
          dartName = strings[idx];
        }
        String? assetId;
        if (assetIdIdxPlusOne > 0) {
          final idx = assetIdIdxPlusOne - 1;
          if (idx >= strings.length) {
            throw const FormatException(
              'Out-of-bounds assetId index in .dill FFI symbol table.',
            );
          }
          assetId = strings[idx];
        }
        if (strings[pragmaIdx] == ffiNativePragmaName) {
          ffiSymbols.add(
            DartFfiNativeSymbol(
              symbol: strings[symbolIdx],
              dartName: dartName,
              assetId: assetId,
            ),
          );
        }
      }

      final channelCount = reader.readUInt();
      for (var i = 0; i < channelCount; i++) {
        final kindIdx = reader.readUInt();
        final nameIdx = reader.readUInt();
        if (kindIdx >= DartChannelKind.values.length ||
            nameIdx >= strings.length) {
          throw const FormatException(
            'Out-of-bounds index in .dill platform channel table.',
          );
        }
        final name = strings[nameIdx];
        final kind = name.startsWith(pigeonChannelPrefix)
            ? DartChannelKind.pigeon
            : DartChannelKind.values[kindIdx];
        channels.add(DartPlatformChannel(name: name, kind: kind));
      }
    }

    // Also surface any Pigeon channel strings present in the StringTable that
    // were not already listed in the structured channel section.
    final seenChannels = {for (final c in channels) c.name};
    for (final s in strings) {
      if (s.startsWith(pigeonChannelPrefix) && seenChannels.add(s)) {
        channels.add(
          DartPlatformChannel(name: s, kind: DartChannelKind.pigeon),
        );
      }
    }

    return DartBridgeContract(
      ffiSymbols: ffiSymbols,
      channels: channels,
    );
  }

  /// Cross-checks the patch's [dillBytes] against the release's native binary
  /// symbols and changed native classes/channels.
  ///
  /// If [dillBytes] cannot be parsed as a valid `.dill` kernel, returns
  /// [DartBridgeAnalysisResult.empty] rather than throwing so archive diffing
  /// is never weakened or crashed by an unreadable kernel.
  DartBridgeAnalysisResult analyze({
    required Uint8List dillBytes,
    Set<String>? releaseSymbols,
    Iterable<Uint8List> releaseElfBinaries = const [],
    Iterable<Uint8List> releaseMachOBinaries = const [],
    Set<String> changedClasses = const {},
    Set<String> changedChannelNames = const {},
    Map<String, Set<String>> channelOwners = const {},
    FileSetDiff? fileSetDiff,
    String? releaseArchivePath,
  }) {
    final DartBridgeContract contract;
    try {
      contract = parseDill(dillBytes);
    } on FormatException {
      return const DartBridgeAnalysisResult.empty();
    }

    if (contract.isEmpty) {
      return DartBridgeAnalysisResult(
        contract: contract,
        diagnostics: const [],
      );
    }

    final diagnostics = <DartBridgeDiagnostic>[];

    // 1. Verify @Native (vm:ffi:native) symbols against release binaries.
    final hasReleaseSymbolSource =
        releaseSymbols != null ||
        releaseElfBinaries.isNotEmpty ||
        releaseMachOBinaries.isNotEmpty ||
        releaseArchivePath != null;

    if (contract.ffiSymbols.isNotEmpty && hasReleaseSymbolSource) {
      final exportedSymbols = <String>{
        ...?releaseSymbols,
        ..._extractElfSymbols(releaseElfBinaries),
        ..._extractMachOSymbols(releaseMachOBinaries),
        if (releaseArchivePath != null)
          ..._extractArchiveSymbols(releaseArchivePath),
      };

      for (final ffi in contract.ffiSymbols) {
        if (!_symbolExistsInRelease(ffi.symbol, exportedSymbols)) {
          diagnostics.add(
            DartBridgeDiagnostic(
              kind: DartBridgeDiagnosticKind.missingFfiSymbol,
              symbolOrChannel: ffi.symbol,
              message:
                  '[CRASH RISK] @Native symbol "${ffi.symbol}" referenced in '
                  'app.dill is missing from the release native binaries.',
            ),
          );
        }
      }
    }

    // 2. Verify MethodChannel / EventChannel / BasicMessageChannel / Pigeon
    // channels against changed native classes and modified channel literals.
    if (contract.channels.isNotEmpty) {
      final effectiveChangedClasses = <String>{...changedClasses};
      final effectiveChangedChannels = <String>{...changedChannelNames};

      if (fileSetDiff != null) {
        _collectDiffMetadata(
          fileSetDiff: fileSetDiff,
          changedClasses: effectiveChangedClasses,
          changedChannels: effectiveChangedChannels,
        );
      }

      for (final channel in contract.channels) {
        final owner = _findModifiedChannelOwner(
          channel: channel,
          changedClasses: effectiveChangedClasses,
          changedChannels: effectiveChangedChannels,
          channelOwners: channelOwners,
        );
        if (owner != null) {
          diagnostics.add(
            DartBridgeDiagnostic(
              kind: DartBridgeDiagnosticKind.modifiedPlatformChannel,
              symbolOrChannel: channel.name,
              channelKind: channel.kind,
              owner: owner,
              message:
                  '[CRASH RISK] ${channel.kind.label} "${channel.name}" '
                  'referenced in app.dill is owned by modified native code '
                  '($owner).',
            ),
          );
        }
      }
    }

    return DartBridgeAnalysisResult(
      contract: contract,
      diagnostics: diagnostics,
    );
  }

  static bool _symbolExistsInRelease(
    String symbol,
    Set<String> exportedSymbols,
  ) {
    if (exportedSymbols.contains(symbol) ||
        exportedSymbols.contains('_$symbol')) {
      return true;
    }
    if (symbol.startsWith('_') &&
        exportedSymbols.contains(symbol.substring(1))) {
      return true;
    }
    return false;
  }

  static Set<String> _extractElfSymbols(Iterable<Uint8List> binaries) {
    const parser = ElfParser();
    final symbols = <String>{};
    for (final bytes in binaries) {
      try {
        final elf = parser.parse(bytes);
        symbols.addAll(elf.exportedSymbolNames);
        for (final s in elf.staticSymbols) {
          if (!s.isUndefined && s.name.isNotEmpty) {
            symbols.add(s.name);
          }
        }
        // Ignore unparseable binaries during symbol harvesting.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
    return symbols;
  }

  static Set<String> _extractMachOSymbols(Iterable<Uint8List> binaries) {
    const parser = MachOParser();
    final symbols = <String>{};
    for (final bytes in binaries) {
      try {
        final machO = parser.parse(bytes);
        for (final slice in machO.slices) {
          for (final s in slice.symbols) {
            if (s.isDefinedInSection && s.name.isNotEmpty) {
              symbols.add(s.name);
            }
          }
          for (final e in slice.exportedSymbols) {
            if (e.name.isNotEmpty) {
              symbols.add(e.name);
            }
          }
        }
        // Ignore unparseable binaries during symbol harvesting.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
    return symbols;
  }

  static Set<String> _extractArchiveSymbols(String archivePath) {
    final elfBinaries = <Uint8List>[];
    final machOBinaries = <Uint8List>[];
    try {
      final input = InputFileStream(archivePath);
      try {
        final archive = ZipDecoder().decodeStream(input, verify: true);
        for (final file in archive.files) {
          if (!file.isFile) continue;
          final name = file.name;
          final base = p.basename(name);
          if (name.endsWith('.so') &&
              base != 'libapp.so' &&
              base != 'libflutter.so') {
            elfBinaries.add(Uint8List.fromList(file.content));
          } else if (AppleArchiveDiffer.xcFrameworkAppRegex.hasMatch(name) ||
              AppleArchiveDiffer.macosAppRegex.hasMatch(name) ||
              AppleArchiveDiffer.isEmbeddedFrameworkBinaryPath(name)) {
            machOBinaries.add(Uint8List.fromList(file.content));
          }
        }
      } finally {
        input.closeSync();
      }
      // Ignore archive read failures during symbol harvesting.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return const {};
    }

    return {
      ..._extractElfSymbols(elfBinaries),
      ..._extractMachOSymbols(machOBinaries),
    };
  }

  static void _collectDiffMetadata({
    required FileSetDiff fileSetDiff,
    required Set<String> changedClasses,
    required Set<String> changedChannels,
  }) {
    if (fileSetDiff is AndroidFileSetDiff) {
      for (final dexResult in fileSetDiff.dexDiffResults.values) {
        for (final diff in dexResult.breakingDifferences) {
          for (final match in _dexClassDescriptorRegex.allMatches(
            diff.description,
          )) {
            final group = match.group(0);
            if (group != null) changedClasses.add(group);
          }
          final codeDiff = diff.codeDiff;
          if (codeDiff != null) {
            for (final insn in [...codeDiff.oldRegion, ...codeDiff.newRegion]) {
              _extractInstructionStringLiterals(insn.tokens, changedChannels);
            }
          }
        }
      }
      for (final elfResult in fileSetDiff.elfDiffResults.values) {
        for (final diff in elfResult.breakingDifferences) {
          final codeDiff = diff.codeDiff;
          if (codeDiff != null) {
            for (final insn in [...codeDiff.oldRegion, ...codeDiff.newRegion]) {
              _extractInstructionStringLiterals(insn.tokens, changedChannels);
            }
          }
        }
      }
    } else if (fileSetDiff is AppleFileSetDiff) {
      for (final machOResult in fileSetDiff.machODiffResults.values) {
        for (final diff in machOResult.breakingDifferences) {
          final desc = diff.description;
          final colonIdx = desc.indexOf(':');
          if (colonIdx != -1 && colonIdx + 1 < desc.length) {
            final target = desc.substring(colonIdx + 1).trim();
            if (!target.startsWith('"')) {
              changedClasses.add(target);
            }
          }
          for (final match in _quotedStringRegex.allMatches(desc)) {
            final literal = match.group(1);
            if (literal != null) changedChannels.add(literal);
          }
          final codeDiff = diff.codeDiff;
          if (codeDiff != null) {
            for (final insn in [...codeDiff.oldRegion, ...codeDiff.newRegion]) {
              _extractInstructionStringLiterals(insn.tokens, changedChannels);
            }
          }
        }
      }
    }
  }

  static void _extractInstructionStringLiterals(
    String tokens,
    Set<String> target,
  ) {
    for (final part in tokens.split(',')) {
      if (part.startsWith('S:') && part.length > 2) {
        target.add(part.substring(2));
      }
    }
  }

  static String? _findModifiedChannelOwner({
    required DartPlatformChannel channel,
    required Set<String> changedClasses,
    required Set<String> changedChannels,
    required Map<String, Set<String>> channelOwners,
  }) {
    if (changedChannels.contains(channel.name)) {
      return channel.name;
    }

    final explicitOwners = channelOwners[channel.name];
    if (explicitOwners != null) {
      for (final owner in explicitOwners) {
        if (changedClasses.contains(owner)) {
          return owner;
        }
      }
    }

    for (final cls in changedClasses) {
      if (_classMatchesChannel(cls, channel)) {
        return cls;
      }
    }

    return null;
  }

  static bool _classMatchesChannel(String rawClass, DartPlatformChannel ch) {
    final simpleNames = _simpleClassNames(rawClass);
    if (simpleNames.isEmpty) return false;

    if (ch.kind == DartChannelKind.pigeon ||
        ch.name.startsWith(pigeonChannelPrefix)) {
      // Pigeon channels have the form:
      // dev.flutter.pigeon.<package>.<ApiClass>.<method>
      final segments = ch.name.split('.');
      for (final simple in simpleNames) {
        if (segments.contains(simple)) return true;
      }
      return false;
    }

    final channelLower = ch.name.toLowerCase();
    final channelSegments = channelLower
        .split(RegExp(r'[/.\-_:]'))
        .where((s) => s.isNotEmpty)
        .toSet();

    for (final simple in simpleNames) {
      final lower = simple.toLowerCase();
      if (channelSegments.contains(lower)) return true;
      final stem = lower.replaceFirst(
        RegExp(r'(?:plugin|handler|channel|bridge|hostapi|api)$'),
        '',
      );
      if (stem.length >= 3 && channelSegments.contains(stem)) {
        return true;
      }
    }
    return false;
  }

  static Set<String> _simpleClassNames(String rawClass) {
    var normalized = rawClass.trim();
    if (normalized.startsWith('L') && normalized.endsWith(';')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    final lastSlash = normalized.lastIndexOf('/');
    final afterSlash = lastSlash == -1
        ? normalized
        : normalized.substring(lastSlash + 1);
    final lastDot = afterSlash.lastIndexOf('.');
    final base = lastDot == -1 ? afterSlash : afterSlash.substring(lastDot + 1);
    if (base.isEmpty) return const {};
    return {
      base,
      for (final part in base.split(r'$'))
        if (part.isNotEmpty) part,
    };
  }
}

class _KernelReader {
  _KernelReader(this.bytes, {required this.offset});

  final Uint8List bytes;
  int offset;

  int get remaining => bytes.length - offset;

  int readByte() {
    if (offset >= bytes.length) {
      throw const FormatException('Unexpected EOF in Dart .dill binary.');
    }
    return bytes[offset++];
  }

  int readUInt() {
    final b0 = readByte();
    if ((b0 & 0x80) == 0) {
      return b0;
    }
    if ((b0 & 0xc0) == 0x80) {
      final b1 = readByte();
      return ((b0 & 0x3f) << 8) | b1;
    }
    final b1 = readByte();
    final b2 = readByte();
    final b3 = readByte();
    return ((b0 & 0x3f) << 24) | (b1 << 16) | (b2 << 8) | b3;
  }
}
