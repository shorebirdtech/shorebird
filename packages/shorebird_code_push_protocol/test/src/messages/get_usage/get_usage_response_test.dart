import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetUsageResponse, () {
    test('can be (de)serialized', () {
      const response = GetUsageResponse(
        apps: [
          AppUsage(
            id: 'app-id',
            platforms: [
              PlatformUsage(
                name: 'android',
                arches: [
                  ArchUsage(
                    name: 'arm64',
                    patches: [PatchUsage(id: 1, installCount: 42)],
                  ),
                ],
              )
            ],
          ),
        ],
      );
      expect(
        GetUsageResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
