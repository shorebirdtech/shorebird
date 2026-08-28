import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/version.dart';
import 'package:shorebird_cli/src/flutter_version_constraints.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

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

  /// The executable name.
  static const executable = 'flutter';

  /// The Shorebird Flutter fork git URL.
  static const String flutterGitUrl =
      'https://github.com/shorebirdtech/flutter.git';

  /// Arguments to pass to `flutter precache`.
  List<String> get precacheArgs => ['--android', if (platform.isMacOS) '--ios'];

  String _workingDirectory({String? revision}) {
    revision ??= shorebirdEnv.flutterRevision;
    return p.join(shorebirdEnv.flutterDirectory.parent.path, revision);
  }

  /// Marker written once `flutter precache` has succeeded for an installed
  /// revision.
  ///
  /// Untracked, and [isUnmodified] passes `--untracked-files=no`, so its
  /// presence does not make the checkout look dirty.
  static const precacheStampName = '.shorebird_precache';

  /// Suffix identifying a directory an install is still writing into.
  static const _stagingSuffix = '.tmp';

  /// How long a staging directory must have existed before another install
  /// treats it as abandoned rather than as a peer's work in progress.
  static const _stagingMaxAge = Duration(days: 1);

  /// Names a directory the sweep can reclaim once it is old enough.
  ///
  /// The creation time is carried in the name rather than read back from the
  /// filesystem. A directory's mtime is not ours to depend on: an unrelated
  /// write can bump it, a rename does not touch it at all, and what it means
  /// varies across platforms. This name is written once, by this code, and
  /// never changes afterwards.
  String _reclaimablePath(String path, {String? tag}) {
    final stamp = clock.now().millisecondsSinceEpoch;
    return '${[path, '$pid', ?tag].join('.')}.$stamp$_stagingSuffix';
  }

  /// Reads back the time [_reclaimablePath] wrote into [name], or null if
  /// [name] was not written by it.
  DateTime? _reclaimableSince({required String name, required String prefix}) {
    if (!name.startsWith(prefix) || !name.endsWith(_stagingSuffix)) return null;
    final stamp = name
        .substring(prefix.length, name.length - _stagingSuffix.length)
        .split('.')
        .last;
    final millis = int.tryParse(stamp);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Clones and checks out [revision], publishing it at [targetDirectory]
  /// only once both have succeeded.
  ///
  /// The work happens in a directory private to this process, so a run that
  /// dies partway leaves that behind rather than a half-written
  /// [targetDirectory]. Nothing infers completeness from the contents of a
  /// checkout, and no existing install is ever deleted to make room.
  Future<void> _cloneAndCheckout({
    required Directory targetDirectory,
    required String revision,
    required String? version,
  }) async {
    final installProgress = logger.progress(
      'Installing Flutter $version (${shortRevisionString(revision)})',
    );

    // Carries this instant, so no earlier run's staging directory can share
    // the name and no directory has to be cleared before the clone.
    final stagingDirectory = Directory(_reclaimablePath(targetDirectory.path));
    try {
      // Clone the Shorebird Flutter repo into the staging directory.
      await git.clone(
        url: flutterGitUrl,
        outputDirectory: stagingDirectory.path,
        args: ['--filter=tree:0', '--no-checkout'],
      );

      // Checkout the correct revision.
      await git.checkout(directory: stagingDirectory.path, revision: revision);

      stagingDirectory.renameSync(targetDirectory.path);
      installProgress.complete();
    } catch (error) {
      // Another process publishing the same revision first is not a failure.
      // Its checkout is as good as ours, so adopt it. A directory that is
      // demonstrably unusable is not a peer's finished work, so it does not
      // count: the shell bootstrap clones into this path in place, and
      // adopting it mid-clone would precache and stamp a partial checkout.
      final published =
          targetDirectory.existsSync() && !_isUnusableInstall(targetDirectory);
      if (published) {
        installProgress.complete();
        _deleteIgnoringErrors(stagingDirectory);
        return;
      }

      final short = shortRevisionString(revision);
      installProgress.fail('Failed to install Flutter $version ($short)');
      logger.err('$error');
      _deleteIgnoringErrors(stagingDirectory);
      rethrow;
    }
  }

  void _deleteIgnoringErrors(Directory directory) {
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      logger.detail('Failed to remove ${directory.path}: $error');
    }
  }

  /// Removes staging directories left by runs that were killed before they
  /// could publish.
  ///
  /// Publishing by rename means an interrupted install strands its staging
  /// directory instead of poisoning the target, so something has to reclaim
  /// it. A concurrent install's staging directory is indistinguishable from a
  /// stranded one except by age, so only entries older than [_stagingMaxAge]
  /// are removed. A clone finishes in minutes.
  ///
  /// A name this code did not write is left alone, so an unparseable or
  /// unrecognized sibling is never a candidate.
  void _reclaimStrandedStagingDirectories(Directory targetDirectory) {
    final prefix = '${p.basename(targetDirectory.path)}.';
    final cutoff = clock.now().subtract(_stagingMaxAge);

    final List<FileSystemEntity> siblings;
    try {
      siblings = targetDirectory.parent.listSync();
    } on FileSystemException {
      return;
    }

    for (final sibling in siblings.whereType<Directory>()) {
      final since = _reclaimableSince(
        name: p.basename(sibling.path),
        prefix: prefix,
      );
      if (since == null || since.isAfter(cutoff)) continue;
      _deleteIgnoringErrors(sibling);
    }
  }

  /// Whether [directory] definitely does not hold a usable install.
  ///
  /// A finished checkout always contains the Flutter launcher, so its absence
  /// is proof the directory is unusable. The converse does not hold, which is
  /// why this only ever condemns a directory and never certifies one: a
  /// checkout interrupted after the launcher was written looks identical to a
  /// finished one from the outside. Installs published by [_cloneAndCheckout]
  /// do not need certifying, since a partial one is never published at all.
  bool _isUnusableInstall(Directory directory) {
    if (!directory.existsSync()) return false;
    final launcher = platform.isWindows ? 'flutter.bat' : 'flutter';
    return !File(p.join(directory.path, 'bin', launcher)).existsSync();
  }

  /// Moves an unusable install out of the way so a fresh one can take its
  /// place, and hands the remains to [_reclaimStrandedStagingDirectories].
  ///
  /// Renamed rather than deleted because a launcher-less directory is also
  /// what the shell bootstrap's in-place `git clone --no-checkout` looks like
  /// while it runs, and there is no lock this side can take to tell the two
  /// apart. A rename never destroys bytes another process is still writing.
  /// The new name stamps this instant, so the sweep's age gate starts from
  /// the rename rather than from whenever the directory was first written.
  void _discardUnusableInstall(Directory directory) {
    try {
      directory.renameSync(_reclaimablePath(directory.path, tag: 'old'));
    } on PathNotFoundException {
      // A peer condemned it first. Its absence is the outcome wanted here.
      return;
    } on FileSystemException catch (error) {
      final exception = CacheCorruptedException(
        'Could not move ${directory.path} aside: $error.',
        remedy: 'Remove ${directory.path} and run this command again.',
      );
      logger.err('$exception');
      throw exception;
    }
  }

  /// Install the provided Flutter [revision].
  ///
  /// Installing is two steps, each with its own durable record, so an
  /// interrupted run resumes instead of leaving state that later runs mistake
  /// for a finished install.
  ///
  /// The checkout records itself by existing: [_cloneAndCheckout] publishes
  /// the target directory with a rename, so it is either a finished checkout
  /// or absent. Precaching records itself with [precacheStampName].
  /// Precache is idempotent, so a missing stamp re-runs it rather than
  /// re-cloning.
  ///
  /// Directories left by versions that installed in place predate that
  /// guarantee, so a demonstrably unusable one is discarded and reinstalled
  /// rather than sending the user to `shorebird cache clean`, which would
  /// take every other installed revision with it.
  ///
  /// Precache runs on install as a convenience so the first build is not
  /// unexpectedly slow. A precache failure is treated as a corrupted install:
  /// Flutter's stamp-based cache will otherwise trust a partial extraction and
  /// surface the missing artifact later as an opaque Gradle error (see
  /// shorebirdtech/shorebird#3783).
  Future<void> installRevision({required String revision}) async {
    final targetDirectory = Directory(_workingDirectory(revision: revision));
    final precacheStamp = File(p.join(targetDirectory.path, precacheStampName));

    // Runs ahead of the already-installed early return below. A run killed
    // mid-clone publishes on its retry, and nothing would ever clone that
    // revision again to reclaim what the killed run left behind.
    _reclaimStrandedStagingDirectories(targetDirectory);

    final isUnusable = _isUnusableInstall(targetDirectory);
    if (!isUnusable &&
        targetDirectory.existsSync() &&
        precacheStamp.existsSync()) {
      return;
    }

    // Read the version before condemning anything. getVersionForRevision runs
    // git in the active revision's checkout, which is this very directory
    // whenever the revision being installed is the active one.
    final version = await getVersionForRevision(flutterRevision: revision);

    if (isUnusable) {
      logger.info(
        '''Flutter ${shortRevisionString(revision)} is incompletely installed. Reinstalling it.''',
      );
      _discardUnusableInstall(targetDirectory);
    }

    final isCheckedOut = targetDirectory.existsSync();

    if (!isCheckedOut) {
      await _cloneAndCheckout(
        targetDirectory: targetDirectory,
        revision: revision,
        version: version,
      );
    }

    final precacheProgress = logger.progress(
      'Running ${lightCyan.wrap('flutter precache')}',
    );

    final precacheArguments = ['precache', ...precacheArgs];

    // Flutter's launcher derives FLUTTER_ROOT from its own script path, so
    // `workingDirectory` cannot aim precache at [revision]. The vended binary
    // path is what decides which cache is warmed, and it resolves from the
    // ambient revision, which is the active one rather than [revision]:
    // callers install before entering their own override scope.
    final targetShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: revision,
    );

    final ShorebirdProcessResult result;
    try {
      result = await runScoped(
        () => process.run(
          executable,
          precacheArguments,
          workingDirectory: targetDirectory.path,
        ),
        values: {shorebirdEnvRef.overrideWith(() => targetShorebirdEnv)},
      );
    } on Exception catch (error) {
      precacheProgress.fail('Failed to precache Flutter $version');
      // The checkout itself is intact and precache re-runs on a missing
      // stamp, so retrying is the whole repair.
      final exception = CacheCorruptedException(
        'Failed to precache Flutter $version: $error.',
        remedy: 'Run this command again to retry the precache.',
      );
      logger.err('$exception');
      throw exception;
    }
    if (result.exitCode != ExitCode.success.code) {
      precacheProgress.fail('Failed to precache Flutter $version');
      final stderr = '${result.stderr}'.trim();
      final exception = CacheCorruptedException(
        'flutter precache exited with code ${result.exitCode}: $stderr.',
        remedy: 'Run this command again to retry the precache.',
      );
      logger.err('$exception');
      throw exception;
    }
    try {
      precacheStamp.createSync();
    } on FileSystemException catch (error) {
      precacheProgress.fail('Failed to precache Flutter $version');
      final exception = CacheCorruptedException(
        'Failed to record the precache for Flutter $version: $error.',
        remedy: 'Make sure ${precacheStamp.path} is writable and retry.',
      );
      logger.err('$exception');
      throw exception;
    }
    precacheProgress.complete();
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
    final result = await process.run(executable, args, useVendedFlutter: false);

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

  /// Executes `flutter config --list` and returns the output as a map.
  Map<String, dynamic> getConfig() {
    final args = ['config', '--list'];
    final result = process.runSync(executable, args);
    // Gracefully handle errors (e.g. older Flutter versions that don't support
    // `flutter config --list`).
    if (result.exitCode != ExitCode.success.code) return <String, dynamic>{};
    final output = '${result.stdout}';
    final config = <String, dynamic>{};
    final lines = LineSplitter.split(output).toList();
    for (final line in lines.skip(1)) {
      final index = line.indexOf(':');
      if (index == -1) continue;
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim();
      config[key] = value;
    }
    return config;
  }

  /// Converts a full git revision to a short revision string.
  String shortRevisionString(String revision) => revision.substring(0, 10);

  /// Given a revision and a version, formats them into a single string.
  ///
  /// e.g. 3.16.3 and b9b2390296b9b2390296 -> 3.16.3 (b9b2390296)
  String formatVersion({required String revision, required String? version}) {
    version ??= 'unknown';
    return '$version (${shortRevisionString(revision)})';
  }

  /// Returns the current Shorebird Flutter version and revision.
  /// Returns unknown if the version check fails.
  Future<String> getVersionAndRevision() async {
    late final String? version;

    try {
      version = await getVersionString();
    } on Exception {
      version = 'unknown';
    }

    return formatVersion(
      version: version,
      revision: shorebirdEnv.flutterRevision,
    );
  }

  /// Returns the current Shorebird Flutter version.
  /// Throws a [ProcessException] if the version check fails.
  /// Returns `null` if the version check succeeds but the version cannot be
  /// parsed.
  Future<String?> getVersionString() async {
    final flutterRevision = shorebirdEnv.flutterRevision;
    return getVersionForRevision(flutterRevision: flutterRevision);
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

  /// Returns the human readable version for a given git revision
  /// e.g. b9b2390296b9b2390296 -> 3.16.3
  Future<String?> getVersionForRevision({
    required String flutterRevision,
  }) async {
    final result = await git.forEachRef(
      contains: flutterRevision,
      format: '%(refname:short)',
      pattern: 'refs/remotes/origin/flutter_release/*',
      directory: _workingDirectory(),
    );

    return LineSplitter.split(result)
        .map((e) => e.replaceFirst('origin/flutter_release/', ''))
        .toList()
        .firstOrNull;
  }

  /// Pattern for a valid git hash (4-40 hex characters).
  /// Git allows short hashes as long as they're unambiguous.
  static final _gitHashPattern = RegExp(r'^[0-9a-fA-F]{4,40}$');

  /// Translates [versionOrHash] into a Flutter revision. If this is a semver
  /// version, it will look up the git revision for that version. If not, it
  /// will check if it's a valid git hash that exists in the local Flutter repo.
  ///
  /// Returns the full hash if valid, or null if it's neither a valid semver
  /// version nor a valid git hash that exists locally.
  Future<String?> resolveFlutterRevision(String versionOrHash) async {
    final parsedVersion = tryParseVersion(versionOrHash);
    if (parsedVersion != null) {
      return getRevisionForVersion(versionOrHash);
    }

    // If we were unable to parse the version, check if it's a valid git hash.
    if (!_gitHashPattern.hasMatch(versionOrHash)) {
      return null;
    }

    // Verify the hash exists locally by resolving it to its full hash.
    try {
      final fullHash = await git.revParse(
        revision: versionOrHash,
        directory: _workingDirectory(),
      );
      return fullHash;
    } on ProcessException {
      return null;
    }
  }

  /// Translates [versionOrHash] into a Flutter [Version]. If [versionOrHash]
  /// is semver version string, it will simply parse that into a [Version]. If
  /// not, it will assume that the input is a git commit hash and attempt to
  /// map it to a Flutter version.
  Future<Version?> resolveFlutterVersion(String versionOrHash) async {
    final parsedVersion = tryParseVersion(versionOrHash);
    if (parsedVersion != null) {
      return parsedVersion;
    }

    try {
      // If we were unable to parse the version, assume it's a revision hash.
      final versionString = await getVersionForRevision(
        flutterRevision: versionOrHash,
      );
      return versionString != null ? tryParseVersion(versionString) : null;
    } on Exception {
      return null;
    }
  }

  /// Whether `gen_snapshot` should be invoked with `--strip` for a build
  /// targeting [platform] on the Flutter pin identified by [flutterRevision].
  ///
  /// On non-Android platforms (iOS, macOS, Linux, Windows, iOS framework,
  /// AAR), AGP is not in the pipeline, so we always pre-strip in gen_snapshot.
  ///
  /// On Android, the answer depends on the Flutter version: from 3.44 onward
  /// AGP performs the strip and emits the matching `.sym` companion;
  /// pre-stripping in gen_snapshot on those versions leaves AGP with nothing
  /// to strip and trips flutter_tools' post-build verification. See
  /// [libappStrippedByAgpConstraint].
  ///
  /// An unresolvable [flutterRevision] (e.g. a development branch) is treated
  /// as satisfying the constraint, since the alternative — pre-stripping —
  /// would fail the post-build check on any 3.44+ pin.
  Future<bool> shouldPreStripLibappInGenSnapshot({
    required ReleasePlatform platform,
    required String flutterRevision,
  }) async {
    if (platform != ReleasePlatform.android) return true;
    final version = await resolveFlutterVersion(flutterRevision);
    return !libappStrippedByAgpConstraint.isSatisfiedBy(
      version: version ?? libappStrippedByAgpConstraint.minVersion,
      revision: flutterRevision,
    );
  }

  /// Fetches the latest remote refs for the Flutter clone so that
  /// release branch pointers (e.g. `flutter_release/3.38.5`) are up to date.
  Future<void> fetchRemoteRefs() async {
    try {
      await git.fetch(directory: _workingDirectory());
    } on Exception {
      logger.warn(
        'Failed to fetch latest Flutter versions. '
        'Resolving with potentially stale data.',
      );
    }
  }

  /// Returns the git revision for the provided [version].
  /// e.g. 3.16.3 -> b9b23902966504a9778f4c07e3a3487fa84dcb2a
  Future<String?> getRevisionForVersion(String version) async {
    try {
      final result = await git.revParse(
        revision: 'refs/remotes/origin/flutter_release/$version',
        directory: _workingDirectory(),
      );
      return LineSplitter.split(result).toList().firstOrNull;
    } on ProcessException {
      return null;
    }
  }

  /// Get the list of Flutter versions for the given [revision].
  Future<List<String>> getVersions({String? revision}) async {
    final result = await git.forEachRef(
      format: '%(refname:short)',
      pattern: 'refs/remotes/origin/flutter_release/*',
      directory: _workingDirectory(revision: revision),
    );
    return LineSplitter.split(
      result,
    ).map((e) => e.replaceFirst('origin/flutter_release/', '')).toList();
  }
}
