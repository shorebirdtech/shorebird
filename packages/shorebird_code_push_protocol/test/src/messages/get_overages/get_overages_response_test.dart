import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetOveragesResponse, () {
    test('can be (de)serialized', () {
      const response = GetOveragesResponse(patchInstallOverageLimit: 4200);
      expect(
        GetOveragesResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
