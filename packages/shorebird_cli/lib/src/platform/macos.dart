import 'package:pub_semver/pub_semver.dart';

/// The minimum allowed Flutter version for creating macOS releases.
final minimumSupportedMacosFlutterVersion = Version(3, 27, 0);

/// A warning message printed at the start of `shorebird release macos` and
/// `shorebird patch macos` commands.
const macosBetaWarning = '''
macOS support is currently in beta.
Please report issues at https://github.com/shorebirdtech/shorebird/issues/new
''';
