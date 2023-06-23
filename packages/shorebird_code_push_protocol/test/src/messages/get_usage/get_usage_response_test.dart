import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetUsageResponse, () {
    test('can be (de)serialized', () {
      final response = GetUsageResponse(
        apps: [
          const AppUsage(id: 'app-id', name: 'My app', patchInstallCount: 1337),
        ],
        patchInstallLimit: 42,
        currentPeriodStart: DateTime(2021),
        currentPeriodEnd: DateTime(2021, 1, 2),
      );
      expect(
        GetUsageResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
