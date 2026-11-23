import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/version.dart';

/// Returns the version of Shorebird's Flutter, or null if it cannot be
/// determined.
Future<String?> tryGetFlutterVersion() async {
  try {
    return await shorebirdFlutter.getVersionString();
  } on Exception catch (error) {
    logger.detail('Unable to determine Flutter version.\n$error');
    return null;
  }
}

/// The pinned Flutter's engine revision, or null if that Flutter isn't
/// installed yet: it is installed the first time a command uses it.
String? _tryGetEngineRevision() {
  try {
    return shorebirdEnv.shorebirdEngineRevision;
  } on CacheCorruptedException {
    return null;
  }
}

/// The Shorebird, Flutter and engine versions as shown by
/// `shorebird --version` and `shorebird doctor`.
String versionBanner({required String? flutterVersion}) {
  final shorebirdFlutterPrefix = StringBuffer('Flutter');
  if (flutterVersion != null) {
    shorebirdFlutterPrefix.write(' $flutterVersion');
  }
  return '''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
$shorebirdFlutterPrefix • revision ${shorebirdEnv.flutterRevision}
Engine • revision ${_tryGetEngineRevision() ?? 'unknown (Flutter not installed yet)'}''';
}

/// The Shorebird, Flutter and engine versions as JSON output fields.
Map<String, String?> versionJson({required String? flutterVersion}) => {
  'shorebird_version': packageVersion,
  'flutter_version': flutterVersion,
  'flutter_revision': shorebirdEnv.flutterRevision,
  'engine_revision': _tryGetEngineRevision(),
};
