// cspell:words xcarchive
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/asset_patching/asset_patch_planner.dart';
import 'package:shorebird_cli/src/release_type.dart';

/// A reference to an [AssetExtractor] instance.
final assetExtractorRef = create(AssetExtractor.new);

/// The [AssetExtractor] instance available in the current zone.
AssetExtractor get assetExtractor => read(assetExtractorRef);

/// Extracts `flutter_assets` files from Android, iOS, and macOS archives.
class AssetExtractor {
  /// Creates an [AssetExtractor].
  const AssetExtractor();

  static final _androidPath = RegExp(r'^base/assets/flutter_assets/(.+)$');
  static final _iosPath = RegExp(
    r'^(?:Products/Applications/)?[^/]+\.app/Frameworks/App\.framework/flutter_assets/(.+)$',
  );
  static final _macosPath = RegExp(
    r'^(?:[^/]+\.app/)?Contents/Frameworks/App\.framework/Versions/A/Resources/flutter_assets/(.+)$',
  );

  static RegExp? _pathPattern(ReleaseType type) => switch (type) {
    ReleaseType.android => _androidPath,
    ReleaseType.ios => _iosPath,
    ReleaseType.macos => _macosPath,
    _ => null,
  };

  /// Whether [releaseType] supports `flutter_assets` extraction.
  static bool supportsReleaseType(ReleaseType releaseType) =>
      _pathPattern(releaseType) != null;

  // Apple ditto archives emit `._*` AppleDouble resource-fork entries.
  static bool _isSidecar(String key, Uint8List b) =>
      p.posix.basename(key).startsWith('._') &&
      b.length >= 4 &&
      (b[0] == 0 && b[1] == 5 && b[2] == 0x16 && b[3] == 7);

  /// Reads regular `flutter_assets` files from [archive] for [releaseType],
  /// keyed by canonical `flutter_assets`-relative POSIX path.
  Future<Map<String, Uint8List>> extractFlutterAssets({
    required File archive,
    required ReleaseType releaseType,
  }) {
    final pattern = _pathPattern(releaseType);
    if (pattern == null) {
      throw UnsupportedError('Unsupported release type: $releaseType');
    }
    final archivePath = archive.path;
    return Isolate.run(() {
      final assets = SplayTreeMap<String, Uint8List>();
      final input = InputFileStream(archivePath);
      try {
        for (final entry in ZipDecoder().decodeStream(input, verify: true)) {
          if (!entry.isFile || entry.isSymbolicLink) continue;
          final key = pattern.firstMatch(entry.name)?.group(1);
          if (key == null) continue;
          if (!isCanonicalAssetKey(key)) {
            throw FormatException('Non-canonical flutter_assets path', key);
          }
          final bytes = Uint8List.fromList(entry.content).asUnmodifiableView();
          if (!_isSidecar(key, bytes)) assets[key] = bytes;
        }
      } finally {
        input.closeSync();
      }
      return Map<String, Uint8List>.unmodifiable(assets);
    });
  }
}
