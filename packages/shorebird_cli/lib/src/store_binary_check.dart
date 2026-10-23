// cspell:words LINKEDIT
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_bundle.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template store_binary_exception}
/// Thrown when a store binary can't be compared with a [ReleaseBundle].
/// {@endtemplate}
class StoreBinaryException implements Exception {
  /// {@macro store_binary_exception}
  const StoreBinaryException(this.message);

  /// What is wrong, said so it stands alone.
  final String message;

  @override
  String toString() => message;
}

/// Compares the binary a customer ships to a store (an .aab, .apk or .ipa)
/// with the [ReleaseBundle] they are about to publish.
///
/// Patches are built against the release on Shorebird. A device running a
/// different build of the same version rejects every patch (its hash doesn't
/// match), so the store binary and the published bundle must come from the
/// same build. Only the compiled Dart code is compared, because that is what
/// patches are built against, and because signing (which may happen after
/// `shorebird release --no-upload`) changes other bytes of the binary.
abstract final class StoreBinaryCheck {
  /// Returns how [storeBinary] differs from [bundle], one line per
  /// difference, or an empty list if it was built from the same build.
  ///
  /// Throws a [StoreBinaryException] if [storeBinary] is not a kind of file
  /// this can compare with [bundle], or holds no compiled Dart code.
  static Future<List<String>> differences({
    required ReleaseBundle bundle,
    required File storeBinary,
  }) async {
    if (!storeBinary.existsSync()) {
      throw StoreBinaryException('No file at ${storeBinary.path}.');
    }
    final extension = p.extension(storeBinary.path).toLowerCase();
    switch (bundle.platform) {
      case ReleasePlatform.android:
        if (extension != '.aab' && extension != '.apk') break;
        return _androidDifferences(
          bundle: bundle,
          storeBinary: storeBinary,
          isApk: extension == '.apk',
        );
      case ReleasePlatform.ios:
        if (extension != '.ipa') break;
        return _iosDifferences(bundle: bundle, storeBinary: storeBinary);
      case ReleasePlatform.linux:
      case ReleasePlatform.macos:
      case ReleasePlatform.windows:
        throw StoreBinaryException(
          '--verify checks Android (.aab, .apk) and iOS (.ipa) builds; this '
          'bundle is a ${bundle.platform.displayName} release.',
        );
    }
    final expected = bundle.platform == ReleasePlatform.android
        ? 'an .aab or .apk'
        : 'an .ipa';
    throw StoreBinaryException(
      '${storeBinary.path} is not $expected. Pass the file you upload to the '
      'store for this ${bundle.platform.displayName} release.',
    );
  }

  static Future<List<String>> _androidDifferences({
    required ReleaseBundle bundle,
    required File storeBinary,
    required bool isApk,
  }) async {
    final inBundle = <String, String>{};
    for (final artifact in bundle.artifacts) {
      final abi = _abiForArch(artifact.arch);
      if (abi != null) inBundle[abi] = await _sha256File(artifact.file);
    }
    final path = storeBinary.path;
    final Map<String, String> inStoreBinary;
    try {
      inStoreBinary = await Isolate.run(() => _libappHashes(path));
    } on Exception catch (error) {
      throw StoreBinaryException('Could not read $path ($error).');
    }
    if (inStoreBinary.isEmpty) {
      throw StoreBinaryException(
        '$path has no libapp.so (the compiled Dart code), so it is not the '
        'build of a Flutter app. Pass the file you upload to the store.',
      );
    }

    final name = p.basename(path);
    return [
      for (final abi in {...inBundle.keys, ...inStoreBinary.keys})
        switch ((inBundle[abi], inStoreBinary[abi])) {
          (final a?, final b?) when a != b =>
            '$abi: libapp.so in $name is not the one in the bundle',
          // A split .apk holds one ABI of the release, so only an .aab is
          // expected to hold every ABI the bundle has.
          (_?, null) when !isApk => '$abi: in the bundle, but not in $name',
          (null, _?) => '$abi: in $name, but not in the bundle',
          _ => null,
        },
    ].nonNulls.toList();
  }

  static Future<List<String>> _iosDifferences({
    required ReleaseBundle bundle,
    required File storeBinary,
  }) async {
    final xcarchive = bundle.artifacts
        .where((artifact) => artifact.arch == 'xcarchive')
        .firstOrNull;
    if (xcarchive == null) {
      throw const StoreBinaryException(
        'This bundle has no .xcarchive to compare with.',
      );
    }
    final archivePath = xcarchive.file.path;
    final ipaPath = storeBinary.path;
    final String? inBundle;
    final String? inStoreBinary;
    try {
      (inBundle, inStoreBinary) = await Isolate.run(
        () => (
          _appFrameworkHash(archivePath, _xcarchiveAppEntry),
          _appFrameworkHash(ipaPath, _ipaAppEntry),
        ),
      );
    } on Exception catch (error) {
      throw StoreBinaryException('Could not read $ipaPath ($error).');
    }
    if (inStoreBinary == null) {
      throw StoreBinaryException(
        '$ipaPath has no Payload/*.app/Frameworks/App.framework/App (the '
        'compiled Dart code), so it is not the build of a Flutter app. Pass '
        'the .ipa you upload to the App Store.',
      );
    }
    if (inBundle == null) {
      throw const StoreBinaryException(
        "The bundle's .xcarchive has no App.framework to compare with.",
      );
    }
    return [
      if (inBundle != inStoreBinary)
        'App.framework in ${p.basename(ipaPath)} is not the one in the bundle',
    ];
  }

