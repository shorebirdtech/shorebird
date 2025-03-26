import 'dart:io';

import 'package:collection/collection.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:xml/xml.dart';

/// Apple-specific platform options, corresponding to different Flutter target
/// platforms.
enum ApplePlatform {
  /// iOS
  ios,

  /// macOS
  macos,
}

/// A record containing the exit code and optionally link percentage
/// returned by `runLinker`.
typedef LinkResult = ({int exitCode, double? linkPercentage});

/// {@template missing_xcode_project_exception}
/// Thrown when the Flutter project does not have iOS configured as a platform.
/// {@endtemplate}
class MissingXcodeProjectException implements Exception {
  /// {@macro missing_xcode_project_exception}
  const MissingXcodeProjectException(this.projectPath);

  /// Expected path of the XCode project.
  final String projectPath;

  @override
  String toString() {
    return '''
Could not find an Xcode project in $projectPath.
To add iOS, run "flutter create . --platforms ios"
To add macOS, run "flutter create . --platforms macos"''';
  }
}

/// {@template export_method}
/// The method used to export the IPA. This is passed to the Flutter tool.
/// Acceptable values can be found by running `flutter build ipa -h`.
/// {@endtemplate}
enum ExportMethod {
  /// Upload to the App Store.
  appStore('app-store', 'Upload to the App Store'),

  /// Ad-hoc distribution.
  adHoc('ad-hoc', '''
Test on designated devices that do not need to be registered with the Apple developer account.
    Requires a distribution certificate.'''),

  /// Development distribution.
  development(
    'development',
    '''Test only on development devices registered with the Apple developer account.''',
  ),

  /// Enterprise distribution.
  enterprise(
    'enterprise',
    'Distribute an app registered with the Apple Developer Enterprise Program.',
  );

  /// {@macro export_method}
  const ExportMethod(this.argName, this.description);

  /// The command-line argument name for this export method.
  final String argName;

  /// A description of this method and how/when it should be used.
  final String description;
}

/// {@template invalid_export_options_plist_exception}
/// Thrown when an invalid export options plist is provided.
/// {@endtemplate}
class InvalidExportOptionsPlistException implements Exception {
  /// {@macro invalid_export_options_plist_exception}
  InvalidExportOptionsPlistException(this.message);

  /// An explanation of this exception.
  final String message;

  @override
  String toString() => message;
}

/// The minimum allowed Flutter version for creating iOS releases.
final minimumSupportedIosFlutterVersion = Version(3, 22, 2);

/// The minimum allowed Flutter version for creating macOS releases.
final minimumSupportedMacosFlutterVersion = Version(3, 27, 4);

/// A reference to a [Apple] instance.
final appleRef = create(Apple.new);

/// The [Apple] instance available in the current zone.
Apple get apple => read(appleRef);

/// A class that provides information about the iOS platform.
class Apple {
  /// Copies the supplement files into the build directory.
  /// Currently we run gen_snapshot from `flutter`, both for the release and
  /// patch builds. Both times it produces supplement files in a directory.
  /// In the release case, these files are zipped up and stored as an artifact
  /// on our servers for later use. In the patch case, they were created on
  /// disk just before this call.
  /// In both cases we need to copy the supplement files from these directories
  /// to right next to where the snapshot files are before calling into
  /// `aot_tools` to link the two snapshots together.
  // TODO(eseidel): We should pass the entire supplement directories to
  // `aot_tools` rather than having to know the contents within `shorebird`.
  void copySupplementFilesToSnapshotDirs({
    required Directory releaseSupplementDir,
    required Directory releaseSnapshotDir,
    required Directory patchSupplementDir,
    required Directory patchSnapshotDir,
  }) {
    // All known supplement files names seen across all Flutter versions.
    final supplementFileNames = <String>[
      'App.ct.link',
      'App.class_table.json',
      'App.ft.link',
      'App.field_table.json',
    ];

    // This uses maybeCopy because not all versions of gen_snapshot/aot_tools
    // use the same supplement files. At the `shorebird` level we don't know
    // which files should be present, so we just try to copy all.
    void maybeCopy(File file, Directory destDir, {String? newBaseName}) {
      if (!file.existsSync()) return;
      final baseName = p.basename(file.path);
      final destName =
          newBaseName != null
              ? baseName.replaceFirst('App', newBaseName)
              : baseName;
      file.copySync(p.join(destDir.path, destName));
    }

    final releaseSupplementFiles = supplementFileNames.map(
      (name) => File(p.join(releaseSupplementDir.path, name)),
    );
    for (final file in releaseSupplementFiles) {
      maybeCopy(file, releaseSnapshotDir);
    }

    final patchSupplementFiles = supplementFileNames.map(
      (name) => File(p.join(patchSupplementDir.path, name)),
    );
    const patchSnapshotBaseName = 'out';
    for (final file in patchSupplementFiles) {
      maybeCopy(file, patchSnapshotDir, newBaseName: patchSnapshotBaseName);
    }
  }

