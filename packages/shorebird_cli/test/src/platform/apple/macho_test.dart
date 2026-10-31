import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/platform/apple/macho.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(MachO, () {
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

      test('returns null for a file shorter than a Mach-O header', () {
        final file = File(
          p.join(Directory.systemTemp.createTempSync().path, 'app.symbols'),
        )..writeAsBytesSync([0xcf, 0xfa]);
        expect(MachO.debugInfoSize(file), isNull);
      });
    });
  });
}
