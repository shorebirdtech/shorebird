// cspell:words Ünïcøde
import 'dart:convert';
import 'dart:typed_data';

import 'package:shorebird_cli/src/symbols/sbsymbols.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The fields of a SBSY v1 file, read back the way a symbolicator does.
class _Decoded {
  _Decoded(this.bytes)
    : data = ByteData.sublistView(bytes),
      magic = utf8.decode(Uint8List.sublistView(bytes, 0, 4));

  final Uint8List bytes;
  final ByteData data;
  final String magic;

  int get version => data.getUint16(4, Endian.little);
  int get flags => data.getUint16(6, Endian.little);
  int get imageCount => data.getUint16(8, Endian.little);
  int get reserved => data.getUint16(10, Endian.little);
  int get rangeCount => data.getUint32(12, Endian.little);
  int get stringsLength => data.getUint32(16, Endian.little);

  int get _imagesStart => 20;
  int get _rangesStart => _imagesStart + imageCount * 4;
  int get _stringsStart => _rangesStart + rangeCount * 16;

  String stringAt(int offset) {
    final strings = Uint8List.sublistView(
      bytes,
      _stringsStart,
      _stringsStart + stringsLength,
    );
    var end = offset;
    while (strings[end] != 0) {
      end++;
    }
    return utf8.decode(Uint8List.sublistView(strings, offset, end));
  }

  List<String> get images => [
    for (var i = 0; i < imageCount; i++)
      stringAt(data.getUint32(_imagesStart + i * 4, Endian.little)),
  ];

  List<({String image, int start, int size, String name})> get ranges => [
    for (var i = 0; i < rangeCount; i++)
      (
        image: images[data.getUint16(_rangesStart + i * 16, Endian.little)],
        start: data.getUint32(_rangesStart + i * 16 + 4, Endian.little),
        size: data.getUint32(_rangesStart + i * 16 + 8, Endian.little),
        name: stringAt(
          data.getUint32(_rangesStart + i * 16 + 12, Endian.little),
        ),
      ),
  ];

  int get rangeReservedAt0 => data.getUint16(_rangesStart + 2, Endian.little);
}

void main() {
  useTempWorkingDirectory();
  group('encodeSbsymbols', () {
    test('writes a SBSY v1 header the reader recognizes', () {
      final decoded = _Decoded(
        encodeSbsymbols({
          SymbolImage.release: [(start: 16, size: 8, name: 'main')],
        }),
      );

      expect(decoded.magic, equals('SBSY'));
      expect(decoded.version, equals(1));
      expect(decoded.flags, isZero);
      expect(decoded.reserved, isZero);
      expect(decoded.rangeReservedAt0, isZero);
      expect(decoded.imageCount, equals(1));
      expect(decoded.rangeCount, equals(1));
      expect(decoded.images, equals(['release']));
      expect(
        decoded.ranges,
        equals([(image: 'release', start: 16, size: 8, name: 'main')]),
      );
    });

    test('names the image by its enum name', () {
      expect(
        _Decoded(
          encodeSbsymbols({
            SymbolImage.vmcode: [(start: 0, size: 4, name: 'patched')],
          }),
        ).images,
        equals(['vmcode']),
      );
    });

    test("sorts an image's ranges by start offset", () {
      expect(
        _Decoded(
          encodeSbsymbols({
            SymbolImage.release: [
              (start: 32, size: 8, name: 'second'),
              (start: 8, size: 8, name: 'first'),
              (start: 64, size: 8, name: 'third'),
            ],
          }),
        ).ranges.map((range) => range.name),
        equals(['first', 'second', 'third']),
      );
    });

    test('writes one string per distinct name', () {
      final decoded = _Decoded(
        encodeSbsymbols({
          SymbolImage.release: [
            (start: 8, size: 8, name: 'shared'),
            (start: 16, size: 8, name: 'shared'),
          ],
        }),
      );

      // 'release\0shared\0'.
      expect(decoded.stringsLength, equals(15));
      expect(
        decoded.ranges.map((range) => range.name),
        equals(['shared', 'shared']),
      );
    });

    test('encodes a name as UTF-8', () {
      expect(
        _Decoded(
          encodeSbsymbols({
            SymbolImage.release: [(start: 8, size: 8, name: 'Ünïcøde')],
          }),
        ).ranges.single.name,
        equals('Ünïcøde'),
      );
    });

    test('leaves out a range no program counter can fall in', () {
      expect(
        _Decoded(
          encodeSbsymbols({
            SymbolImage.release: [
              (start: 8, size: 0, name: 'empty'),
              (start: -8, size: 8, name: 'negative start'),
              (start: 16, size: 8, name: 'kept'),
            ],
          }),
        ).ranges.map((range) => range.name),
        equals(['kept']),
      );
    });

    test('leaves out a range that does not fit a uint32', () {
      expect(
        _Decoded(
          encodeSbsymbols({
            SymbolImage.release: [
              (start: 0x1_0000_0000, size: 8, name: 'past the start'),
              (start: 8, size: 0x1_0000_0000, name: 'past the size'),
              (start: 16, size: 8, name: 'kept'),
            ],
          }),
        ).ranges.map((range) => range.name),
        equals(['kept']),
      );
    });

    test('indexes each image the ranges belong to', () {
      final decoded = _Decoded(
        encodeSbsymbols({
          SymbolImage.release: [(start: 8, size: 8, name: 'released')],
          SymbolImage.vmcode: [(start: 8, size: 8, name: 'patched')],
        }),
      );

      expect(decoded.images, equals(['release', 'vmcode']));
      expect(
        decoded.ranges,
        equals([
          (image: 'release', start: 8, size: 8, name: 'released'),
          (image: 'vmcode', start: 8, size: 8, name: 'patched'),
        ]),
      );
    });

    test('writes a header and nothing else when there is nothing to index', () {
      final decoded = _Decoded(encodeSbsymbols(const {}));

      expect(decoded.bytes, hasLength(20));
      expect(decoded.imageCount, isZero);
      expect(decoded.rangeCount, isZero);
      expect(decoded.stringsLength, isZero);
    });
  });
}
