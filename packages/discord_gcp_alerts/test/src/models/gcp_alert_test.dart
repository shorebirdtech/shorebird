import 'package:discord_gcp_alerts/discord_gcp_alerts.dart';
import 'package:test/test.dart';

void main() {
  group('GCPAlert', () {
    test('can be (de)serialized', () {
      const alert = GCPAlert(
        version: '1.0.0',
        incident: Incident(
          condition: Condition(
            name: 'test',
            displayName: 'Test Condition',
            conditionThreshold: ConditionThreshold(
              trigger: Trigger(count: 10),
              filter: 'metric.type = "test.googleapis.com/metric"',
              comparison: 'ComparisonType.greaterThan',
              thresholdValue: 1,
              duration: '0s',
            ),
          ),
          resource: Resource(type: 'test_resource'),
          metric: Metric(
            type: 'test.googleapis.com/metric',
            displayName: 'Test Metric',
          ),
        ),
      );
      expect(
        GCPAlert.fromJson(alert.toJson()).toJson(),
        equals(alert.toJson()),
      );
    });
  });
}
