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
