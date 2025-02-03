// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Plan _$PlanFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Plan',
      json,
      ($checkedConvert) {
        final val = Plan(
          name: $checkedConvert('name', (v) => v as String),
          currency: $checkedConvert('currency', (v) => v as String),
          basePrice: $checkedConvert('base_price', (v) => (v as num).toInt()),
          baseInstallCount:
              $checkedConvert('base_install_count', (v) => (v as num).toInt()),
          currentPeriodStart: $checkedConvert(
              'current_period_start', (v) => DateTime.parse(v as String)),
          currentPeriodEnd: $checkedConvert(
              'current_period_end', (v) => DateTime.parse(v as String)),
          cancelAtPeriodEnd:
              $checkedConvert('cancel_at_period_end', (v) => v as bool),
          isTiered: $checkedConvert('is_tiered', (v) => v as bool),
          isTrial: $checkedConvert('is_trial', (v) => v as bool),
          pricePerOverageInstall: $checkedConvert('price_per_overage_install',
              (v) => v == null ? null : Decimal.fromJson(v as String)),
          maxTeamSize:
              $checkedConvert('max_team_size', (v) => (v as num?)?.toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'basePrice': 'base_price',
        'baseInstallCount': 'base_install_count',
        'currentPeriodStart': 'current_period_start',
        'currentPeriodEnd': 'current_period_end',
        'cancelAtPeriodEnd': 'cancel_at_period_end',
        'isTiered': 'is_tiered',
        'isTrial': 'is_trial',
        'pricePerOverageInstall': 'price_per_overage_install',
        'maxTeamSize': 'max_team_size'
      },
    );

Map<String, dynamic> _$PlanToJson(Plan instance) => <String, dynamic>{
      'name': instance.name,
      'currency': instance.currency,
      'base_price': instance.basePrice,
      'base_install_count': instance.baseInstallCount,
      'price_per_overage_install': instance.pricePerOverageInstall?.toJson(),
      'current_period_start': instance.currentPeriodStart.toIso8601String(),
      'current_period_end': instance.currentPeriodEnd.toIso8601String(),
      'cancel_at_period_end': instance.cancelAtPeriodEnd,
      'is_tiered': instance.isTiered,
      'is_trial': instance.isTrial,
      'max_team_size': instance.maxTeamSize,
    };
