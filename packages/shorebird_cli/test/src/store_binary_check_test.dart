// cspell:words LINKEDIT linkedit
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/release_bundle.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/store_binary_check.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A minimal 64-bit Mach-O binary: a `__TEXT` segment with one `__text`
/// section holding [text], and a `__LINKEDIT` segment holding [signature].
/// [extraCommands] adds that many 16-byte load commands, as signing an
/// unsigned binary adds LC_CODE_SIGNATURE.
Uint8List machO(
  String text, {
  String signature = '',
  int extraCommands = 0,
}) {
  const headerSize = 32;
  const textCommandSize = 72 + 80;
  const linkeditCommandSize = 72;
  final commandsSize =
      textCommandSize + linkeditCommandSize + 16 * extraCommands;
  final textOffset = headerSize + commandsSize;
  final linkeditOffset = textOffset + text.length;
  final bytes = Uint8List(linkeditOffset + signature.length);
  final data = ByteData.sublistView(bytes);
  void name(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);

  data
    ..setUint32(0, 0xfeedfacf, Endian.little)
    ..setUint32(16, 2 + extraCommands, Endian.little)
    ..setUint32(20, commandsSize, Endian.little);

  var command = headerSize;
  data
    ..setUint32(command, 0x19, Endian.little)
    ..setUint32(command + 4, textCommandSize, Endian.little)
    ..setUint64(command + 48, linkeditOffset, Endian.little)
    ..setUint32(command + 64, 1, Endian.little);
  name(command + 8, '__TEXT');
  final section = command + 72;
  name(section, '__text');
  name(section + 16, '__TEXT');
  data
    ..setUint64(section + 40, text.length, Endian.little)
    ..setUint32(section + 48, textOffset, Endian.little);

  command += textCommandSize;
  data
    ..setUint32(command, 0x19, Endian.little)
    ..setUint32(command + 4, linkeditCommandSize, Endian.little)
    ..setUint64(command + 40, linkeditOffset, Endian.little)
    ..setUint64(command + 48, signature.length, Endian.little);
  name(command + 8, '__LINKEDIT');

  command += linkeditCommandSize;
  for (var i = 0; i < extraCommands; i++) {
    data
      ..setUint32(command, 0x1d, Endian.little)
      ..setUint32(command + 4, 16, Endian.little);
    command += 16;
  }

  bytes.setRange(textOffset, linkeditOffset, text.codeUnits);
  bytes.setRange(linkeditOffset, bytes.length, signature.codeUnits);
  return bytes;
}

/// A universal binary of [slices].
Uint8List fat(List<Uint8List> slices) {
  const alignment = 4096;
  final offsets = <int>[];
  var offset = alignment;
  for (final slice in slices) {
    offsets.add(offset);
    offset += (slice.length + alignment - 1) ~/ alignment * alignment;
  }
  final bytes = Uint8List(offset);
  final data = ByteData.sublistView(bytes)
    ..setUint32(0, 0xcafebabe)
    ..setUint32(4, slices.length);
  for (final (i, slice) in slices.indexed) {
    data
      ..setUint32(8 + i * 20 + 8, offsets[i])
      ..setUint32(8 + i * 20 + 12, slice.length);
    bytes.setRange(offsets[i], offsets[i] + slice.length, slice);
  }
  return bytes;
}

