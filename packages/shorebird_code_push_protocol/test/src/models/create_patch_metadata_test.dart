import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchMetadata, () {
    test('can be (de)serialized', () {
      const metadata = CreatePatchMetadata(
        releasePlatform: ReleasePlatform.android,
        usedIgnoreAssetChangesFlag: false,
        hasAssetChanges: false,
        usedIgnoreNativeChangesFlag: false,
        hasNativeChanges: false,
        linkPercentage: 99.9,
        environment: BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          xcodeVersion: '15.0',
        ),
      );
      expect(
        CreatePatchMetadata.fromJson(metadata.toJson()).toJson(),
        equals(metadata.toJson()),
      );
    });

    group('copyWith', () {
      test('creates a copy with the same fields', () {
        const metadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: false,
          hasAssetChanges: false,
          usedIgnoreNativeChangesFlag: false,
          hasNativeChanges: false,
          linkPercentage: 99.9,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );

        expect(metadata.copyWith(), equals(metadata));
      });

      test('creates a copy with the given fields replaced', () {
        const metadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: false,
          hasAssetChanges: false,
          usedIgnoreNativeChangesFlag: false,
          hasNativeChanges: false,
          linkPercentage: 99.9,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );

        final newMetadata = metadata.copyWith(
          releasePlatform: ReleasePlatform.ios,
          usedIgnoreAssetChangesFlag: true,
          hasAssetChanges: true,
          usedIgnoreNativeChangesFlag: true,
          hasNativeChanges: true,
          linkPercentage: 99.8,
          environment: const BuildEnvironmentMetadata(
            flutterRevision: 'asdf',
            operatingSystem: 'windows',
            operatingSystemVersion: '11',
            shorebirdVersion: '1.2.3',
            xcodeVersion: '14.0',
          ),
        );

        expect(
          newMetadata,
          equals(
            const CreatePatchMetadata(
              releasePlatform: ReleasePlatform.ios,
              usedIgnoreAssetChangesFlag: true,
              hasAssetChanges: true,
              usedIgnoreNativeChangesFlag: true,
              hasNativeChanges: true,
              linkPercentage: 99.8,
              environment: BuildEnvironmentMetadata(
                flutterRevision: 'asdf',
                operatingSystem: 'windows',
                operatingSystemVersion: '11',
                shorebirdVersion: '1.2.3',
                xcodeVersion: '14.0',
              ),
            ),
          ),
        );
      });
    });

    group('equatable', () {
      test('two metadatas with the same properties are equal', () {
        const metadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: false,
          hasAssetChanges: false,
          usedIgnoreNativeChangesFlag: false,
          hasNativeChanges: false,
          linkPercentage: 99.9,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );
        const otherMetadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: false,
          hasAssetChanges: false,
          usedIgnoreNativeChangesFlag: false,
          hasNativeChanges: false,
          linkPercentage: 99.9,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );
        expect(metadata, equals(otherMetadata));
      });

      test('two metadatas with different properties are not equal', () {
        const metadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: false,
          hasAssetChanges: false,
          usedIgnoreNativeChangesFlag: false,
          hasNativeChanges: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '1.2.3',
            shorebirdVersion: '4.5.6',
            xcodeVersion: '15.0',
          ),
        );
        const otherMetadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.ios,
          usedIgnoreAssetChangesFlag: false,
          hasAssetChanges: false,
          usedIgnoreNativeChangesFlag: false,
          hasNativeChanges: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
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
