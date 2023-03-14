import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'account.g.dart';

/// {@template account}
/// A user account which contains zero or more apps.
/// {@endtemplate}
@JsonSerializable()
class Account {
  /// {@macro account}
  Account({required this.apiKey, List<App>? apps}) : apps = apps ?? [];

  /// Converts a Map<String, dynamic> to a [Account]
  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);

  /// Converts a [Account] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$AccountToJson(this);

  /// List of apps associated with this account.
  final List<App> apps;

  /// The api key associated with this account.
  final String apiKey;
}
