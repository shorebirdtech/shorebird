import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(UpdateReleaseMetadata, () {
    test('can be (de)serialized', () {
      const metadata = UpdateReleaseMetadata(
        releasePlatform: ReleasePlatform.android,
        flutterVersionOverride: '1.2.3',
        generatedApks: false,
        includesPublicKey: false,
        environment: BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: false,
          xcodeVersion: '15.0',
        ),
      );
      expect(
        UpdateReleaseMetadata.fromJson(metadata.toJson()).toJson(),
        equals(metadata.toJson()),
      );
    });

    group('copyWith', () {
      test('creates a copy with the same fields', () {
        const metadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.3',
          generatedApks: false,
          includesPublicKey: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
            usesShorebirdCodePushPackage: false,
            xcodeVersion: '15.0',
          ),
        );

        expect(metadata.copyWith(), equals(metadata));
      });

      test('creates a copy with the given fields replaced', () {
        const metadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.3',
          includesPublicKey: false,
          generatedApks: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
            usesShorebirdCodePushPackage: false,
            xcodeVersion: '15.0',
          ),
        );

        final newMetadata = metadata.copyWith(
          releasePlatform: ReleasePlatform.ios,
          flutterVersionOverride: '1.2.4',
          generatedApks: true,
          includesPublicKey: true,
          environment: const BuildEnvironmentMetadata(
            flutterRevision: 'asdf',
            operatingSystem: 'windows',
            operatingSystemVersion: '11',
            shorebirdVersion: '1.2.3',
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
            usesShorebirdCodePushPackage: true,
            xcodeVersion: '14.0',
          ),
        );

        expect(
          newMetadata,
          equals(
            const UpdateReleaseMetadata(
              releasePlatform: ReleasePlatform.ios,
              flutterVersionOverride: '1.2.4',
              generatedApks: true,
              includesPublicKey: true,
              environment: BuildEnvironmentMetadata(
                flutterRevision: 'asdf',
                operatingSystem: 'windows',
                operatingSystemVersion: '11',
                shorebirdVersion: '1.2.3',
                shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                usesShorebirdCodePushPackage: true,
                xcodeVersion: '14.0',
              ),
            ),
          ),
        );
      });
    });

    group('equatable', () {
      test('two metadatas with the same properties are equal', () {
        const metadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.3',
          generatedApks: false,
          includesPublicKey: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
            usesShorebirdCodePushPackage: false,
            xcodeVersion: '15.0',
          ),
        );
        const otherMetadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.3',
          generatedApks: false,
          includesPublicKey: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
            usesShorebirdCodePushPackage: false,
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
          includesPublicKey: true,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
            usesShorebirdCodePushPackage: true,
            xcodeVersion: '15.0',
          ),
        );
        const otherMetadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.android,
          flutterVersionOverride: '1.2.4',
          generatedApks: false,
          includesPublicKey: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
            usesShorebirdCodePushPackage: true,
            xcodeVersion: '15.0',
          ),
        );
        expect(metadata, isNot(equals(otherMetadata)));
      });
    });
  });
}
