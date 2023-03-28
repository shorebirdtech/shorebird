import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/engine_revision.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

mixin ShorebirdEngineMixin on ShorebirdConfigMixin {
  String get shorebirdEnginePath {
    return p.join(
      shorebirdConfigDir,
      'engines',
      shorebirdEngineRevision,
    );
  }

  // This will likely change in the future as each Flutter application
  // will not need to cache its own copy of the Shorebird engine.
  Future<void> ensureEngineExists() async {
    final shorebirdEngine = Directory(shorebirdEnginePath);

    if (!shorebirdEngine.existsSync()) {
      final downloadEngineProgress = logger.progress(
        'Downloading shorebird engine',
      );
      final tempDir = Directory.systemTemp.createTempSync();
      final engineArchivePath = p.join(tempDir.path, 'engine.zip');
      try {
        final codePushClient = buildCodePushClient(
          apiKey: auth.currentSession!.apiKey,
          hostedUri: hostedUri,
        );
        await _downloadShorebirdEngine(codePushClient, engineArchivePath);
        downloadEngineProgress.complete();
      } catch (error) {
        downloadEngineProgress.fail();
        throw Exception('Failed to download shorebird engine: $error');
      }

      final buildingEngine = logger.progress('Building shorebird engine');
      try {
        await _extractShorebirdEngine(
          engineArchivePath,
          shorebirdEngine.path,
          startProcess,
        );
        buildingEngine.complete();
      } catch (error) {
        buildingEngine.fail();
        throw Exception('Failed to build shorebird engine: $error');
      }
    }
  }

  Future<void> _downloadShorebirdEngine(
    CodePushClient codePushClient,
    String path,
  ) async {
    final engine = await codePushClient.downloadEngine(
      revision: shorebirdEngineRevision,
    );
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
    final targetDir = Directory(targetPath);

    if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);

    targetDir.createSync(recursive: true);

    await Isolate.run(
      () async {
        final inputStream = InputFileStream(archivePath);
        final archive = ZipDecoder().decodeBuffer(inputStream);
        extractArchiveToDisk(archive, targetPath);
      },
    );

    // TODO(felangel): support windows and linux
    // https://github.com/shorebirdtech/shorebird/issues/37
    // coverage:ignore-start
    if (Platform.isMacOS) {
      const executables = [
        'flutter/prebuilts/macos-x64/dart-sdk/bin/dart',
        'flutter/prebuilts/macos-x64/dart-sdk/bin/dartaotruntime',
        'out/android_release_arm64/clang_x64/gen_snapshot',
        'out/android_release_arm64/clang_x64/gen_snapshot_arm64',
        'out/android_release_arm64/clang_x64/impellerc',
        'out/android_release_arm64/clang_x64/impellerc',
        'out/android_release_arm64/clang_arm64/gen_snapshot',
        'out/android_release_arm64/clang_arm64/gen_snapshot_arm64',
        'out/android_release_arm64/clang_arm64/impellerc',
        'out/android_release_arm64/clang_arm64/impellerc',
        'out/host_release/gen/const_finder.dart.snapshot',
        'out/host_release/font-subset',
        'patch',
      ];

      for (final executable in executables) {
        final process = await startProcess(
          'chmod',
          ['+x', p.join(targetPath, executable)],
        );
        await process.exitCode;
      }
    }
    // coverage:ignore-end
  }
}
