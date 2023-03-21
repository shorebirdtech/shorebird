// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'error_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorResponse _$ErrorResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ErrorResponse',
      json,
      ($checkedConvert) {
        final val = ErrorResponse(
          code: $checkedConvert('code', (v) => v as String),
          message: $checkedConvert('message', (v) => v as String),
          details: $checkedConvert('details', (v) => v as String?),
        );
        return val;
      },
    );
