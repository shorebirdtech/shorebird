import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetAppCapabilitiesResponse, () {
    test('can be (de)serialized', () {
      final response = GetAppCapabilitiesResponse(capabilities: [
        AppCapability.phasedPatchRollout,
      ]);
      expect(
        GetAppCapabilitiesResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
