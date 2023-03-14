import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'registry.g.dart';

/// {@template registry}
/// A collection of accounts and their respective apps
/// {@endtemplate}
@JsonSerializable()
class Registry {
  /// {@macro registry}
  const Registry({this.accounts = const []});

  /// Converts a Map<String, dynamic> to a [Registry]
  factory Registry.fromJson(Map<String, dynamic> json) =>
      _$RegistryFromJson(json);

  /// Converts a [Registry] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$RegistryToJson(this);

  /// List of accounts associated with this registry.
  final List<Account> accounts;
}