void main() {
  useTempWorkingDirectory();
  group(StoreBinaryCheck, () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      addTearDown(() => tempDir.deleteSync(recursive: true));
    });

    File writeFile(String name, List<int> contents) =>
        File(p.join(tempDir.path, name))
          ..createSync(recursive: true)
          ..writeAsBytesSync(contents);

    File writeZip(String name, Map<String, List<int>> entries) {
      final archive = Archive();
      for (final MapEntry(:key, :value) in entries.entries) {
        archive.addFile(ArchiveFile.bytes(key, value));
      }
      return writeFile(name, ZipEncoder().encode(archive));
    }

    ReleaseBundle bundle(
      ReleaseType releaseType,
      List<ReleaseArtifactUpload> artifacts,
    ) => ReleaseBundle(
      appId: 'app-id',
      releaseType: releaseType,
      releaseVersion: '1.0.0+1',
      flutterRevision: 'deadbeef',
      shorebirdVersion: '1.6.0',
      metadata: const {},
      artifacts: artifacts,
    );

    group('machOCodeHash', () {
      test('is the same however the binary is signed', () {
        expect(
          StoreBinaryCheck.machOCodeHash(machO('code', signature: 'one')),
          equals(
            StoreBinaryCheck.machOCodeHash(
              machO('code', signature: 'a longer signature', extraCommands: 1),
            ),
          ),
        );
      });

      test('differs when the code differs', () {
        expect(
          StoreBinaryCheck.machOCodeHash(machO('code')),
          isNot(equals(StoreBinaryCheck.machOCodeHash(machO('other code')))),
        );
      });

      test('covers each slice of a universal binary', () {
        final hash = StoreBinaryCheck.machOCodeHash(
          fat([machO('arm64'), machO('x86_64')]),
        );
        expect(
          StoreBinaryCheck.machOCodeHash(
            fat([
              machO('arm64', signature: 'signed'),
              machO('x86_64', extraCommands: 1),
            ]),
          ),
          equals(hash),
        );
        expect(
          StoreBinaryCheck.machOCodeHash(
            fat([machO('arm64'), machO('x86_65')]),
          ),
          isNot(equals(hash)),
        );
      });

      test('throws a FormatException for a section past the end', () {
        final truncated = machO('code', signature: 'signature');
        expect(
          () => StoreBinaryCheck.machOCodeHash(
            Uint8List.sublistView(truncated, 0, truncated.length - 14),
          ),
          throwsFormatException,
        );
      });

      test('throws a FormatException for a slice past the end', () {
        final bytes = fat([machO('arm64')]);
        ByteData.sublistView(bytes).setUint32(8 + 8, bytes.length + 1);
        expect(
          () => StoreBinaryCheck.machOCodeHash(bytes),
          throwsFormatException,
        );
      });

      test('throws a FormatException for load commands past the end', () {
        final bytes = machO('code');
        ByteData.sublistView(bytes).setUint32(16, 1000, Endian.little);
        expect(
          () => StoreBinaryCheck.machOCodeHash(bytes),
          throwsFormatException,
        );
      });

      test('throws a FormatException for a load command of size 0', () {
        final bytes = machO('code');
        ByteData.sublistView(bytes).setUint32(32 + 4, 0, Endian.little);
        expect(
          () => StoreBinaryCheck.machOCodeHash(bytes),
          throwsFormatException,
        );
      });

      test('throws a FormatException for a file that is not Mach-O', () {
        expect(
          () => StoreBinaryCheck.machOCodeHash(
            Uint8List.fromList('not a binary at all, no'.codeUnits),
          ),
          throwsFormatException,
        );
      });
    });

    group('differences', () {
      test('throws when there is no file', () async {
        await expectLater(
          StoreBinaryCheck.differences(
            bundle: bundle(ReleaseType.android, []),
            storeBinary: File(p.join(tempDir.path, 'missing.aab')),
          ),
          throwsA(
            isA<StoreBinaryException>().having(
              (e) => e.message,
              'message',
              startsWith('No file at'),
            ),
          ),
        );
      });

      test('throws for a platform it cannot check', () async {
        await expectLater(
          StoreBinaryCheck.differences(
            bundle: bundle(ReleaseType.linux, []),
            storeBinary: writeFile('app.zip', [0]),
          ),
          throwsA(
            isA<StoreBinaryException>().having(
              (e) => e.message,
              'message',
              contains('checks Android (.aab, .apk) and iOS (.ipa)'),
            ),
          ),
        );
      });

      group('for an Android release', () {
        late ReleaseBundle androidBundle;

        ReleaseArtifactUpload libapp(String arch, String contents) =>
            ReleaseArtifactUpload(
              file: writeFile(p.join('bundle', arch, 'libapp.so'), [
                ...contents.codeUnits,
              ]),
              name: arch,
              arch: arch,
              platform: ReleasePlatform.android,
              canSideload: false,
            );

        setUp(() {
          androidBundle = bundle(ReleaseType.android, [
            libapp('aarch64', 'arm64 code'),
            libapp('arm', 'arm32 code'),
            ReleaseArtifactUpload(
              file: writeFile(p.join('bundle', 'app.aab'), [1, 2, 3]),
              name: 'aab',
              arch: 'aab',
              platform: ReleasePlatform.android,
              canSideload: true,
            ),
          ]);
        });

        Future<List<String>> differences(File storeBinary) =>
            StoreBinaryCheck.differences(
              bundle: androidBundle,
              storeBinary: storeBinary,
            );

        test('finds none in an .aab built from the same build', () async {
          final aab = writeZip('app.aab', {
            'base/lib/arm64-v8a/libapp.so': 'arm64 code'.codeUnits,
            'base/lib/armeabi-v7a/libapp.so': 'arm32 code'.codeUnits,
            // Signing adds files, which are not compared.
            'META-INF/UPLOAD.SF': 'signature'.codeUnits,
          });
          expect(await differences(aab), isEmpty);
        });

        test('lists each libapp.so that differs', () async {
          final aab = writeZip('app.aab', {
            'base/lib/arm64-v8a/libapp.so': 'other code'.codeUnits,
            'base/lib/armeabi-v7a/libapp.so': 'arm32 code'.codeUnits,
          });
          expect(
            await differences(aab),
            equals([
              'arm64-v8a: libapp.so in app.aab is not the one in the bundle',
            ]),
          );
        });

        test('lists ABIs only one of them has', () async {
          final aab = writeZip('app.aab', {
            'base/lib/arm64-v8a/libapp.so': 'arm64 code'.codeUnits,
            'base/lib/x86_64/libapp.so': 'x86 code'.codeUnits,
          });
          expect(
            await differences(aab),
            unorderedEquals([
              'armeabi-v7a: in the bundle, but not in app.aab',
              'x86_64: in app.aab, but not in the bundle',
            ]),
          );
        });

        test('accepts a split .apk with one of the ABIs', () async {
          final apk = writeZip('app-arm64-v8a.apk', {
            'lib/arm64-v8a/libapp.so': 'arm64 code'.codeUnits,
          });
          expect(await differences(apk), isEmpty);
        });

        test('throws when the file has no libapp.so', () async {
          final aab = writeZip('app.aab', {'base/manifest': 'x'.codeUnits});
          await expectLater(
            differences(aab),
            throwsA(
              isA<StoreBinaryException>().having(
                (e) => e.message,
                'message',
                contains('has no libapp.so'),
              ),
            ),
          );
        });

        test('throws when the file cannot be read', () async {
          await expectLater(
            differences(writeFile('app.aab', 'not a zip'.codeUnits)),
            throwsA(isA<StoreBinaryException>()),
          );
        });

        test('throws for a file that is not an .aab or .apk', () async {
          await expectLater(
            differences(writeFile('app.ipa', [0])),
            throwsA(
              isA<StoreBinaryException>().having(
                (e) => e.message,
                'message',
                contains('is not an .aab or .apk'),
              ),
            ),
          );
        });
      });

      group('for an iOS release', () {
        late ReleaseBundle iosBundle;

        setUp(() {
          final xcarchive = writeZip(p.join('bundle', 'Runner.xcarchive.zip'), {
            'Products/Applications/Runner.app/Frameworks/App.framework/App':
                machO('dart code', signature: 'development'),
          });
          iosBundle = bundle(ReleaseType.ios, [
            ReleaseArtifactUpload(
              file: xcarchive,
              name: 'xcarchive',
              arch: 'xcarchive',
              platform: ReleasePlatform.ios,
              canSideload: false,
            ),
          ]);
        });

        File ipa(Uint8List app) => writeZip('Runner.ipa', {
          'Payload/Runner.app/Frameworks/App.framework/App': app,
        });

        Future<List<String>> differences(File storeBinary) =>
            StoreBinaryCheck.differences(
              bundle: iosBundle,
              storeBinary: storeBinary,
            );

        test('finds none in an .ipa built from the same build, though it is '
            'signed differently', () async {
          expect(
            await differences(
              ipa(machO('dart code', signature: 'distribution')),
            ),
            isEmpty,
          );
        });

        test('reads the .xcarchive as the release zips it', () async {
          final xcarchiveDirectory = Directory(
            p.join(tempDir.path, 'Runner.xcarchive'),
          );
          File(
              p.joinAll([
                xcarchiveDirectory.path,
                ...'Products/Applications/Runner.app/Frameworks/App.framework/App'
                    .split('/'),
              ]),
            )
            ..createSync(recursive: true)
            ..writeAsBytesSync(machO('dart code'));
          final zipped = await xcarchiveDirectory.zipInto(
            Directory(p.join(tempDir.path, 'staging'))..createSync(),
          );
          iosBundle = bundle(ReleaseType.ios, [
            ReleaseArtifactUpload(
              file: zipped,
              name: 'xcarchive',
              arch: 'xcarchive',
              platform: ReleasePlatform.ios,
              canSideload: false,
            ),
          ]);
          expect(await differences(ipa(machO('dart code'))), isEmpty);
        });

        test("throws when the bundle's .xcarchive cannot be read", () async {
          iosBundle = bundle(ReleaseType.ios, [
            ReleaseArtifactUpload(
              file: writeZip('bad.xcarchive.zip', {
                'Products/Applications/Runner.app/Frameworks/App.framework/App':
                    'not mach-o'.codeUnits,
              }),
              name: 'xcarchive',
              arch: 'xcarchive',
              platform: ReleasePlatform.ios,
              canSideload: false,
            ),
          ]);
          await expectLater(
            differences(ipa(machO('dart code'))),
            throwsA(
              isA<StoreBinaryException>().having(
                (e) => e.message,
                'message',
                startsWith("Could not read the bundle's .xcarchive"),
              ),
            ),
          );
        });

        test('reports an App.framework built from other code', () async {
          expect(
            await differences(ipa(machO('other code'))),
            equals([
              'App.framework in Runner.ipa is not the one in the bundle',
            ]),
          );
        });

        test('throws when the .ipa has no App.framework', () async {
          await expectLater(
            differences(
              writeZip('Runner.ipa', {
                'Payload/x': [0],
              }),
            ),
            throwsA(
              isA<StoreBinaryException>().having(
                (e) => e.message,
                'message',
                contains('has no Payload/*.app/Frameworks/App.framework/App'),
              ),
            ),
          );
        });

        test('throws when its App.framework is not a Mach-O binary', () async {
          await expectLater(
            differences(ipa(Uint8List.fromList('not mach-o'.codeUnits))),
            throwsA(
              isA<StoreBinaryException>().having(
                (e) => e.message,
                'message',
                startsWith('Could not read'),
              ),
            ),
          );
        });

        test(
          "throws when the bundle's .xcarchive has no App.framework",
          () async {
            iosBundle = bundle(ReleaseType.ios, [
              ReleaseArtifactUpload(
                file: writeZip('empty.xcarchive.zip', {
                  'Info.plist': [0],
                }),
                name: 'xcarchive',
                arch: 'xcarchive',
                platform: ReleasePlatform.ios,
                canSideload: false,
              ),
            ]);
            await expectLater(
              differences(ipa(machO('dart code'))),
              throwsA(
                isA<StoreBinaryException>().having(
                  (e) => e.message,
                  'message',
                  contains('has no App.framework'),
                ),
              ),
            );
          },
        );

        test('throws when the bundle has no .xcarchive', () async {
          iosBundle = bundle(ReleaseType.ios, []);
          await expectLater(
            differences(ipa(machO('dart code'))),
            throwsA(isA<StoreBinaryException>()),
          );
        });

        test('throws for a file that is not an .ipa', () async {
          await expectLater(
            differences(writeFile('app.aab', [0])),
            throwsA(
              isA<StoreBinaryException>().having(
                (e) => e.message,
                'message',
                contains('is not an .ipa'),
              ),
            ),
          );
        });
      });
    });
  });
}
