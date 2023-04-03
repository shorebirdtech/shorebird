import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';

/// Severity level of a [ValidationIssue].
///
/// [error]s should be fixed before continuing development.
/// [warning]s should be fixed before releasing your app, but are not as urgent.
enum ValidationIssueSeverity {
  error,
  warning,
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
  const ValidationIssue({required this.severity, required this.message});

  /// How important it is to fix this issue.
  final ValidationIssueSeverity severity;

  /// A description of the issue.
  final String message;

  /// A console-friendly description of this issue.
  String? get displayMessage {
    return '${severity.leading} $message';
  }

  @override
  String toString() => '$severity $message';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ValidationIssue &&
        other.severity == severity &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hashAll([severity, message]);
}

/// Checks for a specific issue with either the Shorebird installation or the
/// current Shorebird project.
abstract class DoctorValidator {
  /// A one-sentence explanation of what this validator is checking.
  String get description;

  /// Checks for [ValidationIssue]s.
  ///
  /// Returns an empty list if no issues are found.
  Future<List<ValidationIssue>> validate();
}
