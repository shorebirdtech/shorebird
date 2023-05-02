import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

export 'android_internet_permission_validator.dart';
export 'shorebird_flutter_validator.dart';
export 'shorebird_version_validator.dart';

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
        return '[✗]';
      case ValidationIssueSeverity.warning:
        return '[!]';
    }
  }

  String get displayLeading {
    switch (this) {
      case ValidationIssueSeverity.error:
        return red.wrap(leading)!;
      case ValidationIssueSeverity.warning:
        return yellow.wrap(leading)!;
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
  final Future<void> Function()? fix;

  /// A console-friendly description of this issue.
  String? get displayMessage {
    final displayMessage = _addLeadingPaddingToLines(
      message,
      skipFirstLine: true,
    );
    return '${severity.displayLeading} $displayMessage';
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

  String _addLeadingPaddingToLines(String text, {bool skipFirstLine = false}) {
    final padding = ' ' * severity.leading.length;
    final lines = text.split('\n');
    final skipCount = skipFirstLine ? 1 : 0;
    return (lines.take(skipCount).toList() +
            lines.skip(skipCount).map((line) => '$padding$line').toList())
        .join('\n');
  }
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
}
