// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'paged_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PagedResponse _$PagedResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PagedResponse', json, ($checkedConvert) {
      final val = PagedResponse(
        data: $checkedConvert('data', (v) => v as List<dynamic>),
        hasMore: $checkedConvert('has_more', (v) => v as bool),
      );
      return val;
    }, fieldKeyMap: const {'hasMore': 'has_more'});

Map<String, dynamic> _$PagedResponseToJson(PagedResponse instance) =>
    <String, dynamic>{'data': instance.data, 'has_more': instance.hasMore};
