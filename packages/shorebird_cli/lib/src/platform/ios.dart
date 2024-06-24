// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:xml/xml.dart';

/// {@template missing_ios_project_exception}
/// Thrown when the Flutter project does not have iOS configured as a platform.
/// {@endtemplate}
class MissingIOSProjectException implements Exception {
  /// {@macro missing_ios_project_exception}
  const MissingIOSProjectException(this.projectPath);

  /// Expected path of the XCode project.
  final String projectPath;

  @override
  String toString() {
    return '''
Could not find an iOS project in $projectPath.
To add iOS, run "flutter create . --platforms ios"''';
  }
}

/// {@template export_method}
/// The method used to export the IPA.
/// {@endtemplate}
enum ExportMethod {
  appStore('app-store', 'Upload to the App Store'),
  adHoc(
    'ad-hoc',
    '''
Test on designated devices that do not need to be registered with the Apple developer account.
    Requires a distribution certificate.''',
  ),
  development(
    'development',
    '''Test only on development devices registered with the Apple developer account.''',
  ),
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

/// Link to the supported versions documentation.
final supportedVersionsLink = link(
  uri: Uri.parse(
    'https://docs.shorebird.dev/flutter-version/#supported-flutter-versions',
  ),
);

/// A reference to a [Ios] instance.
final iosRef = create(Ios.new);

/// The [Ios] instance available in the current zone.
Ios get ios => read(iosRef);

class Ios {
  File exportOptionsPlistFromArgs(ArgResults results) {
    final exportPlistArg =
        results[CommonArguments.exportOptionsPlistArg.name] as String?;
    final exportMethodArgExists =
        results.options.contains(CommonArguments.exportMethodArg.name);
    if (exportPlistArg != null &&
        exportMethodArgExists &&
        results.wasParsed(CommonArguments.exportMethodArg.name)) {
      throw ArgumentError(
        '''Cannot specify both --${CommonArguments.exportMethodArg.name} and --${CommonArguments.exportOptionsPlistArg.name}.''',
      );
    }

    final File? exportOptionsPlist;
    if (exportPlistArg != null) {
      exportOptionsPlist = File(exportPlistArg);
      _validateExportOptionsPlist(exportOptionsPlist);
      return exportOptionsPlist;
    }

    final ExportMethod? exportMethod;
    if (exportMethodArgExists &&
        results.wasParsed(CommonArguments.exportMethodArg.name)) {
      exportMethod = ExportMethod.values.firstWhere(
        (element) =>
            element.argName ==
            results[CommonArguments.exportMethodArg.name] as String,
      );
    } else {
      exportMethod = null;
    }

    return createExportOptionsPlist(
      exportMethod: exportMethod ?? ExportMethod.appStore,
    );
  }

  /// Returns the set of flavors for the iOS project, if the project has an
  /// iOS platform configured.
  Set<String>? flavors() {
    final projectRoot = shorebirdEnv.getFlutterProjectRoot()!;
    // Ideally, we would use `xcodebuild -list` to detect schemes/flavors.
    // Unfortunately, many projects contain schemes that are not flavors,
    // and we don't want to create flavors for these schemes. See
    // https://github.com/shorebirdtech/shorebird/issues/1703 for an example.
    // Instead, we look in `ios/Runner.xcodeproj/xcshareddata/xcschemes` for
    // xcscheme files (which seem to be 1-to-1 with schemes in Xcode) and filter
    // out schemes that are marked as "wasCreatedForAppExtension".
    final iosDir = Directory(p.join(projectRoot.path, 'ios'));
    if (!iosDir.existsSync()) {
      return null;
    }

    final xcodeProjDirectory = iosDir
        .listSync()
        .whereType<Directory>()
        .firstWhereOrNull((d) => p.extension(d.path) == '.xcodeproj');
    if (xcodeProjDirectory == null) {
      throw MissingIOSProjectException(projectRoot.path);
    }

    final xcschemesDir = Directory(
      p.join(
        xcodeProjDirectory.path,
        'xcshareddata',
        'xcschemes',
      ),
    );
    if (!xcschemesDir.existsSync()) {
      throw Exception('Unable to detect iOS schemes in $xcschemesDir');
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

  /// Parses the .xcsheme file to determine if it was created for an app
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

  /// Creates an ExportOptions.plist file, which is used to tell xcodebuild to
  /// not manage the app version and build number. If we don't do this, then
  /// xcodebuild will increment the build number if it detects an App Store
  /// Connect build with the same version and build number. This is a problem
  /// for us when patching, as patches need to have the same version and build
  /// number as the release they are patching.
  /// See
  /// https://developer.apple.com/forums/thread/690647?answerId=689925022#689925022
  File createExportOptionsPlist({
    ExportMethod? exportMethod,
  }) {
    exportMethod ??= ExportMethod.appStore;
    final plistContents = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>uploadBitcode</key>
  <false/>
  <key>method</key>
  <string>${exportMethod.argName}</string>
</dict>
</plist>
''';
    final tempDir = Directory.systemTemp.createTempSync();
    final exportPlistFile = File(p.join(tempDir.path, 'ExportOptions.plist'))
      ..createSync(recursive: true)
      ..writeAsStringSync(plistContents);
    return exportPlistFile;
  }

  /// Verifies that [exportOptionsPlistFile] exists and sets
  /// manageAppVersionAndBuildNumber to false, which prevents Xcode from
  /// changing the version number out from under us.
  ///
  /// Throws an exception if validation fails, exits normally if validation
  /// succeeds.
  void _validateExportOptionsPlist(File exportOptionsPlistFile) {
    if (!exportOptionsPlistFile.existsSync()) {
      throw FileSystemException(
        '''Export options plist file ${exportOptionsPlistFile.path} does not exist''',
      );
    }

    final plist = Plist(file: exportOptionsPlistFile);
    if (plist.properties['manageAppVersionAndBuildNumber'] != false) {
      throw InvalidExportOptionsPlistException(
        '''Export options plist ${exportOptionsPlistFile.path} does not set manageAppVersionAndBuildNumber to false. This is required for shorebird to work.''',
      );
    }
  }
}
