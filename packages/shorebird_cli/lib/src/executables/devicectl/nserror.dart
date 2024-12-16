// ignore_for_file: public_member_api_docs

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

part 'nserror.g.dart';

/// {@template nserror}
/// A pared-down representation of the NSError class.
///
/// See https://developer.apple.com/documentation/foundation/nserror.
/// {@endtemplate}
@JsonSerializable(fieldRename: FieldRename.none)
class NSError extends Equatable {
  /// {@macro nserror}
  const NSError({
    required this.code,
    required this.domain,
    required this.userInfo,
  });

  final int code;
  final String domain;
  final UserInfo userInfo;

  /// Creates an [NSError] from JSON.
  static NSError fromJson(Json json) => _$NSErrorFromJson(json);

  Json toJson() => _$NSErrorToJson(this);

  @override
  String toString() => '''
NSError(
  code: $code,
  domain: $domain,
  userInfo: $userInfo
)''';

  @override
  List<Object> get props => [
        code,
        domain,
        userInfo,
      ];
}

@JsonSerializable(fieldRename: FieldRename.none)
class UserInfo extends Equatable {
  const UserInfo({
    this.description,
    this.localizedDescription,
    this.localizedFailureReason,
    this.underlyingError,
  });

  @JsonKey(name: 'NSDescription')
  final StringContainer? description;

  @JsonKey(name: 'NSLocalizedDescription')
  final StringContainer? localizedDescription;

  @JsonKey(name: 'NSLocalizedFailureReason')
  final StringContainer? localizedFailureReason;

  @JsonKey(name: 'NSUnderlyingError')
  final NSUnderlyingError? underlyingError;

  static const nullInfo = UserInfo();

  static UserInfo fromJson(Json json) => _$UserInfoFromJson(json);

  Json toJson() => _$UserInfoToJson(this);

  @override
  String toString() => '''
UserInfo(
  description: $description,
  localizedDescription: $localizedDescription,
  localizedFailureReason: $localizedFailureReason,
  underlyingError: $underlyingError
)''';

  @override
  List<Object?> get props => [
        description,
        localizedDescription,
        localizedFailureReason,
        underlyingError,
      ];
}

@JsonSerializable(fieldRename: FieldRename.none)
class StringContainer extends Equatable {
  const StringContainer(this.string);

  final String string;

  static StringContainer fromJson(Json json) => _$StringContainerFromJson(json);

  Json toJson() => _$StringContainerToJson(this);

  @override
  String toString() => string;

  @override
  List<Object> get props => [string];
}

@JsonSerializable(fieldRename: FieldRename.none)
class NSUnderlyingError extends Equatable {
  const NSUnderlyingError({required this.error});

  final NSError? error;

  static NSUnderlyingError fromJson(Json json) =>
      _$NSUnderlyingErrorFromJson(json);

  Json toJson() => _$NSUnderlyingErrorToJson(this);

  @override
  String toString() => '''
NSUnderlyingError(
  $error
)''';

  @override
  List<Object?> get props => [error];
}
