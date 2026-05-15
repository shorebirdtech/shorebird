import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleaseAnalysis, () {
    test('can be (de)serialized', () {
      const analysis = ReleaseAnalysis(
        displayName: 'My App',
        packageName: 'com.example.app',
        minSdkVersion: '24',
        targetSdkVersion: '34',
        architectures: ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(
        ReleaseAnalysis.fromJson(analysis.toJson()).toJson(),
        equals(analysis.toJson()),
      );
    });
  });
}
