// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'shorebird_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ShorebirdPlan _$ShorebirdPlanFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ShorebirdPlan',
      json,
      ($checkedConvert) {
        final val = ShorebirdPlan(
          name: $checkedConvert('name', (v) => v as String),
          monthlyCost: $checkedConvert(
              'monthly_cost', (v) => const MoneyConverter().fromJson(v as int)),
          patchInstallLimit:
              $checkedConvert('patch_install_limit', (v) => v as int?),
          maxTeamSize: $checkedConvert('max_team_size', (v) => v as int?),
        );
        return val;
      },
      fieldKeyMap: const {
        'monthlyCost': 'monthly_cost',
        'patchInstallLimit': 'patch_install_limit',
        'maxTeamSize': 'max_team_size'
      },
    );

Map<String, dynamic> _$ShorebirdPlanToJson(ShorebirdPlan instance) =>
    <String, dynamic>{
      'name': instance.name,
      'monthly_cost': const MoneyConverter().toJson(instance.monthlyCost),
      'patch_install_limit': instance.patchInstallLimit,
      'max_team_size': instance.maxTeamSize,
    };
