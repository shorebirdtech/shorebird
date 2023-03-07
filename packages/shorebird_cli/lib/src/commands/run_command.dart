import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';

typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// {@template run_command}
///
/// `shorebird run`
/// Run the Flutter application.
/// {@endtemplate}
class RunCommand extends Command<int> {
  /// {@macro run_command}
  RunCommand({
    required Auth auth,
    required ShorebirdCodePushApiClientBuilder codePushApiClientBuilder,
    required Logger logger,
    StartProcess? startProcess,
  })  : _auth = auth,
        _buildCodePushApiClient = codePushApiClientBuilder,
        _logger = logger,
        _startProcess = startProcess ?? Process.start;

  @override
  String get description => 'Run the Flutter application.';

  @override
  String get name => 'run';

  final Auth _auth;
  final ShorebirdCodePushApiClientBuilder _buildCodePushApiClient;
  final Logger _logger;
  final StartProcess _startProcess;

  @override
  Future<int> run() async {
    final session = _auth.currentSession;
    if (session == null) {
      _logger
        ..err('You must be logged in to run.')
        ..err("Run 'shorebird login' to log in and try again.");
      return ExitCode.noUser.code;
    }

    // This will likely change in the future as each Flutter application
    // will not need to cache its own copy of the Shorebird engine.
    final shorebirdEnginePath = p.join(
      Directory.current.path,
      '.shorebird',
      'engine',
    );
    final shorebirdEngine = Directory(shorebirdEnginePath);
    final shorebirdEngineCache = File(
      p.join(Directory.current.path, '.shorebird', 'cache', 'engine.zip'),
    );

    if (!shorebirdEngineCache.existsSync()) {
      final downloadEngineProgress = _logger.progress(
        'Downloading shorebird engine',
      );
      try {
        final codePushApiClient = _buildCodePushApiClient(
          apiKey: session.apiKey,
        );
        await _downloadShorebirdEngine(
          codePushApiClient,
          shorebirdEngineCache.path,
        );
        downloadEngineProgress.complete();
      } catch (error) {
        downloadEngineProgress.fail(
          'Failed to download shorebird engine: $error',
        );
        return ExitCode.software.code;
      }
    }

    if (!shorebirdEngine.existsSync()) {
      final buildingEngine = _logger.progress(
        'Building shorebird engine',
      );
      try {
        await _extractShorebirdEngine(
          shorebirdEngineCache.path,
          shorebirdEngine.path,
          _startProcess,
        );
        buildingEngine.complete();
      } catch (error) {
        buildingEngine.fail(
          'Failed to build shorebird engine: $error',
        );
        return ExitCode.software.code;
      }
    }

    _logger.info('Running app...');
    final process = await _startProcess(
      'flutter',
      [
        'run',
        // Eventually we should support running in both debug and release mode.
        '--release',
        '--local-engine-src-path',
        shorebirdEnginePath,
        '--local-engine',
        // This is temporary because the Shorebird engine currently
        // only supports Android arm64.
        'android_release_arm64',
        if (argResults?.rest != null) ...argResults!.rest
      ],
      runInShell: true,
    );

    process.stdout.listen((event) {
      _logger.info(utf8.decode(event));
    });
    process.stderr.listen((event) {
      _logger.err(utf8.decode(event));
    });

    return process.exitCode;
  }
}

Future<void> _downloadShorebirdEngine(
  ShorebirdCodePushApiClient codePushClient,
  String path,
) async {
  final engine = await codePushClient.downloadEngine('latest');
  final targetFile = File(path);

  if (targetFile.existsSync()) targetFile.deleteSync(recursive: true);

  targetFile.createSync(recursive: true);
  await targetFile.writeAsBytes(engine, flush: true);
}

Future<void> _extractShorebirdEngine(
  String archivePath,
  String targetPath,
  StartProcess startProcess,
) async {
  final targetDirectory = Directory(targetPath);

  if (targetDirectory.existsSync()) targetDirectory.deleteSync(recursive: true);

  targetDirectory.createSync(recursive: true);

  await Isolate.run(
    () async {
      final inputStream = InputFileStream(archivePath);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      extractArchiveToDisk(archive, targetPath);
    },
  );

  const executables = [
    'flutter/prebuilts/macos-x64/dart-sdk/bin/dart',
    'flutter/prebuilts/macos-x64/dart-sdk/bin/dartaotruntime',
    'out/android_release_arm64/clang_x64/gen_snapshot',
    'out/android_release_arm64/clang_x64/gen_snapshot_arm64',
    'out/android_release_arm64/clang_x64/impellerc',
  ];

  // TODO(felangel): verify whether additional steps are necessary on Windows.
  if (Platform.isMacOS || Platform.isLinux) {
    for (final executable in executables) {
      final process = await startProcess(
        'chmod',
        ['+x', p.join(targetPath, executable)],
      );
      await process.exitCode;
    }
  }
}
