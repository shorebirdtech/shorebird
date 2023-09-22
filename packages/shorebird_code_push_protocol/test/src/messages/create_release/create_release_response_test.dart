import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateReleaseResponse, () {
    test('can be (de)serialized', () {
      final response = CreateReleaseResponse(
        release: Release(
          id: 0,
          appId: 'test-app-id',
          version: '1.0.0',
          displayName: 'v1.0.0',
          flutterRevision: 'flutter-revision',
          platformStatuses: {},
          createdAt: DateTime(2023),
          updatedAt: DateTime(2023),
        ),
      );
      expect(
        CreateReleaseResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
