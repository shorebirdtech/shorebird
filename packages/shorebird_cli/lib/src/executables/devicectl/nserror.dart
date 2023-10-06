import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

part 'nserror.g.dart';

/// {@template nserror}
/// A pared-down representation of the NSError class.
///
/// See https://developer.apple.com/documentation/foundation/nserror.
/// {@endtemplate}
@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class NSError {
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
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class UserInfo {
  const UserInfo({
    this.localizedDescription,
    this.localizedFailureReason,
    this.underlyingError,
  });

  @JsonKey(name: 'NSLocalizedDescription')
  final StringContainer? localizedDescription;

  @JsonKey(name: 'NSLocalizedFailureReason')
  final StringContainer? localizedFailureReason;

  @JsonKey(name: 'NSUnderlyingError')
  final NSUnderlyingError? underlyingError;

  static UserInfo fromJson(Json json) => _$UserInfoFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class StringContainer {
  const StringContainer({required this.string});

  final String string;

  static StringContainer fromJson(Json json) => _$StringContainerFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class NSUnderlyingError {
  const NSUnderlyingError({required this.error});

  final NSError? error;

  static NSUnderlyingError fromJson(Json json) =>
      _$NSUnderlyingErrorFromJson(json);
}
