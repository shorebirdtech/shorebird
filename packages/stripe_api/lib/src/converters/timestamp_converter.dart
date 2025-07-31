import 'package:json_annotation/json_annotation.dart';

/// {@template timestamp_converter}
/// Converts between Unix timestamps and [DateTime].
/// {@endtemplate}
class TimestampConverter implements JsonConverter<DateTime, int> {
  /// {@macro timestamp_converter}
  const TimestampConverter();

  @override
  DateTime fromJson(int timestamp) =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  @override
  int toJson(DateTime dateTime) => dateTime.millisecondsSinceEpoch ~/ 1000;
}
