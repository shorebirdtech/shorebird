// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type

part of 'artifacts_manifest.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ArtifactsManifest _$ArtifactsManifestFromJson(Map json) => $checkedCreate(
      'ArtifactsManifest',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          allowedKeys: const [
            'flutter_engine_revision',
            'storage_bucket',
            'artifact_overrides'
          ],
        );
        final val = ArtifactsManifest(
          flutterEngineRevision:
              $checkedConvert('flutter_engine_revision', (v) => v as String),
          storageBucket: $checkedConvert('storage_bucket', (v) => v as String),
          artifactOverrides: $checkedConvert('artifact_overrides',
              (v) => (v as List<dynamic>).map((e) => e as String).toSet()),
        );
        return val;
      },
      fieldKeyMap: const {
        'flutterEngineRevision': 'flutter_engine_revision',
        'storageBucket': 'storage_bucket',
        'artifactOverrides': 'artifact_overrides'
      },
    );
