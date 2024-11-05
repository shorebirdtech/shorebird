// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_app_capabilities_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetAppCapabilitiesResponse _$GetAppCapabilitiesResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'GetAppCapabilitiesResponse',
      json,
      ($checkedConvert) {
        final val = GetAppCapabilitiesResponse(
          capabilities: $checkedConvert(
              'capabilities',
              (v) => (v as List<dynamic>)
                  .map((e) => $enumDecode(_$AppCapabilityEnumMap, e))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$GetAppCapabilitiesResponseToJson(
        GetAppCapabilitiesResponse instance) =>
    <String, dynamic>{
      'capabilities':
          instance.capabilities.map((e) => _$AppCapabilityEnumMap[e]!).toList(),
    };

const _$AppCapabilityEnumMap = {
  AppCapability.phasedPatchRollout: 'phasedPatchRollout',
};
