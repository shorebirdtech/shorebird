import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateAppRequest, () {
    test('can be (de)serialized', () {
      const request = CreateAppRequest(displayName: 'display_name');
      expect(
        CreateAppRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
