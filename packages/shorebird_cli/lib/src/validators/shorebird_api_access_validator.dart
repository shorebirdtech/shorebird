import 'dart:io';

import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Verifies that the user has access to api.shorebird.dev.
class ShorebirdApiAccessValidator extends Validator {
  @override
  String get description => 'Has access to api.shorebird.dev';

  @override
  Future<List<ValidationIssue>> validate() async {
    final uri = Uri.parse('https://api.shorebird.dev');
    final result = await httpClient.get(uri);
    if (result.statusCode != HttpStatus.ok) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Unable to access api.shorebird.dev',
        ),
      ];
    }
    return [];
  }
}
