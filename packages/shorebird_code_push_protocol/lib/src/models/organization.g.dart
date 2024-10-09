// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'organization.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Organization _$OrganizationFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'Organization',
      json,
      ($checkedConvert) {
        final val = Organization(
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          name: $checkedConvert('name', (v) => v as String),
          organizationType: $checkedConvert('organization_type',
              (v) => $enumDecode(_$OrganizationTypeEnumMap, v)),
          stripeCustomerId:
              $checkedConvert('stripe_customer_id', (v) => v as String?),
          createdAt:
              $checkedConvert('created_at', (v) => DateTime.parse(v as String)),
          updatedAt:
              $checkedConvert('updated_at', (v) => DateTime.parse(v as String)),
          patchOverageLimit: $checkedConvert(
              'patch_overage_limit', (v) => (v as num?)?.toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'organizationType': 'organization_type',
        'stripeCustomerId': 'stripe_customer_id',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'patchOverageLimit': 'patch_overage_limit'
      },
    );

Map<String, dynamic> _$OrganizationToJson(Organization instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'organization_type':
          _$OrganizationTypeEnumMap[instance.organizationType]!,
      'stripe_customer_id': instance.stripeCustomerId,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'patch_overage_limit': instance.patchOverageLimit,
    };

const _$OrganizationTypeEnumMap = {
  OrganizationType.personal: 'personal',
  OrganizationType.team: 'team',
};
