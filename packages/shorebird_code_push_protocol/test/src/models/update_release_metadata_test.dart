import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(UpdateReleaseMetadata, () {
    test('can be (de)serialized', () {
      const metadata = UpdateReleaseMetadata(
        releasePlatform: ReleasePlatform.android,
        flutterVersionOverride: '1.2.3',
        generatedApks: false,
        environment: BuildEnvironmentMetadata(
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          xcodeVersion: '15.0',
        ),
      );
      expect(
        UpdateReleaseMetadata.fromJson(metadata.toJson()).toJson(),
        equals(metadata.toJson()),
      );
    });

    group('equatable', () {
      test('two metadatas with the same properties are equal', () {
        const metadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.3',
          generatedApks: false,
          environment: BuildEnvironmentMetadata(
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );
        const otherMetadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.3',
          generatedApks: false,
          environment: BuildEnvironmentMetadata(
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );
        expect(metadata, equals(otherMetadata));
      });

      test('two metadatas with different properties are not equal', () {
        const metadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.3',
          generatedApks: false,
          environment: BuildEnvironmentMetadata(
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );
        const otherMetadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.4',
          generatedApks: false,
          environment: BuildEnvironmentMetadata(
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );
        expect(metadata, isNot(equals(otherMetadata)));
      });
    });
  });
}
