import 'package:stripe_api/src/converters/timestamp_converter.dart';
import 'package:test/test.dart';

void main() {
  group(TimestampConverter, () {
    group('toJson()', () {
      test('converts a DateTime to a timestamp', () {
        const converter = TimestampConverter();
        final dateTime = DateTime(2023);
        final timestamp = converter.toJson(dateTime);
        expect(timestamp, equals(dateTime.millisecondsSinceEpoch ~/ 1000));
      });
    });

    group('fromJson()', () {
      test('converts a timestamp to a DateTime', () {
        const converter = TimestampConverter();
        const timestamp = 1672552800;
        final dateTime = converter.fromJson(timestamp);
        expect(
          dateTime,
          equals(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)),
        );
      });
    });
  });
}
