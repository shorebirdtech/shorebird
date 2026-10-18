import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_bundle_exception}
/// Thrown when a file can't be read as a [ReleaseBundle].
/// {@endtemplate}
class ReleaseBundleException implements Exception {
  /// {@macro release_bundle_exception}
  const ReleaseBundleException(this.message);

  /// What is wrong with the bundle, said so it stands alone.
  final String message;

  @override
  String toString() => message;
}

/// {@template release_bundle}
/// A release that was built but not uploaded: everything `shorebird upload`
/// needs to publish it, in one zip file.
///
/// `shorebird release --no-upload` writes one, so a release can be built in
/// one place (or before QA, or before signing) and published later from
/// anywhere, without the project or a rebuild.
///
/// The zip holds a JSON manifest, [manifestFileName], and the artifact files
/// under `artifacts/`. The manifest records each artifact's SHA-256, so a
/// bundle that was changed or truncated after it was written is refused
/// rather than uploaded.
/// {@endtemplate}
class ReleaseBundle {
  /// {@macro release_bundle}
  const ReleaseBundle({
    required this.appId,
    required this.releaseType,
    required this.releaseVersion,
    required this.flutterRevision,
    required this.shorebirdVersion,
    required this.metadata,
    required this.artifacts,
    this.flavor,
    this.target,
    this.supplement,
  });

  /// The version of the bundle format this CLI writes and reads. Bump it when
  /// a change to the manifest would make an older CLI misread a bundle.
  static const formatVersion = 1;

  /// The name of the manifest inside the zip.
  static const manifestFileName = 'shorebird_release_bundle.json';

  /// The Shorebird app ID the release belongs to.
  final String appId;

  /// The flavor the release was built with, if any.
  final String? flavor;

  /// The entrypoint the release was built from (`--target`), if not the
  /// default.
  final String? target;

  /// What was built (e.g. android, ios, aar).
  final ReleaseType releaseType;

  /// The version of the release (e.g. `1.0.0+1`).
  final String releaseVersion;

  /// The Flutter revision the release was built with.
  final String flutterRevision;

  /// The version of the Shorebird CLI that built the release.
  final String shorebirdVersion;

  /// The release metadata to send when the release is marked active, as
  /// `shorebird release` would have sent it.
  final Json metadata;

  /// The artifacts to upload.
  final List<ReleaseArtifactUpload> artifacts;

  /// The supplement artifact (e.g. obfuscation map), if the build made one.
  final ReleaseArtifactUpload? supplement;

  /// The platform of the release.
  ReleasePlatform get platform => releaseType.releasePlatform;

  /// Writes this bundle to [file] as a zip, replacing any file there.
  Future<void> writeTo(File file) async {
    file.parent.createSync(recursive: true);
    if (file.existsSync()) file.deleteSync();

    final entries = <(File, String)>[];
    Future<Json> describe(ReleaseArtifactUpload artifact, int index) async {
      // Android arch artifacts are all named libapp.so, so each file gets a
      // directory of its own.
      final path = 'artifacts/$index/${p.basename(artifact.file.path)}';
      entries.add((artifact.file, path));
      return {
        'path': path,
        'name': artifact.name,
        'arch': artifact.arch,
        'can_sideload': artifact.canSideload,
        'podfile_lock_hash': artifact.podfileLockHash,
        'sha256': await _sha256(artifact.file),
      };
    }

    final manifest = <String, dynamic>{
      'format_version': formatVersion,
      'app_id': appId,
      'flavor': flavor,
      'target': target,
      'release_type': releaseType.cliName,
      'release_version': releaseVersion,
      'flutter_revision': flutterRevision,
      'shorebird_version': shorebirdVersion,
      'metadata': metadata,
      'artifacts': [
        for (final (index, artifact) in artifacts.indexed)
          await describe(artifact, index),
      ],
      'supplement': supplement == null
          ? null
          : await describe(supplement!, artifacts.length),
    };
    final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);

