import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(RecordPatchInstallRequest, () {
    test('can be (de)serialized', () {
      final response = RecordPatchInstallRequest(
        clientId: 'some-client-id',
        appId: 'some-app-id',
        patchNumber: 2,
      );
      expect(
        RecordPatchInstallRequest.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
