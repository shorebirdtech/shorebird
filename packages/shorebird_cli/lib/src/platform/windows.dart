import 'package:pub_semver/pub_semver.dart';

/// The minimum allowed Flutter version for creating Windows releases.
final minimumSupportedWindowsFlutterVersion = Version(3, 27, 1);

/// A warning message printed at the start of `shorebird release windows` and
/// `shorebird patch windows` commands.
const windowsBetaWarning = '''
Windows support is currently in beta.
Please report issues at https://github.com/shorebirdtech/shorebird/issues/new
''';
