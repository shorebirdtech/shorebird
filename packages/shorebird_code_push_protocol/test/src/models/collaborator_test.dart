import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(Collaborator, () {
    test('can be (de)serialized', () {
      const collaborator = Collaborator(
        userId: 1,
        email: 'jane.doe@shorebird.dev',
        role: CollaboratorRole.admin,
      );
      expect(
        Collaborator.fromJson(collaborator.toJson()).toJson(),
        equals(collaborator.toJson()),
      );
    });
  });
}
