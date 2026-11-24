import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(MachO, () {
    group('architectures', () {
      File writeHeader(Uint8List bytes) => File(
        p.join(Directory.systemTemp.createTempSync().path, 'App'),
      )..writeAsBytesSync(bytes);

      Uint8List thin64Header(int cpuType) {
        final bytes = Uint8List(32);
        ByteData.sublistView(bytes)
          ..setUint32(0, 0xfeedfacf, Endian.little)
          ..setUint32(4, cpuType, Endian.little);
        return bytes;
      }

      test('reads the slice of a thin 64-bit Mach-O', () {
        expect(
          MachO.architectures(writeHeader(thin64Header(0x0100000c))),
          equals({Arch.arm64}),
        );
        expect(
          MachO.architectures(writeHeader(thin64Header(0x01000007))),
          equals({Arch.x86_64}),
        );
      });

      test('reads every slice of a 32-bit universal Mach-O', () {
        final bytes = Uint8List(8 + 2 * 20);
        ByteData.sublistView(bytes)
          ..setUint32(0, 0xcafebabe)
          ..setUint32(4, 2)
          ..setUint32(8, 0x0100000c)
          ..setUint32(28, 0x01000007);
        expect(
          MachO.architectures(writeHeader(bytes)),
          equals({Arch.arm64, Arch.x86_64}),
        );
      });

      test('reads every slice of a 64-bit universal Mach-O', () {
        final bytes = Uint8List(8 + 32);
        ByteData.sublistView(bytes)
          ..setUint32(0, 0xcafebabf)
          ..setUint32(4, 1)
          ..setUint32(8, 0x0100000c);
        expect(
          MachO.architectures(writeHeader(bytes)),
          equals({Arch.arm64}),
        );
      });

      test(
        'returns null when the file is missing, truncated, or not Mach-O',
        () {
          final dir = Directory.systemTemp.createTempSync();
          expect(
            MachO.architectures(File(p.join(dir.path, 'missing'))),
            isNull,
          );
          expect(MachO.architectures(writeHeader(Uint8List(4))), isNull);
          expect(
            MachO.architectures(writeHeader(thin64Header(0x000000ff))),
            isNull,
          );
          final truncatedFat = Uint8List(12);
          ByteData.sublistView(truncatedFat)
            ..setUint32(0, 0xcafebabe)
            ..setUint32(4, 2);
          expect(MachO.architectures(writeHeader(truncatedFat)), isNull);
        },
      );
    });

    group('debugInfoSize', () {
      File fixture(String name) =>
          File(p.join(fixturesDirectory, 'dsym', name));

      test('returns the size of __debug_info', () {
        expect(MachO.debugInfoSize(fixture('with_debug_info.dwarf')), 69);
      });

      test('returns 0 when the dSYM has no __debug_info', () {
        expect(MachO.debugInfoSize(fixture('no_debug_info.dwarf')), 0);
      });

      test('returns null for a file that is not a 64-bit Mach-O', () {
        final elf = File(
          p.join(Directory.systemTemp.createTempSync().path, 'app.symbols'),
        )..writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46, ...List.filled(60, 0)]);
        expect(MachO.debugInfoSize(elf), isNull);
      });

      test('returns null for a truncated Mach-O', () {
        final bytes = fixture('with_debug_info.dwarf').readAsBytesSync();
        final directory = Directory.systemTemp.createTempSync();
        for (final length in [36, 160, 200]) {
          final file = File(p.join(directory.path, 'app.symbols'))
            ..writeAsBytesSync(bytes.sublist(0, length));
          expect(MachO.debugInfoSize(file), isNull, reason: '$length bytes');
        }
      });

      test('returns null for a load command smaller than its header', () {
        // Zero the first load command's cmdsize, at offset 32 + 4.
        final bytes = fixture('with_debug_info.dwarf').readAsBytesSync()
          ..setRange(36, 40, [0, 0, 0, 0]);
        final file = File(
          p.join(Directory.systemTemp.createTempSync().path, 'app.symbols'),
        )..writeAsBytesSync(bytes);
        expect(MachO.debugInfoSize(file), isNull);
      });

      test('returns null for a file shorter than a Mach-O header', () {
        final file = File(
          p.join(Directory.systemTemp.createTempSync().path, 'app.symbols'),
        )..writeAsBytesSync([0xcf, 0xfa]);
        expect(MachO.debugInfoSize(file), isNull);
      });
    });
  });
}
