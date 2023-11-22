import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

class StorageAccessValidator extends Validator {
  @override
  String get description => 'Has access to storage.googleapis.com';

  @override
  Future<List<ValidationIssue>> validate() async {
    final testFileUrl = Uri.parse(
      'https://storage.googleapis.com/shorebird_doctor/hello',
    );
    final result = await httpClient.get(testFileUrl);
    if (result.statusCode != HttpStatus.ok || result.body != 'hello') {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Unable to access storage.googleapis.com',
        ),
      ];
    }
    return [];
  }
}
