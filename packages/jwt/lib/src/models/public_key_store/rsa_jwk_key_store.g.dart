// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, document_ignores

part of 'rsa_jwk_key_store.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RsaJwkKeyStore _$RsaJwkKeyStoreFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RsaJwkKeyStore', json, ($checkedConvert) {
      final val = RsaJwkKeyStore(
        keys: $checkedConvert(
          'keys',
          (v) => (v as List<dynamic>)
              .map((e) => RsaJwk.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });
