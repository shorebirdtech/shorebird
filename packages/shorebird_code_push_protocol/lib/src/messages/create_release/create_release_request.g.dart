// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_release_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateReleaseRequest _$CreateReleaseRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateReleaseRequest',
      json,
      ($checkedConvert) {
        final val = CreateReleaseRequest(
          version: $checkedConvert('version', (v) => v as String),
          flutterRevision:
              $checkedConvert('flutter_revision', (v) => v as String),
          displayName: $checkedConvert('display_name', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'flutterRevision': 'flutter_revision',
        'displayName': 'display_name'
      },
    );

Map<String, dynamic> _$CreateReleaseRequestToJson(
        CreateReleaseRequest instance) =>
    <String, dynamic>{
      'version': instance.version,
      'flutter_revision': instance.flutterRevision,
      'display_name': instance.displayName,
    };
