import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/logger.dart';

const exportMethodArgName = 'export-method';
const exportOptionsPlistArgName = 'export-options-plist';

void showiOSStatusWarning() {
  final url = link(
    uri: Uri.parse('https://docs.shorebird.dev/status'),
  );
  logger
    ..warn('iOS support is beta. Some apps may run slower after patching.')
    ..info('See $url for more information.');
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

  final String message;
}

/// A reference to a [Ios] instance.
final iosRef = create(Ios.new);

/// The [Ios] instance available in the current zone.
Ios get ios => read(iosRef);

class Ios {
  File exportOptionsPlistFromArgs(ArgResults results) {
    final exportPlistArg = results[exportOptionsPlistArgName] as String?;
    if (exportPlistArg != null && results.wasParsed(exportMethodArgName)) {
      throw ArgumentError(
        '''Cannot specify both --$exportMethodArgName and --$exportOptionsPlistArgName.''',
      );
    }

    final File? exportOptionsPlist;
    if (exportPlistArg != null) {
      exportOptionsPlist = File(exportPlistArg);
      _validateExportOptionsPlist(exportOptionsPlist);
      return exportOptionsPlist;
    }

    final ExportMethod? exportMethod;
    if (results.wasParsed(exportMethodArgName)) {
      exportMethod = ExportMethod.values.firstWhere(
        (element) => element.argName == results[exportMethodArgName] as String,
      );
    } else {
      exportMethod = null;
    }

    return createExportOptionsPlist(
      exportMethod: exportMethod ?? ExportMethod.appStore,
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
