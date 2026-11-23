// cspell:words bsdtar msvc
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The zizmor release the generated `zizmor` job runs and `generate`
/// runs locally, downloaded from its GitHub release rather than through
/// a third-party action, and checked against [zizmorSha256] before use.
///
/// To bump it, download every asset of the new release and check each
/// one's build provenance before taking its SHA-256:
///
/// ```sh
/// gh release download v<version> --repo zizmorcore/zizmor
/// for f in zizmor-*; do
///   gh attestation verify "$f" --repo zizmorcore/zizmor && shasum -a 256 "$f"
/// done
/// ```
///
/// `gh attestation verify` checks that zizmor's own release workflow
/// built the file, so a release asset swapped after publishing fails
/// it. Then update [zizmorVersion] and every entry of [zizmorSha256].
/// Neither `generate` nor Dependabot bumps it.
const zizmorVersion = '1.33.1';

/// The SHA-256 of each of [zizmorVersion]'s release assets, by asset
/// name. See [zizmorVersion] for how to take them.
const zizmorSha256 = <String, String>{
  'zizmor-aarch64-apple-darwin.tar.gz':
      '68516d45723aac36e9c87c47d56e8418009fcb919c6ceb44514d85b9d0c1c011',
  'zizmor-aarch64-unknown-linux-gnu.tar.gz':
      'aa487c792a7cbbe86e4f8dccd3b66de33b3b51813c090aaa0842d7ea08a3fc35',
  'zizmor-x86_64-apple-darwin.tar.gz':
      '8b609d38243c6dd6ddd29bf93d02d886eb507383fe4735b1cde73e66e4de4f29',
  'zizmor-x86_64-pc-windows-msvc.zip':
      'f02ebeedf651da468b4de19d31f0609050af74e11be41dc46d82e355cf44f68b',
  'zizmor-x86_64-unknown-linux-gnu.tar.gz':
      '3e6a301c7a820a2501915f5a9de8c0486da82bdec7965f068477538a98743d43',
};

/// The URL of [asset] in [zizmorVersion]'s GitHub release.
String zizmorAssetUrl(String asset) =>
    'https://github.com/zizmorcore/zizmor/releases/download/'
    'v$zizmorVersion/$asset';

/// The release asset that runs on [abi], or `null` when zizmor publishes
/// none for it. Windows on Arm gets the x64 build, which it emulates.
String? zizmorAssetFor(Abi abi) => switch (abi) {
  Abi.linuxX64 => 'zizmor-x86_64-unknown-linux-gnu.tar.gz',
  Abi.linuxArm64 => 'zizmor-aarch64-unknown-linux-gnu.tar.gz',
  Abi.macosX64 => 'zizmor-x86_64-apple-darwin.tar.gz',
  Abi.macosArm64 => 'zizmor-aarch64-apple-darwin.tar.gz',
  Abi.windowsX64 || Abi.windowsArm64 => 'zizmor-x86_64-pc-windows-msvc.zip',
  _ => null,
};

/// The arguments the generated `zizmor` job passes, so `generate`'s local
/// run reports what that job will. `--offline` because the job gets no
/// token: zizmor's online audits call the GitHub API.
const zizmorArgs = ['--offline', '.github/workflows'];

/// The outcome of a zizmor run.
typedef ZizmorResult = ({int exitCode, String stdout, String stderr});

/// Finds or downloads zizmor [zizmorVersion] and runs it.
class Zizmor {
  /// Creates a [Zizmor]. [cacheDir] defaults to a per-user cache
  /// directory. [download] (which fetches a URL's bytes), [abi],
  /// [environment] and [onPath] (the command looked up on `PATH`) are
  /// exposed for tests.
  Zizmor({
    String? cacheDir,
    Future<List<int>> Function(Uri url)? download,
    Abi? abi,
    Map<String, String>? environment,
    String? onPath,
  }) : _abi = abi ?? Abi.current(),
       _environment = environment ?? Platform.environment,
       _download = download ?? _httpGet,
       _cacheDir = cacheDir,
       _onPath = onPath;

  final Abi _abi;
  final Map<String, String> _environment;
  final Future<List<int>> Function(Uri url) _download;
  final String? _cacheDir;
  final String? _onPath;

  bool get _isWindows => _abi == Abi.windowsX64 || _abi == Abi.windowsArm64;

