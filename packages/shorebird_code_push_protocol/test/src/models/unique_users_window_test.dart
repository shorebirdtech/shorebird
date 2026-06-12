import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  // The generated round-trip tests cover the required-fields-only case;
  // these cover the fully-populated window atoms — in particular the
  // allOf-composed current window carrying both `time_series` and
  // `breakdown` — and the envelope that nests them.
  final range = MetricsRange(
    start: DateTime.utc(2026, 4, 22),
    end: DateTime.utc(2026, 5, 20),
  );
  final series = [
    UniqueUsersTimeSeriesEntry(
      period: DateTime.utc(2026, 4, 22),
      uniqueUsers: 10,
    ),
    UniqueUsersTimeSeriesEntry(
      period: DateTime.utc(2026, 4, 23),
      uniqueUsers: 12,
    ),
  ];

  group('UniqueUsersWindow', () {
    test('round-trips with a populated time_series', () {
      final window = UniqueUsersWindow(
        uniqueUsers: 42,
        range: range,
        timeSeries: series,
      );
      final parsed = UniqueUsersWindow.fromJson(window.toJson());
      expect(parsed, equals(window));
      expect(parsed.toJson(), equals(window.toJson()));
    });
  });

  group('UniqueUsersCurrentWindow', () {
    test('round-trips with time_series and breakdown populated', () {
      final window = UniqueUsersCurrentWindow(
        uniqueUsers: 42,
        range: range,
        timeSeries: series,
        breakdown: [
          UniqueUsersBreakdownEntry(
            groupBy: 'platform',
            groupValue: 'android',
            uniqueUsers: 30,
            timeSeries: series,
          ),
          const UniqueUsersBreakdownEntry(
            groupBy: 'platform',
            groupValue: 'ios',
            uniqueUsers: 12,
          ),
        ],
      );
      final parsed = UniqueUsersCurrentWindow.fromJson(window.toJson());
      expect(parsed, equals(window));
      expect(parsed.toJson(), equals(window.toJson()));
    });
  });

  group('GetUniqueUsersResponse', () {
    test('round-trips the full current/previous envelope', () {
      final response = GetUniqueUsersResponse(
        asOf: DateTime.utc(2026, 5, 20, 17, 30),
        granularity: 'day',
        current: UniqueUsersCurrentWindow(
          uniqueUsers: 42,
          range: range,
          timeSeries: series,
          breakdown: [
            UniqueUsersBreakdownEntry(
              groupBy: 'platform',
              groupValue: 'android',
              uniqueUsers: 30,
              timeSeries: series,
            ),
          ],
        ),
        previous: UniqueUsersWindow(
          uniqueUsers: 37,
          range: MetricsRange(
            start: DateTime.utc(2026, 3, 25),
            end: DateTime.utc(2026, 4, 22),
          ),
          timeSeries: series,
        ),
      );
      final parsed = GetUniqueUsersResponse.fromJson(response.toJson());
      expect(parsed, equals(response));
      expect(parsed.toJson(), equals(response.toJson()));
    });

    test('round-trips the no-granularity envelope (null sections)', () {
      final response = GetUniqueUsersResponse(
        asOf: DateTime.utc(2026, 5, 20, 17, 30),
        granularity: null,
        current: UniqueUsersCurrentWindow(uniqueUsers: 42, range: range),
        previous: UniqueUsersWindow(
          uniqueUsers: 37,
          range: MetricsRange(
            start: DateTime.utc(2026, 3, 25),
            end: DateTime.utc(2026, 4, 22),
          ),
        ),
      );
      final parsed = GetUniqueUsersResponse.fromJson(response.toJson());
      expect(parsed, equals(response));
      expect(parsed.current.timeSeries, isNull);
      expect(parsed.current.breakdown, isNull);
      expect(parsed.previous.timeSeries, isNull);
    });
  });
}