    final zipPath = file.path;
    await Isolate.run(() async {
      final encoder = ZipFileEncoder()
        ..create(zipPath)
        ..addArchiveFile(ArchiveFile.string(manifestFileName, manifestJson));
      for (final (source, path) in entries) {
        await encoder.addFile(source, path);
      }
      await encoder.close();
    });
  }

  /// Extracts the bundle at [file] into [directory] and returns it, with each
  /// artifact pointing at its extracted file.
  ///
  /// A bundle may come from anywhere (e.g. a CI artifact), so only the
  /// manifest and the regular files it lists are written, each to a path
  /// checked to be inside [directory]. Anything else in the zip (links,
  /// directories, unlisted files) is ignored, and an artifact that isn't a
  /// regular file is refused.
  ///
  /// Throws a [ReleaseBundleException] if [file] isn't a release bundle this
  /// CLI can read, or an artifact's contents don't match the manifest.
  static Future<ReleaseBundle> extract({
    required File file,
    required Directory directory,
  }) async {
    if (!file.existsSync()) {
      throw ReleaseBundleException('No file at ${file.path}.');
    }
    final zipPath = file.path;
    final outPath = directory.path;

    try {
      // The zip decoder reads what it can, so a file that isn't a zip reads
      // as an empty one, with no manifest.
      final manifestJson = await Isolate.run(() => _readManifest(zipPath));
      if (manifestJson == null) {
        throw ReleaseBundleException(
          '${file.path} is not a release bundle (no $manifestFileName in '
          'it). Pass the zip that `shorebird release --no-upload` wrote.',
        );
      }
      final manifest = jsonDecode(manifestJson) as Json;
      final version = manifest['format_version'] as int;
      if (version > formatVersion) {
        throw ReleaseBundleException(
          '${file.path} was written by a newer Shorebird CLI '
          '(bundle format $version; this CLI reads up to $formatVersion). '
          'Run `shorebird upgrade` and try again.',
        );
      }

      final releaseTypeName = manifest['release_type'] as String;
      final releaseType = ReleaseType.values.firstWhere(
        (type) => type.cliName == releaseTypeName,
        orElse: () => throw ReleaseBundleException(
          '${file.path} is for an unknown platform "$releaseTypeName". '
          'Run `shorebird upgrade` and try again.',
        ),
      );

      final supplementJson = manifest['supplement'] as Json?;
      final artifactsJson = [
        for (final artifact in manifest['artifacts'] as List<dynamic>)
          artifact as Json,
        ?supplementJson,
      ];
      final paths = [for (final a in artifactsJson) a['path'] as String];
      for (final path in paths) {
        if (!_isSafeRelativePath(path)) {
          throw ReleaseBundleException(
            "${file.path}'s manifest lists $path, which is not a path inside "
            'the bundle.',
          );
        }
      }

      final unreadable = await Isolate.run(
        () => _extractFiles(zipPath, outPath, paths),
      );
      if (unreadable != null) {
        throw ReleaseBundleException(
          '${file.path} is missing $unreadable, which its manifest lists, or '
          'it is not a regular file.',
        );
      }

      Future<ReleaseArtifactUpload> readArtifact(Json json) async {
        final path = json['path'] as String;
        final artifactFile = File(p.join(outPath, path));
        if (await _sha256(artifactFile) != json['sha256'] as String) {
          throw ReleaseBundleException(
            '$path in ${file.path} does not match the hash in its manifest. '
            'The bundle was changed or damaged after it was written; build '
            'it again.',
          );
        }
        return ReleaseArtifactUpload(
          file: artifactFile,
          name: json['name'] as String,
          arch: json['arch'] as String,
          platform: releaseType.releasePlatform,
          canSideload: json['can_sideload'] as bool,
          podfileLockHash: json['podfile_lock_hash'] as String?,
        );
      }

      return ReleaseBundle(
        appId: manifest['app_id'] as String,
        flavor: manifest['flavor'] as String?,
        target: manifest['target'] as String?,
        releaseType: releaseType,
        releaseVersion: manifest['release_version'] as String,
        flutterRevision: manifest['flutter_revision'] as String,
        shorebirdVersion: manifest['shorebird_version'] as String,
        metadata: manifest['metadata'] as Json,
        artifacts: [
          for (final artifact in manifest['artifacts'] as List<dynamic>)
            await readArtifact(artifact as Json),
        ],
        supplement: supplementJson == null
            ? null
            : await readArtifact(supplementJson),
      );
    } on ReleaseBundleException {
      rethrow;
    } on Object catch (error) {
      // A malformed manifest (bad JSON, or a field missing or of the wrong
      // type), or a damaged zip.
      throw ReleaseBundleException(
        '${file.path} could not be read as a release bundle ($error). '
        'Build the bundle again.',
      );
    }
  }

  /// Whether [path] is a relative path that stays inside the directory it is
  /// resolved against: no root, no `..`, no `.` or empty segments.
  static bool _isSafeRelativePath(String path) {
    if (path.contains(r'\') || p.isAbsolute(path)) return false;
    // Split by hand: p.split drops empty segments, which would hide `a//b`
    // and a leading `/`.
    return path
        .split('/')
        .every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );
  }

  /// Whether [entry] is a regular file: not a directory, and not
  /// a link (by the decoder's reading, or by its Unix mode, which some zip
  /// tools set without the "made by Unix" marker the decoder looks for).
  static bool _isRegularFile(ArchiveFile entry) {
    if (!entry.isFile || entry.isSymbolicLink) return false;
    const fileTypeMask = 0xF000;
    const symbolicLinkType = 0xA000;
    return entry.mode & fileTypeMask != symbolicLinkType;
  }

  /// Returns the manifest in the zip at [zipPath], or null if it has none.
  /// Throws if [zipPath] is not a zip.
  static String? _readManifest(String zipPath) {
    final input = InputFileStream(zipPath);
    try {
      final entry = ZipDecoder().decodeStream(input).findFile(manifestFileName);
      if (entry == null || !_isRegularFile(entry)) return null;
      return utf8.decode(entry.content);
    } finally {
      input.closeSync();
    }
  }

  /// Writes each of [paths] in the zip at [zipPath] to the same path under
  /// [outPath]. Returns the first path that is not a regular file in the zip,
  /// or null once all are written.
  static String? _extractFiles(
    String zipPath,
    String outPath,
    List<String> paths,
  ) {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final path in paths) {
        final entry = archive.findFile(path);
        if (entry == null || !_isRegularFile(entry)) return path;
        final outFile = File(p.join(outPath, path))
          ..parent.createSync(recursive: true);
        final output = OutputFileStream(outFile.path);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      }
      return null;
    } finally {
      input.closeSync();
    }
  }

  static Future<String> _sha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
