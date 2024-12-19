import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
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
/// The method used to export the IPA. This is passed to the Flutter tool.
/// Acceptable values can be found by running `flutter build ipa -h`.
/// {@endtemplate}
enum ExportMethod {
  /// Upload to the App Store.
  appStore('app-store', 'Upload to the App Store'),

  /// Ad-hoc distribution.
  adHoc(
    'ad-hoc',
    '''
Test on designated devices that do not need to be registered with the Apple developer account.
    Requires a distribution certificate.''',
  ),

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

/// A reference to a [Ios] instance.
final iosRef = create(Ios.new);

/// The [Ios] instance available in the current zone.
Ios get ios => read(iosRef);

/// A class that provides information about the iOS platform.
class Ios {
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