  /// Returns the set of flavors for the Xcode project associated with
  /// [platform], if this project has that platform configured.
  Set<String>? flavors({required ApplePlatform platform}) {
    final projectRoot = shorebirdEnv.getFlutterProjectRoot()!;
    // Ideally, we would use `xcodebuild -list` to detect schemes/flavors.
    // Unfortunately, many projects contain schemes that are not flavors, and we
    // don't want to create flavors for these schemes. See
    // https://github.com/shorebirdtech/shorebird/issues/1703 for an example.
    // Instead, we look in `[platform]/Runner.xcodeproj/xcshareddata/xcschemes`
    // for xcscheme files (which seem to be 1-to-1 with schemes in Xcode) and
    // filter out schemes that are marked as "wasCreatedForAppExtension".
    final platformDirName = switch (platform) {
      ApplePlatform.ios => 'ios',
      ApplePlatform.macos => 'macos',
    };
    final platformDir = Directory(p.join(projectRoot.path, platformDirName));
    if (!platformDir.existsSync()) {
      return null;
    }

    final xcodeProjDirectory = platformDir
        .listSync()
        .whereType<Directory>()
        .firstWhereOrNull((d) => p.extension(d.path) == '.xcodeproj');
    if (xcodeProjDirectory == null) {
      throw MissingXcodeProjectException(projectRoot.path);
    }

    final xcschemesDir = Directory(
      p.join(xcodeProjDirectory.path, 'xcshareddata', 'xcschemes'),
    );
    if (!xcschemesDir.existsSync()) {
      throw Exception('Unable to detect schemes in $xcschemesDir');
    }

    return xcschemesDir
        .listSync()
        .whereType<File>()
        .where((e) => p.extension(e.path) == '.xcscheme')
        .where((e) => p.basenameWithoutExtension(e.path) != 'Runner')
        .whereNot((e) => _isExtensionScheme(schemeFile: e))
        .map((file) => p.basenameWithoutExtension(file.path))
        .toSet();
  }

  // TODO(eseidel): Move this into a "linker" class rather than Apple.
  /// Runs the linking step to minimize differences between patch and release
  /// and maximize code that can be executed on the CPU.
  Future<LinkResult> runLinker({
    required File kernelFile,
    required File releaseArtifact,
    required List<String> splitDebugInfoArgs,
    required File aotOutputFile,
    required File vmCodeFile,
  }) async {
    final patch = aotOutputFile;
    final buildDirectory = shorebirdEnv.buildDirectory;

    if (!patch.existsSync()) {
      logger.err('Unable to find patch AOT file at ${patch.path}');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshotIos,
      ),
    );

    if (!analyzeSnapshot.existsSync()) {
      logger.err('Unable to find analyze_snapshot at ${analyzeSnapshot.path}');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }

    final genSnapshot = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.genSnapshotIos,
    );

    final linkProgress = logger.progress('Linking AOT files');
    double? linkPercentage;
    final dumpDebugInfoDir =
        await aotTools.isLinkDebugInfoSupported()
            ? Directory.systemTemp.createTempSync()
            : null;

    Future<void> dumpDebugInfo() async {
      if (dumpDebugInfoDir == null) return;

      final debugInfoZip = await dumpDebugInfoDir.zipToTempFile();
      debugInfoZip.copySync(p.join('build', Patcher.debugInfoFile.path));
      logger.detail('Link debug info saved to ${Patcher.debugInfoFile.path}');

      // If we're running on codemagic, export the patch-debug.zip artifact.
      // https://docs.codemagic.io/knowledge-others/upload-custom-artifacts
      final codemagicExportDir = platform.environment['CM_EXPORT_DIR'];
      if (codemagicExportDir != null) {
        logger.detail(
          '''Codemagic environment detected. Exporting ${Patcher.debugInfoFile.path} to $codemagicExportDir''',
        );
        try {
          debugInfoZip.copySync(
            p.join(codemagicExportDir, p.basename(Patcher.debugInfoFile.path)),
          );
        } on Exception catch (error) {
          logger.detail('''
Failed to export ${Patcher.debugInfoFile.path} to $codemagicExportDir.
$error''');
        }
      }
    }

    try {
      linkPercentage = await aotTools.link(
        base: releaseArtifact.path,
        patch: patch.path,
        analyzeSnapshot: analyzeSnapshot.path,
        genSnapshot: genSnapshot,
        outputPath: vmCodeFile.path,
        workingDirectory: buildDirectory.path,
        kernel: kernelFile.path,
        dumpDebugInfoPath: dumpDebugInfoDir?.path,
        additionalArgs: splitDebugInfoArgs,
      );
    } on Exception catch (error) {
      linkProgress.fail('Failed to link AOT files: $error');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    } finally {
      await dumpDebugInfo();
    }
    linkProgress.complete();
    return (exitCode: ExitCode.success.code, linkPercentage: linkPercentage);
  }

  /// Parses the .xcscheme file to determine if it was created for an app
  /// extension. We don't want to include these schemes as app flavors.
  ///
  /// xcschemes are XML files that contain metadata about the scheme, including
  /// whether it was created for an app extension. The top-level Scheme element
  /// has an optional attribute named `wasCreatedForAppExtension`.
  bool _isExtensionScheme({required File schemeFile}) {
    final xmlDocument = XmlDocument.parse(schemeFile.readAsStringSync());
    return xmlDocument.childElements
        .firstWhere((element) => element.name.local == 'Scheme')
        .attributes
        .any(
          (e) => e.localName == 'wasCreatedForAppExtension' && e.value == 'YES',
        );
  }
}
