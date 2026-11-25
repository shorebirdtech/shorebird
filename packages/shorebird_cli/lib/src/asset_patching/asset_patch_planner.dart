import 'dart:collection';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:scoped_deps/scoped_deps.dart';

/// Default per-patch asset upload cap in bytes, equal to 5 MiB.
const int defaultMaxAssetBytes = 5 * 1024 * 1024;

/// Global Flutter asset registry keys that cannot be overridden by a patch.
const Set<String> poisonAssetKeys = {
  'AssetManifest.json',
  'AssetManifest.bin',
  'AssetManifest.bin.json',
  'FontManifest.json',
  'NOTICES.Z',
};

/// Whether [key] is a canonical `flutter_assets`-relative POSIX path.
bool isCanonicalAssetKey(String key) =>
    !key.contains(r'\') &&
    !key.split('/').any((s) => s.isEmpty || s == '.' || s == '..');

/// A reference to an [AssetPatchPlanner] instance.
final assetPatchPlannerRef = create(AssetPatchPlanner.new);

/// The [AssetPatchPlanner] instance available in the current zone.
AssetPatchPlanner get assetPatchPlanner => read(assetPatchPlannerRef);

/// Metadata for one changed or added `flutter_assets` entry in a patch.
typedef AssetManifestEntry = ({String key, String sha256, int size});

/// A unique content-addressed asset blob to upload for a patch.
typedef AssetUploadBlob = ({String sha256, int size, Uint8List bytes});

/// Result of diffing patch `flutter_assets` against release `flutter_assets`.
typedef AssetPatchPlan = ({
  Map<String, AssetManifestEntry> entries,
  List<AssetUploadBlob> blobs,
  Set<String> poisonKeys,
  int totalBytes,
  int maxBytes,
  bool exceedsMaxBytes,
});

/// Computes content-addressed asset upload plans from `flutter_assets` maps.
class AssetPatchPlanner {
  /// Creates an [AssetPatchPlanner].
  const AssetPatchPlanner();

  static const _bytesEqual = ListEquality<int>();

  /// Computes an [AssetPatchPlan] from [releaseAssets] and [patchAssets],
  /// splitting changed [poisonAssetKeys] into `poisonKeys` and deduplicating
  /// changed upload blobs by SHA-256 against [maxBytes].
  AssetPatchPlan plan({
    required Map<String, Uint8List> releaseAssets,
    required Map<String, Uint8List> patchAssets,
    int maxBytes = defaultMaxAssetBytes,
  }) {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be non-negative.');
    }
    final entries = SplayTreeMap<String, AssetManifestEntry>();
    final blobs = SplayTreeMap<String, AssetUploadBlob>();
    final poisonKeys = SplayTreeSet<String>();
    var totalBytes = 0;

    for (final MapEntry(key: key, value: patchBytes) in patchAssets.entries) {
      if (!isCanonicalAssetKey(key)) {
        throw FormatException('Non-canonical flutter_assets key', key);
      }
      final releaseBytes = releaseAssets[key];
      if (releaseBytes != null &&
          _bytesEqual.equals(releaseBytes, patchBytes)) {
        continue;
      }
      if (poisonAssetKeys.contains(key)) {
        poisonKeys.add(key);
        continue;
      }
      final copied = Uint8List.fromList(patchBytes).asUnmodifiableView();
      final digest = crypto.sha256.convert(copied).toString();
      entries[key] = (key: key, sha256: digest, size: copied.length);
      blobs.putIfAbsent(digest, () {
        totalBytes += copied.length;
        return (sha256: digest, size: copied.length, bytes: copied);
      });
    }

    return (
      entries: Map<String, AssetManifestEntry>.unmodifiable(entries),
      blobs: List<AssetUploadBlob>.unmodifiable(blobs.values),
      poisonKeys: Set<String>.unmodifiable(poisonKeys),
      totalBytes: totalBytes,
      maxBytes: maxBytes,
      exceedsMaxBytes: totalBytes > maxBytes,
    );
  }
}
