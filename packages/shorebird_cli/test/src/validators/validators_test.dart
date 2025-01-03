import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

void main() {
  group(ValidationIssue, () {
    test('has an error factory constructor', () {
      final issue = ValidationIssue.error(message: 'error message');
      expect(issue.severity, ValidationIssueSeverity.error);
      expect(issue.message, 'error message');
    });

    test('has a warning factory constructor', () {
      final issue = ValidationIssue.warning(message: 'warning message');
      expect(issue.severity, ValidationIssueSeverity.warning);
      expect(issue.message, 'warning message');
    });
  });
}
