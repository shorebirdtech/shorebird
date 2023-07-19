import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(UpdateOveragesRequest, () {
    test('can be (de)serialized', () {
      const response = UpdateOveragesRequest(patchInstallOverageLimit: 4200);
      expect(
        UpdateOveragesRequest.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