  String get _exeName => _isWindows ? 'zizmor.exe' : 'zizmor';

  /// Where downloaded releases are kept, one directory per version.
  String get cacheDir =>
      _cacheDir ??
      (_isWindows
          ? p.join(
              _environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
              'shorebird_ci',
              'zizmor',
            )
          : p.join(
              _environment['XDG_CACHE_HOME'] ??
                  p.join(
                    _environment['HOME'] ?? Directory.systemTemp.path,
                    '.cache',
                  ),
              'shorebird_ci',
              'zizmor',
            ));

  /// The path of a zizmor [zizmorVersion]: a `zizmor` on `PATH` at that
  /// version, else one downloaded to [cacheDir], checking the release
  /// asset's SHA-256 first. Another version on `PATH` is passed over,
  /// since its findings can differ from the generated job's.
  ///
  /// Throws a [ZizmorException] when there is no release for this
  /// platform, the download fails or the checksum doesn't match.
  Future<String> ensure() async {
    final onPath = await _onPathAtVersion();
    if (onPath != null) return onPath;

    final installed = p.join(cacheDir, zizmorVersion, _exeName);
    if (File(installed).existsSync()) return installed;

    final asset = zizmorAssetFor(_abi);
    if (asset == null) {
      throw ZizmorException('zizmor publishes no release for $_abi');
    }
    final List<int> bytes;
    try {
      bytes = await _download(Uri.parse(zizmorAssetUrl(asset)));
    } on Exception catch (e) {
      throw ZizmorException('could not download ${zizmorAssetUrl(asset)}: $e');
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != zizmorSha256[asset]) {
      throw ZizmorException(
        '${zizmorAssetUrl(asset)} has SHA-256 $actual, '
        'expected ${zizmorSha256[asset]}',
      );
    }

    // Extract beside the final directory and rename it into place, so an
    // interrupted run never leaves a half-written binary that looks
    // installed.
    Directory(cacheDir).createSync(recursive: true);
    final staging = Directory(cacheDir).createTempSync('$zizmorVersion.');
    try {
      final archive = File(p.join(staging.path, asset))
        ..writeAsBytesSync(bytes);
      final result = await Process.run(tar, [
        '-xf',
        archive.path,
        '-C',
        staging.path,
      ]);
      if (result.exitCode != 0) {
        throw ZizmorException('could not extract $asset: ${result.stderr}');
      }
      archive.deleteSync();
      if (!File(p.join(staging.path, _exeName)).existsSync()) {
        throw ZizmorException('$asset holds no $_exeName');
      }
      final target = Directory(p.join(cacheDir, zizmorVersion));
      if (target.existsSync()) target.deleteSync(recursive: true);
      staging.renameSync(target.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
    return installed;
  }

  /// Runs zizmor [zizmorVersion] with [zizmorArgs] in [repoRoot].
  Future<ZizmorResult> run(String repoRoot) async {
    final executable = await ensure();
    final result = await Process.run(
      executable,
      [...zizmorArgs, '--color', 'never'],
      workingDirectory: repoRoot,
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }

  /// The `tar` that extracts the release. Windows' own (bsdtar) extracts
  /// zip files; a Git for Windows `tar` earlier on `PATH` doesn't, so it's
  /// named in full there.
  @visibleForTesting
  String get tar => _isWindows
      ? p.join(_environment['SystemRoot'] ?? r'C:\Windows', 'System32', 'tar')
      : 'tar';

  Future<String?> _onPathAtVersion() async {
    try {
      final command = _onPath ?? _exeName;
      final result = await Process.run(command, ['--version']);
      if (result.exitCode != 0) return null;
      final reported = (result.stdout as String).trim();
      return reported == 'zizmor $zizmorVersion' ? command : null;
    } on ProcessException {
      return null;
    }
  }
}

/// zizmor couldn't be found or installed.
class ZizmorException implements Exception {
  /// Creates a [ZizmorException].
  ZizmorException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

// coverage:ignore-start
// The network call behind [Zizmor.ensure]; tests inject a fake.
Future<List<int>> _httpGet(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(url);
    request.headers.add('User-Agent', 'shorebird_ci');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final bytes = <int>[];
    await response.forEach(bytes.addAll);
    return bytes;
  } finally {
    client.close();
  }
}

// coverage:ignore-end
