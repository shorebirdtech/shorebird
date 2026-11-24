import 'dart:io';

import 'package:elf/elf.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/symbols/sbsymbols.dart';

/// A reference to a [SymbolExtractor] instance.
final symbolExtractorRef = create(SymbolExtractor.new);

/// The [SymbolExtractor] instance available in the current zone.
SymbolExtractor get symbolExtractor => read(symbolExtractorRef);

/// {@template symbol_extractor}
/// Turns the debug info a Dart build leaves behind into the symbol index
/// crash symbolication reads.
/// {@endtemplate}
class SymbolExtractor {
  /// {@macro symbol_extractor}
  const SymbolExtractor();

  /// Writes the SBSY v1 index of the functions in [debugInfo] to [output],
  /// measured against [image], and returns it.
  ///
  /// Returns null when [debugInfo] names no functions, which is the ordinary
  /// answer for a build whose names live only in DWARF: `flutter build ipa`
  /// takes its debug info from `dsymutil` rather than from gen_snapshot's
  /// `--save-debugging-info`, and a dSYM carries no function symbols. A
  /// release with no index is symbolicated as raw offsets rather than failing.
  File? writeIndex({
    required File debugInfo,
    required File output,
    required SymbolImage image,
  }) {
    final ranges = _readRanges(debugInfo);
    if (ranges.isEmpty) return null;
    output.parent.createSync(recursive: true);
    return output..writeAsBytesSync(encodeSbsymbols({image: ranges}));
  }

  /// Writes [source] gzipped to [destination] and returns it.
  File compress({required File source, required File destination}) {
    destination.parent.createSync(recursive: true);
    return destination..writeAsBytesSync(gzip.encode(source.readAsBytesSync()));
  }

  /// The address ranges of the functions [debugInfo] names.
  ///
  /// Read from `.symtab`, which gen_snapshot's debug output carries one entry
  /// in per compiled function, with the same addresses as the snapshot it was
  /// built beside. `.dynsym` is deliberately not a fallback: it names the
  /// snapshot's blobs rather than its functions, and a range covering a whole
  /// blob would answer every offset inside it with the blob's name.
  List<SbsymbolsRange> _readRanges(File debugInfo) {
    final ElfFile elf;
    try {
      elf = const ElfParser().parse(debugInfo.readAsBytesSync());
    } on FormatException catch (error) {
      logger.detail('${debugInfo.path} is not readable as an ELF: $error');
      return const [];
    }
    return [
      for (final symbol in elf.staticSymbols)
        if (symbol.isFunction && symbol.size > 0 && symbol.name.isNotEmpty)
          (start: symbol.value, size: symbol.size, name: symbol.name),
    ];
  }
}
