// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'collaborator.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Collaborator _$CollaboratorFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'Collaborator',
      json,
      ($checkedConvert) {
        final val = Collaborator(
          userId: $checkedConvert('user_id', (v) => v as int),
          email: $checkedConvert('email', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'userId': 'user_id'},
    );

Map<String, dynamic> _$CollaboratorToJson(Collaborator instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
      'email': instance.email,
    };
