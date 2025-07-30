import 'package:json_annotation/json_annotation.dart';

part 'paged_response.g.dart';

/// {@template paged_response}
/// A response that contains a list of data and a flag indicating if there is
/// more data available.
/// See https://stripe.com/docs/api/pagination.
/// {@endtemplate}
@JsonSerializable()
class PagedResponse {
  /// {@macro paged_response}
  PagedResponse({required this.data, required this.hasMore});

  /// Converts a `Map<String, dynamic>` to a [PagedResponse].
  factory PagedResponse.fromJson(Map<String, dynamic> json) =>
      _$PagedResponseFromJson(json);

  /// The data in this page of the response.
  final List<dynamic> data;

  /// Whether there are more pages of data available.
  final bool hasMore;
}
