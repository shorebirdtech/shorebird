import 'package:pub_semver/pub_semver.dart';

/// The primary release artifact architecture for Windows releases.
/// This is a zipped copy of `build/windows/x64/runner/Release`, which is
/// produced by the `flutter build windows --release` command. It contains, at
/// its top level:
///   - flutter.dll
///   - app.exe (where `app` is the name of the Flutter app)
///   - data/, which contains flutter assets and the app.so file
const primaryWindowsReleaseArtifactArch = 'win_archive';

/// The minimum allowed Flutter version for creating Windows releases.
final minimumSupportedWindowsFlutterVersion = Version(3, 27, 2);

/// Revisions of Flutter 3.27.1 that support windows.
const windowsFlutterGitHashesBelowMinVersion = {
  '56228c343d6c7fd3e1e548dbb290f9713bb22aa9',
};

/// A warning message printed at the start of `shorebird release windows` and
/// `shorebird patch windows` commands.
const windowsBetaWarning = '''
Windows support is currently in beta.
Please report issues at https://github.com/shorebirdtech/shorebird/issues/new
''';
