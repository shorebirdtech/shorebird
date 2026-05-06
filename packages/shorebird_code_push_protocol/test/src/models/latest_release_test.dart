import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(LatestRelease, () {
    test('can be (de)serialized', () {
      final latest = LatestRelease(
        id: 535,
        version: '1.2.3+5',
        flutterRevision: 'abc123',
        flutterVersion: '3.27.0',
        createdAt: DateTime(2023, 3),
        updatedAt: DateTime(2023, 4),
        status: ReleaseStatus.active,
        notes: 'launch notes',
        analysis: const ReleaseAnalysis(
          displayName: 'My App',
          packageName: 'com.example.app',
          iconBase64: 'data:image/png;base64,AAA',
          minSdkVersion: '24',
          targetSdkVersion: '34',
          architectures: ['arm64-v8a'],
        ),
      );
      expect(
        LatestRelease.fromJson(latest.toJson()).toJson(),
        equals(latest.toJson()),
      );
    });

    test('is equatable', () {
      const analysis = ReleaseAnalysis(
        displayName: 'My App',
        packageName: 'com.example.app',
        minSdkVersion: '24',
        targetSdkVersion: '34',
        architectures: ['arm64-v8a'],
      );
      final latest1 = LatestRelease(
        id: 535,
        version: '1.2.3+5',
        flutterRevision: 'abc123',
        createdAt: DateTime(2023, 3),
        updatedAt: DateTime(2023, 4),
        status: ReleaseStatus.active,
        analysis: analysis,
      );
      final latest1Copy = LatestRelease(
        id: 535,
        version: '1.2.3+5',
        flutterRevision: 'abc123',
        createdAt: DateTime(2023, 3),
        updatedAt: DateTime(2023, 4),
        status: ReleaseStatus.active,
        analysis: analysis,
      );
      final latest2 = LatestRelease(
        id: 600,
        version: '1.2.4+6',
        flutterRevision: 'abc123',
        createdAt: DateTime(2023, 3),
        updatedAt: DateTime(2023, 4),
        status: ReleaseStatus.active,
        analysis: analysis,
      );

      expect(latest1, equals(latest1Copy));
      expect(latest1, isNot(equals(latest2)));
    });
  });
}
