// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetReleasePatchesResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetReleasePatchesResponse(
        patches: <ReleasePatch>[
          ReleasePatch(
            id: 0,
            number: 0,
            artifacts: <PatchArtifact>[
              PatchArtifact(
                id: 0,
                patchId: 0,
                arch: 'example',
                platform: ReleasePlatform.values.first,
                hash: 'example',
                size: 0,
                createdAt: DateTime.utc(2024),
              ),
            ],
            isRolledBack: false,
          ),
        ],
      );
      final parsed = GetReleasePatchesResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetReleasePatchesResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetReleasePatchesResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
