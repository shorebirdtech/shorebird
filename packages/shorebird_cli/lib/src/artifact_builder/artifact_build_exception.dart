import 'dart:convert';

import 'package:shorebird_cli/src/shorebird_process.dart';

const String _missingKeystoreFixSuggestion =
    'This error is likely due to a missing keystore file. You can read about Android app signing here: https://developer.android.com/studio/publish/app-signing.';

/// {@template artifact_build_exception}
/// Thrown when a build fails.
/// {@endtemplate}
class ArtifactBuildException implements Exception {
  /// {@macro artifact_build_exception}
  ArtifactBuildException(
    this.message, {
    List<String>? stdout,
    List<String>? stderr,
    String? fixRecommendation,
  })  : stdout = stdout ?? [],
        stderr = stderr ?? [] {
    flutterError =
        _errorMessageFromOutput(this.stdout + this.stderr).join('\n');
    this.fixRecommendation = fixRecommendation ??
        _recommendationFromOutput(this.stdout + this.stderr);
  }

  /// {@macro artifact_build_exception}
  factory ArtifactBuildException.fromProcessResult(
    String message, {
    required ShorebirdProcessResult buildProcessResult,
    String? fixRecommendation,
  }) {
    return ArtifactBuildException(
      message,
      stdout: const LineSplitter().convert('${buildProcessResult.stdout}'),
      stderr: const LineSplitter().convert('${buildProcessResult.stderr}'),
      fixRecommendation: fixRecommendation,
    );
  }

  /// Information about the build failure.
  late final String message;

  /// The stdout output from the build process, split into lines.
  final List<String> stdout;

  /// The stderr output from the build process, split into lines.
  final List<String> stderr;

  /// The relevant error message (if we can find one) from the Flutter build
  /// output.
  late final String? flutterError;

  /// An optional tip to help the user fix the build failure.
  late final String? fixRecommendation;

  List<String> _errorMessageFromOutput(List<String> output) {
    final failureHeader =
        RegExp(r'.*FAILURE: Build failed with an exception\..*');
    // This precedes a stack trace
    final failureFooter1 = RegExp(r'.*\* Exception is:.*');

    // This precedes recommendations that are not applicable to us (e.g., "Get
    // more help at https://help.gradle.org.")
    final failureFooter2 = RegExp(r'.*\* Try:.*');

    String trimLine(String line) {
      return line.trim().replaceAll(RegExp(r'^\[.*\]'), '');
    }

    var inErrorOutput = false;
    final ret = <String>[];
    for (final line in output) {
      if (failureHeader.hasMatch(line)) {
        inErrorOutput = true;
      } else if (failureFooter1.hasMatch(line) ||
          failureFooter2.hasMatch(line)) {
        inErrorOutput = false;
      }

      if (inErrorOutput) {
        ret.add(trimLine(line));
      }
    }

    return ret;
  }

  final _regexpToRecommendations = {
    (
      [RegExp("Execution failed for task ':app:signReleaseBundle'")],
      _missingKeystoreFixSuggestion,
    ),
  };

  String? _recommendationFromOutput(List<String> output) {
    for (final entry in _regexpToRecommendations) {
      final regexpes = entry.$1;
      for (final regexp in regexpes) {
        if (output.any(regexp.hasMatch)) {
          return entry.$2;
        }
      }
    }

    return null;
  }
}
