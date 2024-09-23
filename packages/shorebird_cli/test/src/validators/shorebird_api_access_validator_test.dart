import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(ShorebirdApiAccessValidator, () {
    late http.Client httpClient;
    late ShorebirdApiAccessValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          httpClientRef.overrideWith(() => httpClient),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Uri());
    });

    setUp(() {
      httpClient = MockHttpClient();
      validator = ShorebirdApiAccessValidator();

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
      group('when url is accessible', () {
        setUp(() {
          when(() => httpClient.get(any())).thenAnswer(
            (_) async => http.Response('', HttpStatus.ok),
          );
        });

        test('returns empty list of validation issues', () async {
          final results = await runWithOverrides(validator.validate);
          expect(results, isEmpty);
        });
      });

      group('when url is inaccessible', () {
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
                  message: 'Unable to access api.shorebird.dev',
                ),
              ],
            ),
          );
        });
      });
    });
  });
}