  /// The Android ABI directory name of the Shorebird arch [arch]
  /// (e.g. `aarch64` is `arm64-v8a`), or null if [arch] is not one.
  static String? _abiForArch(String arch) => Arch.values
      .where((value) => value.arch == arch)
      .firstOrNull
      ?.androidBuildPath;

  static final _libappEntry = RegExp(r'^(?:base/)?lib/([^/]+)/libapp\.so$');
  static final _xcarchiveAppEntry = RegExp(
    r'(?:^|/)Products/Applications/[^/]+\.app/Frameworks/App\.framework/App$',
  );
  static final _ipaAppEntry = RegExp(
    r'^Payload/[^/]+\.app/Frameworks/App\.framework/App$',
  );

  /// The SHA-256 of each `libapp.so` in the .aab or .apk at [path], by ABI.
  static Map<String, String> _libappHashes(String path) {
    final input = InputFileStream(path);
    try {
      return {
        for (final entry in ZipDecoder().decodeStream(input).files)
          if (entry.isFile)
            if (_libappEntry.firstMatch(entry.name) case final match?)
              match.group(1)!: sha256.convert(entry.content).toString(),
      };
    } finally {
      input.closeSync();
    }
  }

  /// The [machOCodeHash] of the first entry in the zip at [path] whose name
  /// matches [entryName], or null if there is none.
  static String? _appFrameworkHash(String path, RegExp entryName) {
    final input = InputFileStream(path);
    try {
      for (final entry in ZipDecoder().decodeStream(input).files) {
        if (entry.isFile && entryName.hasMatch(entry.name)) {
          return machOCodeHash(entry.content);
        }
      }
      return null;
    } finally {
      input.closeSync();
    }
  }

  /// A SHA-256 of the Mach-O binary [bytes] that signing doesn't change: the
  /// contents of every section outside `__LINKEDIT` (which holds the code
  /// signature), and not the header or load commands (which signing
  /// rewrites). For a universal binary, of each slice in turn.
  ///
  /// Throws a [FormatException] if [bytes] is not a 64-bit Mach-O binary or
  /// a universal binary of them.
  static String machOCodeHash(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final code = BytesBuilder(copy: false);
    // Universal (fat) binaries are big-endian; the slices are little-endian.
    const fatMagic = 0xcafebabe;
    if (bytes.length >= 8 && data.getUint32(0) == fatMagic) {
      final count = data.getUint32(4);
      for (var i = 0; i < count; i++) {
        final arch = 8 + i * 20;
        final offset = data.getUint32(arch + 8);
        final size = data.getUint32(arch + 12);
        _addMachOCode(
          Uint8List.sublistView(bytes, offset, offset + size),
          code,
        );
      }
    } else {
      _addMachOCode(bytes, code);
    }
    return sha256.convert(code.takeBytes()).toString();
  }

  static void _addMachOCode(Uint8List bytes, BytesBuilder code) {
    const magic64 = 0xfeedfacf;
    const segment64 = 0x19;
    const headerSize = 32;
    const segmentCommandSize = 72;
    const sectionSize = 80;
    // Section types with no bytes in the file.
    const zeroFillTypes = {0x1, 0xc, 0x12};
    final data = ByteData.sublistView(bytes);
    if (bytes.length < headerSize ||
        data.getUint32(0, Endian.little) != magic64) {
      throw const FormatException('not a 64-bit Mach-O binary');
    }
    String name(int offset) => String.fromCharCodes(
      bytes.sublist(offset, offset + 16).takeWhile((c) => c != 0),
    );

    final commandCount = data.getUint32(16, Endian.little);
    var command = headerSize;
    for (var i = 0; i < commandCount; i++) {
      final type = data.getUint32(command, Endian.little);
      final size = data.getUint32(command + 4, Endian.little);
      if (type == segment64 && name(command + 8) != '__LINKEDIT') {
        final sectionCount = data.getUint32(command + 64, Endian.little);
        for (var j = 0; j < sectionCount; j++) {
          final section = command + segmentCommandSize + j * sectionSize;
          final length = data.getUint64(section + 40, Endian.little);
          final offset = data.getUint32(section + 48, Endian.little);
          final flags = data.getUint32(section + 64, Endian.little);
          if (zeroFillTypes.contains(flags & 0xff) || length == 0) continue;
          if (offset + length > bytes.length) {
            throw const FormatException('section runs past the end');
          }
          code
            ..add('${name(section + 16)},${name(section)}'.codeUnits)
            ..add(Uint8List.sublistView(bytes, offset, offset + length));
        }
      }
      command += size;
    }
  }

  static Future<String> _sha256File(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
