import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateAppCollaboratorRequest, () {
    test('can be (de)serialized', () {
      const request = CreateAppCollaboratorRequest(userId: 42);
      expect(
        CreateAppCollaboratorRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
