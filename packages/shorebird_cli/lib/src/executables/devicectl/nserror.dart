import 'package:json_annotation/json_annotation.dart';

part 'nserror.g.dart';

/// A representation of the NSError class.
///
/// See https://developer.apple.com/documentation/foundation/nserror.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class NSError {
  NSError({
    required this.code,
    required this.domain,
    required this.userInfo,
  });

  final int code;
  final String domain;
  final UserInfo userInfo;

  static NSError fromJson(Map<String, dynamic> json) => _$NSErrorFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class UserInfo {
  UserInfo({
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

  static UserInfo fromJson(Map<String, dynamic> json) =>
      _$UserInfoFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class StringContainer {
  StringContainer({required this.string});

  final String string;

  static StringContainer fromJson(Map<String, dynamic> json) =>
      _$StringContainerFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class NSUnderlyingError {
  NSUnderlyingError({required this.error});

  final NSError? error;

  static NSUnderlyingError fromJson(Map<String, dynamic> json) =>
      _$NSUnderlyingErrorFromJson(json);
}
