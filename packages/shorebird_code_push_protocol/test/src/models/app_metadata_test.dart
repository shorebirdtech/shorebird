import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(AppMetadata, () {
    test('can be (de)serialized', () {
      final appMetadata = AppMetadata(
        appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
        displayName: 'My App',
        latestReleaseVersion: '1.0.0',
        latestPatchNumber: 1,
        createdAt: DateTime(2022),
        updatedAt: DateTime(2023),
      );
      expect(
        AppMetadata.fromJson(appMetadata.toJson()).toJson(),
        equals(appMetadata.toJson()),
      );
    });
  });
}
