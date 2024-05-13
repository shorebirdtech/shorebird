import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [ShorebirdFlutter] instance.
final shorebirdFlutterRef = create(ShorebirdFlutter.new);

/// The [ShorebirdFlutter] instance available in the current zone.
ShorebirdFlutter get shorebirdFlutter => read(shorebirdFlutterRef);

/// {@template shorebird_flutter}
/// Helps manage the Flutter installation used by Shorebird.
/// {@endtemplate}
class ShorebirdFlutter {
  /// {@macro shorebird_flutter}
  const ShorebirdFlutter();

  static const executable = 'flutter';
  static const String flutterGitUrl =
      'https://github.com/shorebirdtech/flutter.git';

  /// Arguments to pass to `flutter precache`.
  List<String> get precacheArgs => [
        '--android',
        if (platform.isMacOS) '--ios',
      ];

  String _workingDirectory({String? revision}) {
    revision ??= shorebirdEnv.flutterRevision;
    return p.join(shorebirdEnv.flutterDirectory.parent.path, revision);
  }

  Future<void> installRevision({required String revision}) async {
    final targetDirectory = Directory(_workingDirectory(revision: revision));
    if (targetDirectory.existsSync()) return;

    final version = await getVersionString(revision: revision);

    final installProgress = logger.progress(
      'Installing Flutter $version (${shortRevisionString(revision)})',
    );

    try {
      // Clone the Shorebird Flutter repo into the target directory.
      await git.clone(
        url: flutterGitUrl,
        outputDirectory: targetDirectory.path,
        args: [
          '--filter=tree:0',
          '--no-checkout',
        ],
      );

      // Checkout the correct revision.
      await git.checkout(directory: targetDirectory.path, revision: revision);
      installProgress.complete();
    } catch (error) {
      installProgress.fail(
        'Failed to install Flutter $version (${shortRevisionString(revision)})',
      );
      logger.err('$error');
      rethrow;
    }

    final precacheProgress = logger.progress(
      'Running ${lightCyan.wrap('flutter precache')}',
    );

    try {
      await process.run(
        executable,
        ['precache', ...precacheArgs],
        workingDirectory: targetDirectory.path,
        runInShell: true,
      );
      precacheProgress.complete();
    } catch (_) {
      precacheProgress.fail('Failed to precache Flutter $version');
      logger.info(
        '''This is not a critical error, but your next build make take longer than usual.''',
      );
    }
  }

  /// Whether the current revision is unmodified.
  Future<bool> isUnmodified({String? revision}) async {
    final status = await git.status(
      directory: _workingDirectory(revision: revision),
      args: ['--untracked-files=no', '--porcelain'],
    );
    return status.isEmpty;
  }

  /// Returns the current system Flutter version.
  /// Throws a [ProcessException] if the version check fails.
  /// Returns `null` if the version check succeeds but the version cannot be
  /// parsed.
  Future<String?> getSystemVersion() async {
    const args = ['--version'];
    final result = await process.run(
      executable,
      args,
      runInShell: true,
      useVendedFlutter: false,
    );

    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${result.stderr}',
        result.exitCode,
      );
    }

    final output = result.stdout.toString();
    final flutterVersionRegex = RegExp(r'Flutter (\d+.\d+.\d+)');
    final match = flutterVersionRegex.firstMatch(output);

    return match?.group(1);
  }

  /// Converts a full git revision to a short revision string.
  String shortRevisionString(String revision) => revision.substring(0, 10);

  /// Returns the current Shorebird Flutter version and revision.
  /// Returns unknown if the version check fails.
  Future<String> getVersionAndRevision() async {
    String? version = 'unknown';
    try {
      version = await getVersionString();
    } catch (_) {}

    return '$version (${shortRevisionString(shorebirdEnv.flutterRevision)})';
  }

  /// Returns the current Shorebird Flutter version.
  /// Throws a [ProcessException] if the version check fails.
  /// Returns `null` if the version check succeeds but the version cannot be
  /// parsed.
  Future<String?> getVersionString({String? revision}) async {
    final result = await git.forEachRef(
      contains: revision ?? shorebirdEnv.flutterRevision,
      format: '%(refname:short)',
      pattern: 'refs/remotes/origin/flutter_release/*',
      directory: _workingDirectory(),
    );

    return LineSplitter.split(result)
        .map((e) => e.replaceFirst('origin/flutter_release/', ''))
        .toList()
        .firstOrNull;
  }

  /// The current Shorebird Flutter version as a [Version]. Returns null if the
  /// version cannot be parsed.
  Future<Version?> getVersion() async {
    final versionString = await getVersionString();
    if (versionString == null) {
      return null;
    }

    final Version version;
    try {
      version = Version.parse(versionString);
    } on FormatException {
      return null;
    }

    return version;
  }

  /// Returns the git revision for the provided [version].
  /// e.g. 3.16.3 -> b9b23902966504a9778f4c07e3a3487fa84dcb2a
  Future<String?> getRevisionForVersion(String version) async {
    final result = await git.revParse(
      revision: 'refs/remotes/origin/flutter_release/$version',
      directory: _workingDirectory(),
    );
    return LineSplitter.split(result).toList().firstOrNull;
  }

  Future<List<String>> getVersions({String? revision}) async {
    final result = await git.forEachRef(
      format: '%(refname:short)',
      pattern: 'refs/remotes/origin/flutter_release/*',
      directory: _workingDirectory(revision: revision),
    );
    return LineSplitter.split(result)
        .map((e) => e.replaceFirst('origin/flutter_release/', ''))
        .toList();
  }

  Future<void> useVersion({required String version}) async {
    final revision = await git.revParse(
      revision: 'origin/flutter_release/$version',
      directory: _workingDirectory(),
    );

    await useRevision(revision: revision);
  }

  Future<void> useRevision({required String revision}) async {
    await installRevision(revision: revision);

    final version = await getVersionString(revision: revision);
    final useFlutterProgress = logger.progress('Using Flutter $version');
    shorebirdEnv.flutterRevision = revision;
    useFlutterProgress.complete();
  }
}
