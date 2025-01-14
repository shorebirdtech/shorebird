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

  /// The error code.
  final int code;

  /// The error domain.
  final String domain;

  /// Additional information about the error.
  final UserInfo userInfo;

  /// Creates an [NSError] from JSON.
  static NSError fromJson(Json json) => _$NSErrorFromJson(json);

  /// Converts this [NSError] to [Json].
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

/// {@template user_info}
/// A pared-down representation of the userInfo property of an NSError.
/// {@endtemplate}
@JsonSerializable(fieldRename: FieldRename.none)
class UserInfo extends Equatable {
  /// {@macro user_info}
  const UserInfo({
    this.description,
    this.localizedDescription,
    this.localizedFailureReason,
    this.underlyingError,
  });

  /// A description of the error.
  @JsonKey(name: 'NSDescription')
  final StringContainer? description;

  /// A localized description of the error.
  @JsonKey(name: 'NSLocalizedDescription')
  final StringContainer? localizedDescription;

  /// A localized description of the failure reason.
  @JsonKey(name: 'NSLocalizedFailureReason')
  final StringContainer? localizedFailureReason;

  /// The underlying error, if any.
  @JsonKey(name: 'NSUnderlyingError')
  final NSUnderlyingError? underlyingError;

  /// An empty [UserInfo] instance.
  static const nullInfo = UserInfo();

  /// Creates a [UserInfo] from [Json].
  static UserInfo fromJson(Json json) => _$UserInfoFromJson(json);

  /// Converts this [UserInfo] to [Json].
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

/// {@template string_container}
/// A container for a string value.
/// {@endtemplate}
@JsonSerializable(fieldRename: FieldRename.none)
class StringContainer extends Equatable {
  /// {@macro string_container}
  const StringContainer(this.string);

  /// The string value.
  final String string;

  /// Creates a [StringContainer] from [Json].
  static StringContainer fromJson(Json json) => _$StringContainerFromJson(json);

  /// Converts this [StringContainer] to [Json].
  Json toJson() => _$StringContainerToJson(this);

  @override
  String toString() => string;

  @override
  List<Object> get props => [string];
}

/// {@template ns_underlying_error}
/// A pared-down representation of the NSUnderlyingError class.
/// {@endtemplate}
@JsonSerializable(fieldRename: FieldRename.none)
class NSUnderlyingError extends Equatable {
  /// {@macro ns_underlying_error}
  const NSUnderlyingError({required this.error});

  /// The underlying error.
  final NSError? error;

  /// Creates an [NSUnderlyingError] from [Json].
  static NSUnderlyingError fromJson(Json json) =>
      _$NSUnderlyingErrorFromJson(json);

  /// Converts this [NSUnderlyingError] to [Json].
  Json toJson() => _$NSUnderlyingErrorToJson(this);

  @override
  String toString() => '''
NSUnderlyingError(
  $error
)''';

  @override
  List<Object?> get props => [error];
}
