import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchInstallRequest, () {
    test('can be (de)serialized', () {
      final response = CreatePatchInstallRequest(
        clientId: 'some-client-id',
      );
      expect(
        CreatePaymentLinkResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
