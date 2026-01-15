import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:test/test.dart';

void main() {
  group(BuildEnvironmentMetadata, () {
    test('can be (de)serialized', () {
      const metadata = BuildEnvironmentMetadata(
        flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
        operatingSystem: 'macos',
        operatingSystemVersion: '1.2.3',
        shorebirdVersion: '4.5.6',
        shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
        usesShorebirdCodePushPackage: false,
        xcodeVersion: '15.0',
        projectGitHash: 'abc123def456',
      );
      expect(
        BuildEnvironmentMetadata.fromJson(metadata.toJson()).toJson(),
        equals(metadata.toJson()),
      );
    });

    test('can be (de)serialized without projectGitHash', () {
      const metadata = BuildEnvironmentMetadata(
        flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
        operatingSystem: 'macos',
        operatingSystemVersion: '1.2.3',
        shorebirdVersion: '4.5.6',
        shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
        usesShorebirdCodePushPackage: false,
        xcodeVersion: '15.0',
      );
      expect(
        BuildEnvironmentMetadata.fromJson(metadata.toJson()).toJson(),
        equals(metadata.toJson()),
      );
    });

    group('copyWith', () {
      test('creates a copy with the same fields', () {
        const metadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: false,
          xcodeVersion: '15.0',
          projectGitHash: 'abc123',
        );

        expect(metadata.copyWith(), equals(metadata));
      });

      test('returns a new instance with the given fields replaced', () {
        const metadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: false,
          xcodeVersion: '15.0',
          projectGitHash: 'abc123',
        );
        final newMetadata = metadata.copyWith(
          flutterRevision: 'asdf',
          operatingSystem: 'windows',
          operatingSystemVersion: '11',
          shorebirdVersion: '1.2.3',
          shorebirdYaml: const ShorebirdYaml(appId: 'app-id2'),
          usesShorebirdCodePushPackage: true,
          xcodeVersion: '14.0',
          projectGitHash: 'def456',
        );
        expect(
          newMetadata,
          equals(
            const BuildEnvironmentMetadata(
              flutterRevision: 'asdf',
              operatingSystem: 'windows',
              operatingSystemVersion: '11',
              shorebirdVersion: '1.2.3',
              shorebirdYaml: ShorebirdYaml(appId: 'app-id2'),
              usesShorebirdCodePushPackage: true,
              xcodeVersion: '14.0',
              projectGitHash: 'def456',
            ),
          ),
        );
      });
    });

    group('equatable', () {
      test('two metadatas with the same properties are equal', () {
        const metadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: true,
          xcodeVersion: '15.0',
          projectGitHash: 'abc123',
        );
        const otherMetadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: true,
          xcodeVersion: '15.0',
          projectGitHash: 'abc123',
        );
        expect(metadata, equals(otherMetadata));
      });

      test('two metadatas with different properties are not equal', () {
        const metadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: true,
          xcodeVersion: '15.0',
          projectGitHash: 'abc123',
        );
        const otherMetadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id2'),
          usesShorebirdCodePushPackage: true,
          xcodeVersion: '15.1',
          projectGitHash: 'def456',
        );
        expect(metadata, isNot(equals(otherMetadata)));
      });

      test('two metadatas with different projectGitHash are not equal', () {
        const metadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: true,
          xcodeVersion: '15.0',
          projectGitHash: 'abc123',
        );
        const otherMetadata = BuildEnvironmentMetadata(
          flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
          operatingSystem: 'macos',
          operatingSystemVersion: '1.2.3',
          shorebirdVersion: '4.5.6',
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: true,
          xcodeVersion: '15.0',
          projectGitHash: 'def456',
        );
        expect(metadata, isNot(equals(otherMetadata)));
      });
    });
  });
}
