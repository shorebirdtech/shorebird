import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(StorageAccessValidator, () {
    late http.Client httpClient;
    late StorageAccessValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          httpClientRef.overrideWith(() => httpClient),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Uri.parse('http://example.com'));
    });

    setUp(() {
      httpClient = MockHttpClient();
      validator = StorageAccessValidator();

      when(() => httpClient.get(any())).thenAnswer(
        (_) async => http.Response('', HttpStatus.ok),
      );
    });

    group('description', () {
      test('has a non-empty description', () {
        expect(validator.description, isNotEmpty);
      });
    });

    group('validate', () {
      group('when storage url is accessible', () {
        setUp(() {
          when(() => httpClient.get(any())).thenAnswer(
            (_) async => http.Response('hello', HttpStatus.ok),
          );
        });

        test('returns empty list of validation issues', () async {
          final results = await runWithOverrides(validator.validate);
          expect(results, isEmpty);
        });
      });

      group('when storage url is inaccessible', () {
        setUp(() {
          when(() => httpClient.get(any())).thenAnswer(
            (_) async => http.Response('Not Found', HttpStatus.notFound),
          );
        });

        test('returns validation error', () async {
          final results = await runWithOverrides(validator.validate);
          expect(
            results,
            equals(
              [
                const ValidationIssue(
                  severity: ValidationIssueSeverity.error,
                  message: 'Unable to access storage.googleapis.com',
                ),
              ],
            ),
          );
        });
      });
    });
  });
}
