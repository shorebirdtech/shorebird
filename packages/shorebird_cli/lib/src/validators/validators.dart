import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

export 'android_internet_permission_validator.dart';
export 'shorebird_flutter_validator.dart';
export 'shorebird_version_validator.dart';

/// Severity level of a [ValidationIssue].
///
/// [error]s will prevent code push from working and block releases, builds,
///   patches, etc.
/// [warning]s should be fixed before releasing your app, but are not as urgent.
enum ValidationIssueSeverity {
  error,
  warning,
}

/// The level at which validation is being performed.
enum ValidatorScope {
  project,
  installation,
}

/// Display helpers for printing [ValidationIssue]s.
extension Display on ValidationIssueSeverity {
  String get leading {
    switch (this) {
      case ValidationIssueSeverity.error:
        return red.wrap('[✗]')!;
      case ValidationIssueSeverity.warning:
        return yellow.wrap('[!]')!;
    }
  }
}

/// A (potential) problem with the current Shorebird installation or project.
@immutable
class ValidationIssue {
  const ValidationIssue({
    required this.severity,
    required this.message,
    this.fix,
  });

  /// How important it is to fix this issue.
  final ValidationIssueSeverity severity;

  /// A description of the issue.
  final String message;

  /// Fixes this issue.
  final FutureOr<void> Function()? fix;

  /// A console-friendly description of this issue.
  String? get displayMessage {
    return '${severity.leading} $message';
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
  /// A unique identifer for this class.
  String get id => '$runtimeType';

  /// A one-sentence explanation of what this validator is checking.
  String get description;

  /// Checks for [ValidationIssue]s.
  ///
  /// Returns an empty list if no issues are found.
  /// Not all validators use [process].
  Future<List<ValidationIssue>> validate(ShorebirdProcess process);

  /// Whether this validator is project-specific or system-wide.
  ValidatorScope get scope;
}
