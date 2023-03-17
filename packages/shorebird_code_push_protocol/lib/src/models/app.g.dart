// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'app.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

App _$AppFromJson(Map<String, dynamic> json) => $checkedCreate(
      'App',
      json,
      ($checkedConvert) {
        final val = App(
          appId: $checkedConvert('app_id', (v) => v as String),
          latestReleaseVersion:
              $checkedConvert('latest_release_version', (v) => v as String?),
          latestPatchNumber:
              $checkedConvert('latest_patch_number', (v) => v as int?),
        );
        return val;
      },
      fieldKeyMap: const {
        'appId': 'app_id',
        'latestReleaseVersion': 'latest_release_version',
        'latestPatchNumber': 'latest_patch_number'
      },
    );

Map<String, dynamic> _$AppToJson(App instance) => <String, dynamic>{
      'app_id': instance.appId,
      'latest_release_version': instance.latestReleaseVersion,
      'latest_patch_number': instance.latestPatchNumber,
    };
