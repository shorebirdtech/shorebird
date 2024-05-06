// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type, unnecessary_lambdas

part of 'nserror.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NSError _$NSErrorFromJson(Map<String, dynamic> json) => $checkedCreate(
      'NSError',
      json,
      ($checkedConvert) {
        final val = NSError(
          code: $checkedConvert('code', (v) => (v as num).toInt()),
          domain: $checkedConvert('domain', (v) => v as String),
          userInfo: $checkedConvert(
              'userInfo', (v) => UserInfo.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

UserInfo _$UserInfoFromJson(Map<String, dynamic> json) => $checkedCreate(
      'UserInfo',
      json,
      ($checkedConvert) {
        final val = UserInfo(
          localizedDescription: $checkedConvert(
              'NSLocalizedDescription',
              (v) => v == null
                  ? null
                  : StringContainer.fromJson(v as Map<String, dynamic>)),
          localizedFailureReason: $checkedConvert(
              'NSLocalizedFailureReason',
              (v) => v == null
                  ? null
                  : StringContainer.fromJson(v as Map<String, dynamic>)),
          underlyingError: $checkedConvert(
              'NSUnderlyingError',
              (v) => v == null
                  ? null
                  : NSUnderlyingError.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {
        'localizedDescription': 'NSLocalizedDescription',
        'localizedFailureReason': 'NSLocalizedFailureReason',
        'underlyingError': 'NSUnderlyingError'
      },
    );

StringContainer _$StringContainerFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'StringContainer',
      json,
      ($checkedConvert) {
        final val = StringContainer(
          string: $checkedConvert('string', (v) => v as String),
        );
        return val;
      },
    );

NSUnderlyingError _$NSUnderlyingErrorFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'NSUnderlyingError',
      json,
      ($checkedConvert) {
        final val = NSUnderlyingError(
          error: $checkedConvert(
              'error',
              (v) => v == null
                  ? null
                  : NSError.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );
