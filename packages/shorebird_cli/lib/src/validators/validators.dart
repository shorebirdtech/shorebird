import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

export 'android_internet_permission_validator.dart';
export 'flavor_validator.dart';
export 'macos_network_entitlement_validator.dart';
export 'shorebird_version_validator.dart';
export 'shorebird_yaml_asset_validator.dart';
export 'tracked_lock_files_validator.dart';
export 'xcodeproj_flutter_root_validator.dart';

/// Severity level of a [ValidationIssue].
enum ValidationIssueSeverity {
  /// [error]s will prevent code push from working and block releases, builds,
  /// patches, etc.
  error,

  /// [warning]s should be fixed before releasing your app, but are not as
  /// urgent.
  warning,
}

/// Display helpers for printing [ValidationIssue]s.
extension Display on ValidationIssueSeverity {
  /// The raw string representation of this severity.
  String get rawLeading {
    switch (this) {
      case ValidationIssueSeverity.error:
        return '[✗]';
      case ValidationIssueSeverity.warning:
        return '[!]';
    }
  }

  /// The colorized string representation of this severity.
  String get displayLeading {
    switch (this) {
      case ValidationIssueSeverity.error:
        return red.wrap(rawLeading)!;
      case ValidationIssueSeverity.warning:
        return yellow.wrap(rawLeading)!;
    }
  }
}

/// A (potential) problem with the current Shorebird installation or project.
@immutable
class ValidationIssue {
  /// Creates a new [ValidationIssue].
  const ValidationIssue({
    required this.severity,
    required this.message,
    this.fix,
  });

  /// Creates a new [ValidationIssue] with a severity of
  /// [ValidationIssueSeverity.error].
  factory ValidationIssue.error({required String message}) => ValidationIssue(
    severity: ValidationIssueSeverity.error,
    message: message,
  );

  /// Creates a new [ValidationIssue] with a severity of
  /// [ValidationIssueSeverity.warning].
  factory ValidationIssue.warning({required String message}) => ValidationIssue(
    severity: ValidationIssueSeverity.warning,
    message: message,
  );

  /// How important it is to fix this issue.
  final ValidationIssueSeverity severity;

  /// A description of the issue.
  final String message;

  /// Fixes this issue.
  final FutureOr<void> Function()? fix;

  /// A console-friendly description of this issue.
  String? get displayMessage {
    return '${severity.displayLeading} $message';
  }

  // coverage:ignore-start
  @override
  String toString() => '$severity $message';
  // coverage:ignore-end

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ValidationIssue &&
        other.severity == severity &&
        other.message == message;
  }

  // coverage:ignore-start
  @override
  int get hashCode => Object.hashAll([severity, message]);
  // coverage:ignore-end
}

/// Checks for a specific issue with either the Shorebird installation or the
/// current Shorebird project.
abstract class Validator {
  /// A one-sentence explanation of what this validator is checking.
  String get description;

  /// Checks for [ValidationIssue]s.
  ///
  /// Returns an empty list if no issues are found.
  /// Not all validators use [process].
  Future<List<ValidationIssue>> validate();

  /// Whether it makes sense to run the validator in the current working
  /// directory.
  bool canRunInCurrentContext() => true;

  /// User-facing message explaining why [canRunInCurrentContext] is false.
  String? get incorrectContextMessage => null;
}
