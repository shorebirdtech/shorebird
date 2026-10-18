import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/release_bundle.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();
  const manifestName = ReleaseBundle.manifestFileName;
  group(ReleaseBundle, () {
    late Directory tempDir;
    late File bundleFile;
    late Directory extractDir;

    File writeFile(String path, String contents) {
      return File(p.join(tempDir.path, 'build', path))
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
    }

    ReleaseBundle androidBundle({ReleaseArtifactUpload? supplement}) {
      return ReleaseBundle(
        appId: 'app-id',
        flavor: 'internal',
        target: 'lib/main_internal.dart',
        releaseType: ReleaseType.android,
        releaseVersion: '1.0.0+1',
        flutterRevision: 'deadbeef',
        flutterVersion: '3.35.0',
        shorebirdVersion: '1.6.0',
        metadata: const {'platform': 'android', 'generated_apks': false},
        artifacts: [
          ReleaseArtifactUpload(
            file: writeFile('arm64-v8a/libapp.so', 'arm64'),
            name: 'aarch64',
            arch: 'aarch64',
            platform: ReleasePlatform.android,
            canSideload: false,
          ),
          ReleaseArtifactUpload(
            file: writeFile('armeabi-v7a/libapp.so', 'arm'),
            name: 'arm',
            arch: 'arm',
            platform: ReleasePlatform.android,
            canSideload: false,
          ),
          ReleaseArtifactUpload(
            file: writeFile('app-release.aab', 'aab'),
            name: 'aab',
            arch: 'aab',
            platform: ReleasePlatform.android,
            canSideload: true,
            podfileLockHash: 'not-really-android',
          ),
        ],
        supplement: supplement,
      );
    }

    /// Rewrites the manifest in [bundleFile] with [edit] applied.
    void editManifest(void Function(Map<String, dynamic> manifest) edit) {
      final archive = ZipDecoder().decodeBytes(bundleFile.readAsBytesSync());
      final out = Archive();
      for (final file in archive.files) {
        if (file.name == ReleaseBundle.manifestFileName) {
          final manifest =
              jsonDecode(utf8.decode(file.content as List<int>))
                  as Map<String, dynamic>;
          edit(manifest);
          out.addFile(
            ArchiveFile.string(file.name, jsonEncode(manifest)),
          );
        } else {
          out.addFile(file);
        }
      }
      bundleFile.writeAsBytesSync(ZipEncoder().encode(out));
    }

    Matcher throwsBundleError(String containing) => throwsA(
      isA<ReleaseBundleException>().having(
        (e) => e.toString(),
        'message',
        contains(containing),
      ),
    );

    Future<ReleaseBundle> extract() =>
        ReleaseBundle.extract(file: bundleFile, directory: extractDir);

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      bundleFile = File(p.join(tempDir.path, 'out', 'bundle.zip'));
      extractDir = Directory(p.join(tempDir.path, 'extracted'))..createSync();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('round-trips through a zip', () async {
      final bundle = androidBundle();
      await bundle.writeTo(bundleFile);
      final read = await extract();

      expect(read.appId, equals('app-id'));
      expect(read.flavor, equals('internal'));
      expect(read.target, equals('lib/main_internal.dart'));
      expect(read.releaseType, equals(ReleaseType.android));
      expect(read.platform, equals(ReleasePlatform.android));
      expect(read.releaseVersion, equals('1.0.0+1'));
      expect(read.flutterRevision, equals('deadbeef'));
      expect(read.flutterVersion, equals('3.35.0'));
      expect(read.shorebirdVersion, equals('1.6.0'));
      expect(read.metadata, equals(bundle.metadata));
      expect(read.supplement, isNull);
      expect(
        [for (final a in read.artifacts) (a.name, a.arch, a.canSideload)],
        equals([
          ('aarch64', 'aarch64', false),
          ('arm', 'arm', false),
          ('aab', 'aab', true),
        ]),
      );
      expect(read.artifacts.last.podfileLockHash, 'not-really-android');
      // Both libapp.so files survive, though they share a name.
      expect(
        [for (final a in read.artifacts) a.file.readAsStringSync()],
        equals(['arm64', 'arm', 'aab']),
      );
      for (final artifact in read.artifacts) {
        expect(p.isWithin(extractDir.path, artifact.file.path), isTrue);
        expect(artifact.platform, equals(ReleasePlatform.android));
      }
    });

    test('round-trips a supplement', () async {
      await androidBundle(
        supplement: ReleaseArtifactUpload(
          file: writeFile('android_supplement.zip', 'supplement'),
          name: 'supplement',
          arch: 'android_supplement',
          platform: ReleasePlatform.android,
          canSideload: false,
        ),
      ).writeTo(bundleFile);
      final read = await extract();
      expect(read.supplement!.arch, equals('android_supplement'));
      expect(read.supplement!.file.readAsStringSync(), equals('supplement'));
    });

    test('replaces a file already at the destination', () async {
      bundleFile
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      await androidBundle().writeTo(bundleFile);
      expect((await extract()).artifacts, hasLength(3));
    });

    group('extract refuses', () {
      test('a missing file', () {
        expect(extract, throwsBundleError('No file at'));
      });

      test('a file that is not a zip', () {
        bundleFile
          ..createSync(recursive: true)
          ..writeAsStringSync('not a zip');
        expect(extract, throwsBundleError('is not a release bundle'));
      });

      test('a truncated zip', () async {
        await androidBundle().writeTo(bundleFile);
        final bytes = bundleFile.readAsBytesSync();
        bundleFile.writeAsBytesSync(bytes.sublist(0, bytes.length - 10));
        expect(extract, throwsBundleError('is not a release bundle'));
      });

      test('a zip with no manifest', () {
        bundleFile
          ..createSync(recursive: true)
          ..writeAsBytesSync(
            ZipEncoder().encode(
              Archive()..addFile(ArchiveFile.string('other.txt', 'hi')),
            ),
          );
        expect(extract, throwsBundleError('is not a release bundle'));
      });

      test('a bundle from a newer format', () async {
        await androidBundle().writeTo(bundleFile);
        editManifest(
          (m) => m['format_version'] = ReleaseBundle.formatVersion + 1,
        );
        expect(extract, throwsBundleError('newer Shorebird CLI'));
      });

      test('an unknown platform', () async {
        await androidBundle().writeTo(bundleFile);
        editManifest((m) => m['release_type'] = 'fuchsia');
        expect(extract, throwsBundleError('unknown platform "fuchsia"'));
      });

      test('a manifest missing a field', () async {
        await androidBundle().writeTo(bundleFile);
        editManifest((m) => m.remove('app_id'));
        expect(
          extract,
          throwsBundleError('could not be read as a release bundle'),
        );
      });

      test('an artifact the manifest lists but the zip lacks', () async {
        await androidBundle().writeTo(bundleFile);
        editManifest(
          (m) => (m['artifacts'] as List<dynamic>).add({
            'path': 'artifacts/9/missing.so',
            'name': 'x',
            'arch': 'x',
            'can_sideload': false,
            'sha256': '00',
          }),
        );
        expect(extract, throwsBundleError('is missing artifacts/9/missing.so'));
      });

      test('an artifact path outside the bundle', () async {
        await androidBundle().writeTo(bundleFile);
        File(p.join(tempDir.path, 'outside.txt')).writeAsStringSync('x');
        editManifest(
          (m) =>
              (m['artifacts'] as List<dynamic>).first as Map<String, dynamic>
                ..['path'] = '../outside.txt',
        );
        expect(extract, throwsBundleError('not a path inside the bundle'));
      });

      for (final path in [
        '/etc/passwd',
        'artifacts/../../escape',
        'artifacts/./0/x',
        'artifacts//x',
        r'artifacts\..\x',
        '',
      ]) {
        test('an artifact path "$path"', () async {
          await androidBundle().writeTo(bundleFile);
          editManifest(
            (m) =>
                (m['artifacts'] as List<dynamic>).first as Map<String, dynamic>
                  ..['path'] = path,
          );
          expect(extract, throwsBundleError('not a path inside the bundle'));
        });
      }

      test('an artifact that is a link', () async {
        await androidBundle().writeTo(bundleFile);
        final archive = ZipDecoder().decodeBytes(bundleFile.readAsBytesSync());
        final out = Archive();
        for (final file in archive.files) {
          if (file.name == 'artifacts/0/libapp.so') {
            out.addFile(
              _symlink(file.name, '../../$manifestName'),
            );
          } else {
            out.addFile(file);
          }
        }
        bundleFile.writeAsBytesSync(ZipEncoder().encode(out));
        expect(
          extract,
          throwsBundleError('is missing artifacts/0/libapp.so'),
        );
      });
    });

    test('follows no link in the zip, even along a listed path', () async {
      // The manifest lists a file whose path runs through link entries. The
      // links are never created, so the file lands inside the directory, as
      // a plain file under plain directories.
      await androidBundle().writeTo(bundleFile);
      final archive = ZipDecoder().decodeBytes(bundleFile.readAsBytesSync())
        ..addFile(_symlink('a/b/c', '..'))
        ..addFile(_symlink('a/b/c/d', '../..'))
        ..addFile(ArchiveFile.string('a/b/c/d/escaped.txt', 'gotcha'));
      bundleFile.writeAsBytesSync(ZipEncoder().encode(archive));
      final digest = sha256.convert(utf8.encode('gotcha')).toString();
      editManifest(
        (m) => (m['artifacts'] as List<dynamic>).add({
          'path': 'a/b/c/d/escaped.txt',
          'name': 'x',
          'arch': 'x',
          'can_sideload': false,
          'sha256': digest,
        }),
      );

      final read = await extract();

      final escaped = read.artifacts.last.file;
      expect(p.isWithin(extractDir.path, escaped.path), isTrue);
      expect(
        FileSystemEntity.typeSync(
          p.join(extractDir.path, 'a', 'b', 'c'),
          followLinks: false,
        ),
        equals(FileSystemEntityType.directory),
      );
      expect(
        tempDir
            .listSync(recursive: true)
            .where((e) => p.basename(e.path) == 'escaped.txt')
            .map((e) => e.path),
        equals([escaped.path]),
      );
    });

    test('writes nothing outside its directory from a crafted zip', () async {
      // Links through earlier links are how a naive extractor escapes its
      // directory. Only the manifest and the files it lists are written, so
      // none of these entries is.
      await androidBundle().writeTo(bundleFile);
      final archive = ZipDecoder().decodeBytes(bundleFile.readAsBytesSync())
        ..addFile(_symlink('a/b/c', '..'))
        ..addFile(_symlink('a/b/c/d', '../..'))
        ..addFile(ArchiveFile.string('a/b/c/d/escaped.txt', 'gotcha'))
        ..addFile(ArchiveFile.string('../escaped2.txt', 'gotcha'));
      bundleFile.writeAsBytesSync(ZipEncoder().encode(archive));

      await extract();

      final written = extractDir
          .listSync(recursive: true)
          .map((e) => p.relative(e.path, from: extractDir.path))
          .toSet();
      expect(written, isNot(contains('a')));
      expect(
        tempDir.listSync(recursive: true).map((e) => p.basename(e.path)),
        isNot(anyOf(contains('escaped.txt'), contains('escaped2.txt'))),
      );
    });

    group('extract refuses, besides', () {
      test('a bundle with no artifacts', () async {
        await androidBundle().writeTo(bundleFile);
        editManifest((m) => m['artifacts'] = <dynamic>[]);
        expect(extract, throwsBundleError('lists no artifacts'));
      });

      test('a manifest that is a link', () async {
        bundleFile
          ..createSync(recursive: true)
          ..writeAsBytesSync(
            ZipEncoder().encode(
              Archive()..addFile(_symlink(manifestName, '/etc/passwd')),
            ),
          );
        expect(extract, throwsBundleError('is not a release bundle'));
      });

      test('an artifact whose contents changed', () async {
        await androidBundle().writeTo(bundleFile);
        editManifest(
          (m) =>
              (m['artifacts'] as List<dynamic>).first as Map<String, dynamic>
                ..['sha256'] = '00',
        );
        expect(extract, throwsBundleError('does not match the hash'));
      });
    });
  });
}

/// A zip entry that is a symbolic link from [name] to [target], encoded as a
/// Unix zip tool encodes one: link mode, with the target as its contents.
ArchiveFile _symlink(String name, String target) =>
    ArchiveFile.bytes(name, utf8.encode(target))..mode = 0xA1FF;
