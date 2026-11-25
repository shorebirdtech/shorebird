// cspell:words xcarchive
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/asset_patching/asset_extractor.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(AssetExtractor, () {
    const extractor = AssetExtractor();
    late Directory tempDir;

    File writeZip(
      String name,
      Map<String, List<int>> files, {
      List<String> dirs = const [],
      Map<String, String> symlinks = const {},
    }) {
      final archive = Archive();
      for (final d in dirs) {
        archive.addFile(ArchiveFile.directory(d));
      }
      files.forEach((k, v) => archive.addFile(ArchiveFile(k, v.length, v)));
      symlinks.forEach((k, v) => archive.addFile(ArchiveFile.symlink(k, v)));
      return File(p.join(tempDir.path, name))
        ..writeAsBytesSync(ZipEncoder().encode(archive));
    }

    setUp(() => tempDir = Directory.systemTemp.createTempSync());
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('resolves via scoped ref and checks supported release types', () {
      expect(
        runScoped(() => assetExtractor, values: {assetExtractorRef}),
        isA<AssetExtractor>(),
      );
      const ok = {ReleaseType.android, ReleaseType.ios, ReleaseType.macos};
      for (final type in ReleaseType.values) {
        expect(AssetExtractor.supportsReleaseType(type), ok.contains(type));
      }
    });

    group('when releaseType is android', () {
      test('extracts base/assets/flutter_assets/ and real fixture', () async {
        final aab = writeZip(
          'app.aab',
          {
            'base/assets/flutter_assets/assets/logo.png': [1, 2, 3],
            'base/assets/other.txt': [9],
          },
          dirs: const ['base/assets/flutter_assets/assets/'],
        );
        final out = await extractor.extractFlutterAssets(
          archive: aab,
          releaseType: ReleaseType.android,
        );
        expect(out, {
          'assets/logo.png': [1, 2, 3],
        });
        expect(() => out['assets/logo.png']![0] = 9, throwsUnsupportedError);

        final baseAab = File(p.join(fixturesDirectory, 'aabs', 'base.aab'));
        final fixture = await extractor.extractFlutterAssets(
          archive: baseAab,
          releaseType: ReleaseType.android,
        );
        expect(fixture.keys, containsAll(['AssetManifest.bin', 'NOTICES.Z']));
      });
    });

    group('when releaseType is ios', () {
      test(
        'extracts Runner.app and xcarchive while skipping sidecars',
        () async {
          const ext = 'Runner.app/PlugIns/Ext.appex/Frameworks/App.framework';
          final appZip = writeZip('ios.zip', {
            'Runner.app/Frameworks/App.framework/flutter_assets/c.json': [123],
            '$ext/flutter_assets/ignored.json': [1],
          });
          final appOut = await extractor.extractFlutterAssets(
            archive: appZip,
            releaseType: ReleaseType.ios,
          );
          expect(appOut.keys, ['c.json']);

          const xc =
              'Products/Applications/App.app/Frameworks/App.framework/'
              'flutter_assets';
          final xcZip = writeZip('xc.zip', {
            '$xc/img/hero.png': [10, 20],
            '$xc/img/._hero.png': [0x00, 0x05, 0x16, 0x07, 0x01],
            '$xc/img/._short': [0x00, 0x05],
          });
          final xcOut = await extractor.extractFlutterAssets(
            archive: xcZip,
            releaseType: ReleaseType.ios,
          );
          expect(xcOut.keys, ['img/._short', 'img/hero.png']);
        },
      );
    });

    group('when releaseType is macos', () {
      test(
        'extracts Versions/A/Resources/flutter_assets/ and .app root',
        () async {
          const root =
              'Contents/Frameworks/App.framework/Versions/A/Resources/'
              'flutter_assets';
          final zip = writeZip(
            'macos.zip',
            {
              '$root/data/cfg.json': utf8.encode('{}'),
              'Contents/Frameworks/App.framework/Resources/flutter_assets/x': [
                1,
              ],
            },
            symlinks: const {'$root/link.json': 'data/cfg.json'},
          );
          final out = await extractor.extractFlutterAssets(
            archive: zip,
            releaseType: ReleaseType.macos,
          );
          expect(out.keys, ['data/cfg.json']);

          final wrapped = writeZip('w.zip', {
            'App.app/$root/f.ttf': [9, 8],
          });
          final wOut = await extractor.extractFlutterAssets(
            archive: wrapped,
            releaseType: ReleaseType.macos,
          );
          expect(wOut['f.ttf'], [9, 8]);
        },
      );
    });

    group('validation', () {
      test('rejects unsupported types, bad paths, and corrupt zips', () async {
        final empty = writeZip('empty.zip', const {});
        expect(
          () => extractor.extractFlutterAssets(
            archive: empty,
            releaseType: ReleaseType.linux,
          ),
          throwsUnsupportedError,
        );
        for (final bad in ['../x', 'a//b', './c', '/d']) {
          final z = writeZip('b_${bad.hashCode}.aab', {
            'base/assets/flutter_assets/$bad': [1],
          });
          await expectLater(
            extractor.extractFlutterAssets(
              archive: z,
              releaseType: ReleaseType.android,
            ),
            throwsFormatException,
          );
        }
        final corrupt = File(p.join(tempDir.path, 'bad.aab'))
          ..writeAsBytesSync([1, 2, 3]);
        await expectLater(
          extractor.extractFlutterAssets(
            archive: corrupt,
            releaseType: ReleaseType.android,
          ),
          throwsA(isA<ArchiveException>()),
        );
      });
    });
  });
}
