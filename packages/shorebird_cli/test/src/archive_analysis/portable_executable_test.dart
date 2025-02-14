import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/portable_executable.dart';
import 'package:test/test.dart';

void main() {
  group(PortableExecutable, () {
    group('when no .rdata section exists', () {
      late File file;

      setUp(() {
        final tempDir = Directory.systemTemp.createTempSync();
        file = File(p.join(tempDir.path, 'my.exe'))
          ..writeAsBytesSync(List.filled(1000, 0));
      });

      test('throws exception', () {
        expect(
          () => PortableExecutable.bytesWithZeroedTimestamps(file),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'string value',
              'Exception: Could not find .rdata section',
            ),
          ),
        );
      });
    });

    group('when given a valid exe', () {
      late File file;
      final winArchivesFixturesBasePath = p.join(
        'test',
        'fixtures',
        'win_archives',
      );
      final releasePath = p.join(winArchivesFixturesBasePath, 'release.zip');

      setUp(() async {
        final tempDir = Directory.systemTemp.createTempSync();
        final inputStream = InputFileStream(releasePath);
        final archive = ZipDecoder().decodeStream(inputStream);
        await extractArchiveToDisk(archive, tempDir.path);
        file = File(p.join(tempDir.path, 'hello_windows.exe'));
      });

      test('zeroes out timestamps', () {
        // Known locations of timestamps in this executable
        const timestampLocations = [0x110, 0x6e14];

        final beforeBytes = file.readAsBytesSync();
        final afterBytes = PortableExecutable.bytesWithZeroedTimestamps(file);
        expect(
          beforeBytes.sublist(timestampLocations[0], timestampLocations[0] + 4),
          isNot(equals([0, 0, 0, 0])),
        );
        expect(
          beforeBytes.sublist(timestampLocations[1], timestampLocations[1] + 4),
          isNot(equals([0, 0, 0, 0])),
        );
        expect(
          afterBytes.sublist(timestampLocations[0], timestampLocations[0] + 4),
          equals([0, 0, 0, 0]),
        );
        expect(
          afterBytes.sublist(timestampLocations[1], timestampLocations[1] + 4),
          equals([0, 0, 0, 0]),
        );
      });
    });
  });
}
