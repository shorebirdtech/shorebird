import 'dart:convert';

import 'package:args/args.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

void main() {
  group(JsonResult, () {
    group('success', () {
      test('serializes correctly', () {
        final result = JsonResult.success(
          data: <String, dynamic>{'releases': <dynamic>[]},
          command: 'doctor',
        );
        final json = result.toJson();
        expect(json['status'], equals('success'));
        expect(json['data'], equals({'releases': <dynamic>[]}));
        final meta = json['meta'] as Map<String, dynamic>;
        expect(meta['version'], equals(packageVersion));
        expect(meta['command'], equals('doctor'));
        expect(json.containsKey('error'), isFalse);
      });

      test('produces valid JSON', () {
        final result = JsonResult.success(
          data: {'key': 'value'},
          command: 'doctor',
        );
        final encoded = jsonEncode(result.toJson());
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        expect(decoded['status'], equals('success'));
      });
    });

    group('error', () {
      test('serializes correctly without hint', () {
        final result = JsonResult.error(
          code: JsonErrorCode.softwareError,
          message: 'Not authenticated.',
          command: 'doctor',
        );
        final json = result.toJson();
        expect(json['status'], equals('error'));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], equals('software_error'));
        expect(error['message'], equals('Not authenticated.'));
        expect(error.containsKey('hint'), isFalse);
        final meta = json['meta'] as Map<String, dynamic>;
        expect(meta['version'], equals(packageVersion));
        expect(meta['command'], equals('doctor'));
        expect(json.containsKey('data'), isFalse);
      });

      test('serializes correctly with hint', () {
        final result = JsonResult.error(
          code: JsonErrorCode.usageError,
          message: 'Not authenticated.',
          hint: 'Run: shorebird login:ci',
          command: 'doctor',
        );
        final json = result.toJson();
        final error = json['error'] as Map<String, dynamic>;
        expect(error['hint'], equals('Run: shorebird login:ci'));
      });
    });
  });

  group('commandNameFromResults', () {
    test('returns shorebird when no command is present', () {
      final parser = ArgParser()..addFlag('version');
      final results = parser.parse(['--version']);
      expect(commandNameFromResults(results), equals('shorebird'));
    });
  });

  group(JsonMeta, () {
    test('serializes correctly', () {
      const meta = JsonMeta(version: '1.0.0', command: 'doctor');
      expect(meta.toJson(), equals({'version': '1.0.0', 'command': 'doctor'}));
    });
  });

  group(JsonError, () {
    test('serializes correctly without hint', () {
      const error = JsonError(
        code: JsonErrorCode.softwareError,
        message: 'test message',
      );
      final json = error.toJson();
      expect(json['code'], equals('software_error'));
      expect(json['message'], equals('test message'));
      expect(json.containsKey('hint'), isFalse);
    });

    test('serializes correctly with hint', () {
      const error = JsonError(
        code: JsonErrorCode.usageError,
        message: 'test message',
        hint: 'try this',
      );
      expect(error.toJson()['hint'], equals('try this'));
    });
  });
}
