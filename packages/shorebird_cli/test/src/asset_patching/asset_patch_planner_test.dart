import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/asset_patching/asset_patch_planner.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(AssetPatchPlanner, () {
    const planner = AssetPatchPlanner();
    Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));
    String sha256Of(List<int> b) => crypto.sha256.convert(b).toString();

    test('resolves via scoped ref and exposes constants', () {
      expect(
        runScoped(() => assetPatchPlanner, values: {assetPatchPlannerRef}),
        isA<AssetPatchPlanner>(),
      );
      expect(defaultMaxAssetBytes, 5242880);
      expect(poisonAssetKeys, {
        'AssetManifest.json',
        'AssetManifest.bin',
        'AssetManifest.bin.json',
        'FontManifest.json',
        'NOTICES.Z',
      });
    });

    group('when no patchable assets changed', () {
      test('returns empty plan for identical or removed assets', () {
        final plan = planner.plan(
          releaseAssets: {'a': bytesOf('1'), 'removed': bytesOf('old')},
          patchAssets: {'a': bytesOf('1')},
        );
        expect(plan.entries, isEmpty);
        expect(plan.blobs, isEmpty);
        expect(plan.poisonKeys, isEmpty);
        expect(plan.totalBytes, 0);
        expect(plan.exceedsMaxBytes, isFalse);
      });
    });

    group('when poison keys and patchable assets change', () {
      test('splits the 5 poison keys from content-addressed entries', () {
        final plan = planner.plan(
          releaseAssets: {'AssetManifest.json': bytesOf('a1')},
          patchAssets: {
            for (final key in poisonAssetKeys) key: bytesOf('new-$key'),
            'assets/Nested/NOTICES.Z': bytesOf('ok'),
          },
        );
        expect(plan.poisonKeys, poisonAssetKeys);
        expect(plan.entries.keys, ['assets/Nested/NOTICES.Z']);
        expect(plan.totalBytes, 2);
      });

      test('deduplicates identical changed blobs against 5242880 cap', () {
        final shared = Uint8List(3 * 1024 * 1024)..fillRange(0, 8, 0xab);
        final sharedHash = sha256Of(shared);
        final font = bytesOf('repacked-font');
        final plan = planner.plan(
          releaseAssets: {'fonts/Icons.otf': bytesOf('orig-font')},
          patchAssets: {
            'fonts/Icons.otf': font,
            'assets/b.bin': shared,
            'assets/a.bin': Uint8List.fromList(shared),
          },
        );
        expect(plan.entries.keys, [
          'assets/a.bin',
          'assets/b.bin',
          'fonts/Icons.otf',
        ]);
        expect(plan.entries['assets/a.bin'], (
          key: 'assets/a.bin',
          sha256: sharedHash,
          size: shared.length,
        ));
        expect(plan.entries['assets/b.bin']?.sha256, sharedHash);
        expect(plan.blobs, hasLength(2));
        expect(plan.totalBytes, shared.length + font.length);
        expect(plan.exceedsMaxBytes, isFalse);
        expect(() => plan.blobs.first.bytes[0] = 0, throwsUnsupportedError);
      });

      test('checks 5242880 boundary and custom cap', () {
        final atCap = planner.plan(
          releaseAssets: const {},
          patchAssets: {'a': Uint8List(defaultMaxAssetBytes)},
        );
        expect(atCap.exceedsMaxBytes, isFalse);

        final overCap = planner.plan(
          releaseAssets: const {},
          patchAssets: {'a': Uint8List(defaultMaxAssetBytes + 1)},
        );
        expect(overCap.exceedsMaxBytes, isTrue);

        final custom = planner.plan(
          releaseAssets: const {},
          patchAssets: {'a': Uint8List(6)},
          maxBytes: 5,
        );
        expect(custom.maxBytes, 5);
        expect(custom.exceedsMaxBytes, isTrue);
      });
    });

    group('validation', () {
      test('rejects negative maxBytes and non-canonical keys', () {
        expect(
          () => planner.plan(
            releaseAssets: const {},
            patchAssets: const {},
            maxBytes: -1,
          ),
          throwsArgumentError,
        );
        for (final bad in ['', '/a', 'a/', '../a', './a', 'a//b', r'a\b']) {
          expect(
            () => planner.plan(
              releaseAssets: const {},
              patchAssets: {bad: Uint8List(1)},
            ),
            throwsFormatException,
          );
        }
      });
    });
  });
}
