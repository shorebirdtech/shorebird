import 'package:shorebird_code_push_protocol/src/messages/messages.dart';
import 'package:test/test.dart';

void main() {
  group(DeleteReleaseRequest, () {
    test('can be (de)serialized', () {
      const request = DeleteReleaseRequest(appId: 'myApp', version: '1.0.0');
      expect(
        DeleteReleaseRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
