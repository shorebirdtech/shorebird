import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:shorebird_code_push_protocol/src/models/build_environment_metadata.dart';
import 'package:test/test.dart';

void main() {
  group(BuildEnvironmentMetadata, () {
    test('can be (de)serialized', () {
      const metadata = BuildEnvironmentMetadata(
        operatingSystem: 'macos',
        operatingSystemVersion: '1.2.3',
        shorebirdVersion: '4.5.6',
        xcodeVersion: '15.0',
      );
      expect(
        BuildEnvironmentMetadata.fromJson(metadata.toJson()).toJson(),
        equals(metadata.toJson()),
      );
    });

    group('equatable', () {
      test('two metadatas with the same properties are equal', () {
        const metadata = BuildEnvironmentMetadata(
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          xcodeVersion: '15.0',
        );
        const otherMetadata = BuildEnvironmentMetadata(
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          xcodeVersion: '15.0',
        );
        expect(metadata, equals(otherMetadata));
      });

      test('two metadatas with different properties are not equal', () {
        const metadata = BuildEnvironmentMetadata(
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          xcodeVersion: '15.0',
        );
        const otherMetadata = BuildEnvironmentMetadata(
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          xcodeVersion: '15.1',
        );
        expect(metadata, isNot(equals(otherMetadata)));
      });
    });
  });
}
