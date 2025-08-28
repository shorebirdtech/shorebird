import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

Future<List<String>> getFlutterVersions(Directory flutterDirectory) async {
  final result = await git.forEachRef(
    format: '%(refname:short)',
    pattern: 'refs/remotes/origin/flutter_release/*',
    directory: flutterDirectory.path,
  );
  return LineSplitter.split(
    result,
  ).map((e) => e.replaceFirst('origin/flutter_release/', '')).toList();
}

Future<String> engineHashFromFlutterVersion({
  required Directory flutterCheckout,
  required String flutterVersion,
}) async {
  final result = await git.git(
    [
      'show',
      'origin/flutter_release/$flutterVersion:bin/internal/engine.version',
    ],
    workingDirectory: flutterCheckout.path,
  );
  if (result.exitCode != 0) {
    throw Exception('Failed to get engine version for $flutterVersion');
  }
  return result.stdout.toString().trim();
}

Uri xcFrameworkDownloadUrl(String engineVersion) {
  return Uri.parse(
    'https://storage.googleapis.com/download.shorebird.dev/flutter_infra_release/flutter/$engineVersion/ios-release/artifacts.zip',
  );
}

Directory engineDirectory(String engineVersion) {
  return Directory('cache/engine/$engineVersion');
}

File iosArtifactsZip(String engineVersion) {
  return File(p.join(engineDirectory(engineVersion).path, 'ios-release.zip'));
}

Directory xcFramework(String engineVersion) {
  return Directory(
    p.join(
      engineDirectory(engineVersion).path,
      'ios-release',
      'Flutter.xcframework',
    ),
  );
}

Future<File> downloadIfNeeded(String engineVersion) async {
  final zipFile = iosArtifactsZip(engineVersion);
  if (zipFile.existsSync()) {
    return zipFile;
  }
  await zipFile.parent.create(recursive: true);
  final zipUrl = xcFrameworkDownloadUrl(engineVersion);
  final response = await http.get(zipUrl);
  if (response.statusCode != 200) {
    throw Exception('Failed to download $zipUrl: ${response.statusCode}');
  }
  await zipFile.writeAsBytes(response.bodyBytes);
  return zipFile;
}

void unzipInto({
  required Directory outDirectory,
  required File zipFile,
  bool Function(ArchiveFile)? filter,
}) {
  final bytes = zipFile.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive) {
    if (file.isFile) {
      if (filter != null && !filter(file)) {
        continue;
      }
      final filePath = p.join(outDirectory.path, file.name);
      final fileContent = file.content as List<int>;
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileContent);
    }
  }
}

Future<Directory> cacheFrameworkIfNeeded(
  Directory cacheDirectory,
  String engineVersion,
) async {
  final xcDirectory = xcFramework(engineVersion);
  if (xcDirectory.existsSync()) {
    return xcDirectory;
  }
  final zipFile = await downloadIfNeeded(engineVersion);
  final zipDirName = p.basenameWithoutExtension(zipFile.path);
  unzipInto(
    outDirectory: Directory(
      p.join(engineDirectory(engineVersion).path, zipDirName),
    )..createSync(recursive: true),
    zipFile: zipFile,
    filter: (file) => file.name.startsWith('Flutter.xcframework/'),
  );
  return xcDirectory;
}

Future<bool> checkSignature(String xcFrameworkPath) async {
  final result = await process.run(
    'codesign',
    ['-v', xcFrameworkPath],
  );
  if (result.exitCode != 0) {
    print(result.stderr);
  }
  return result.exitCode == 0;
}

Future<List<String>> getVersionsToCheck({
  required List<String> explicitVersions,
  required Directory flutterCheckout,
  required bool includeAll,
}) async {
  if (includeAll) {
    return getFlutterVersions(flutterCheckout);
  }
  return explicitVersions;
}

Future<void> logic(List<String> args) async {
  final argParser = ArgParser()
    ..addFlag('all', abbr: 'a', help: 'Check all versions.');
  final argResults = argParser.parse(args);
  final includeAll = argResults['all'] as bool;
  final explicitVersions = argResults.rest;

  final flutterCheckout = shorebirdEnv.flutterDirectory;
  final versions = await getVersionsToCheck(
    flutterCheckout: flutterCheckout,
    explicitVersions: explicitVersions,
    includeAll: includeAll,
  );

  if (versions.isEmpty) {
    print('No versions to check.');
    print('Use --all to check all versions.');
    print('Or specify versions to check.');
    return;
  }

  final cacheDirectory = Directory('cache');
  await cacheDirectory.create(recursive: true);

  for (final flutterVersion in versions) {
    final engineHash = await engineHashFromFlutterVersion(
      flutterCheckout: flutterCheckout,
      flutterVersion: flutterVersion,
    );
    final shortEngHash = engineHash.substring(0, 8);
    try {
      final xcFramework = await cacheFrameworkIfNeeded(
        cacheDirectory,
        engineHash,
      );
      final isSignatureOK = await checkSignature(xcFramework.path);
      final emoji = isSignatureOK ? '✅' : '❌';
      print('$emoji $flutterVersion (eng $shortEngHash)');
    } on Exception catch (e) {
      print('❓ $flutterVersion (eng $shortEngHash)');
      print(e);
    }
  }
}

Future<void> main(List<String> args) async {
  await runScoped(
    () async {
      await logic(args);
    },
    values: {
      shorebirdFlutterRef,
      gitRef,
      shorebirdEnvRef,
      processRef,
      loggerRef,
    },
  );
}
