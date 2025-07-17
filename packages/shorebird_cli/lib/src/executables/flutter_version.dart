import 'package:shorebird_cli/src/shorebird_process.dart';

/// Parses the output of `flutter --version` to get the version number.
///
/// The output of `flutter --version` is of the form:
///
/// ```text
/// Flutter 3.32.4 • channel stable • https://github.com/flutter/flutter.git
/// Framework • revision 6fba2447e9 (5 weeks ago) • 2025-06-12 19:03:56 -0700
/// Engine • revision 8cd19e509d (5 weeks ago) • 2025-06-12 16:30:12 -0700
/// Tools • Dart 3.8.1 • DevTools 2.45.1
/// ```
String? maybeParseFlutterVersionFromOutput(String output) {
  final flutterVersionRegex = RegExp(r'Flutter (\d+.\d+.\d+)');
  final match = flutterVersionRegex.firstMatch(output);
  return match?.group(1);
}

/// Parses the output of `flutter --version` to get the version number.
/// Unlike [maybeParseFlutterVersionFromOutput], this method throws an exception
/// if the version cannot be parsed.
String parseFlutterVersionFromOutput(String output) {
  final version = maybeParseFlutterVersionFromOutput(output);
  if (version == null) {
    throw Exception('Failed to parse Flutter version from output: $output');
  }
  return version;
}

/// Returns the Flutter version from a system-installed Flutter if available.
String flutterVersionFromSystemFlutter(ShorebirdProcess process) {
  try {
    final output = process.runSync('flutter', ['--version']);
    return parseFlutterVersionFromOutput(output.stdout as String);
  } on Exception catch (e) {
    throw Exception('Failed to get Flutter version from `flutter` on path: $e');
  }
}

/// Returns the Flutter version from a FVM-installed Flutter if available.
String flutterVersionFromFVMFlutter(ShorebirdProcess process) {
  try {
    final output = process.runSync('fvm', ['flutter', '--version']);
    return parseFlutterVersionFromOutput(output.stdout as String);
  } on Exception catch (e) {
    throw Exception('Failed to get Flutter version from `fvm flutter`: $e');
  }
}
