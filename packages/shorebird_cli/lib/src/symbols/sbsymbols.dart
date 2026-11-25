import 'dart:convert';
import 'dart:typed_data';

/// One symbol's address range within an image: where it starts, how long it
/// is, and the name a frame inside it resolves to.
typedef SbsymbolsRange = ({int start, int size, String name});

/// The image a crash report's program counter offsets are measured against.
///
/// The name is the contract: a crash report names its image with the same
/// string, and a range in the index is only ever matched against the image it
/// was measured in.
enum SymbolImage {
  /// The release's compiled snapshot, linked into the app binary.
  release,

  /// A patch's compiled code, which a device runs in place of the release's.
  vmcode,
}

/// `SBSY`, the version, the flags, the image count, the reserved field, the
/// range count and the string table's length.
const _headerSize = 20;

/// The image index, a reserved field, the start offset, the size and the
/// name offset.
const _rangeSize = 16;

/// A start offset, a size and a string table offset are each a `uint32`.
const _maxUint32 = 0xffffffff;

/// Encodes [rangesByImage] as a SBSY v1 symbol index.
///
/// The format is a sorted address-range table rather than DWARF because
/// symbolication reads it on a server that cannot hold a release's DWARF in
/// memory. Ranges are sorted by start offset per image, which is what lets a
/// reader binary-search them. A reader rejects an unsorted table rather than
/// answer with the wrong function, so sorting happens here.
///
/// A range whose start, size or name offset does not fit in a `uint32`, or
/// whose size is zero, is left out: the first cannot be represented and the
/// second covers no program counter.
Uint8List encodeSbsymbols(
  Map<SymbolImage, List<SbsymbolsRange>> rangesByImage,
) {
  final strings = BytesBuilder(copy: false);
  final stringOffsets = <String, int>{};

  int offsetOf(String value) {
    final existing = stringOffsets[value];
    if (existing != null) return existing;
    final offset = strings.length;
    strings
      ..add(utf8.encode(value))
      ..addByte(0);
    return stringOffsets[value] = offset;
  }

  final images = rangesByImage.keys.toList();
  final imageNameOffsets = [for (final image in images) offsetOf(image.name)];

  final rows = <({int imageIndex, int start, int size, int nameOffset})>[];
  for (final (imageIndex, image) in images.indexed) {
    final ranges = [...rangesByImage[image]!]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final range in ranges) {
      if (range.size <= 0 || range.start < 0) continue;
      if (range.start > _maxUint32 || range.size > _maxUint32) continue;
      final nameOffset = offsetOf(range.name);
      if (nameOffset > _maxUint32) continue;
      rows.add((
        imageIndex: imageIndex,
        start: range.start,
        size: range.size,
        nameOffset: nameOffset,
      ));
    }
  }

  final stringBytes = strings.takeBytes();
  final bytes = Uint8List(
    _headerSize +
        images.length * 4 +
        rows.length * _rangeSize +
        stringBytes.length,
  );
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, utf8.encode('SBSY'));
  data
    ..setUint16(4, 1, Endian.little)
    ..setUint16(6, 0, Endian.little)
    ..setUint16(8, images.length, Endian.little)
    ..setUint16(10, 0, Endian.little)
    ..setUint32(12, rows.length, Endian.little)
    ..setUint32(16, stringBytes.length, Endian.little);

  var offset = _headerSize;
  for (final nameOffset in imageNameOffsets) {
    data.setUint32(offset, nameOffset, Endian.little);
    offset += 4;
  }
  for (final row in rows) {
    data
      ..setUint16(offset, row.imageIndex, Endian.little)
      ..setUint16(offset + 2, 0, Endian.little)
      ..setUint32(offset + 4, row.start, Endian.little)
      ..setUint32(offset + 8, row.size, Endian.little)
      ..setUint32(offset + 12, row.nameOffset, Endian.little);
    offset += _rangeSize;
  }
  bytes.setRange(offset, offset + stringBytes.length, stringBytes);

  return bytes;
}
