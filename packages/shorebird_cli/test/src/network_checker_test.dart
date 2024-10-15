import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/network_checker.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(NetworkChecker, () {
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late Progress progress;
    late NetworkChecker networkChecker;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(Uri());
    });

    setUp(() {
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      progress = MockProgress();

      when(() => logger.progress(any())).thenReturn(progress);

      networkChecker = NetworkChecker();
    });

    group('checkReachability', () {
      group('when endpoints are reachable', () {
        setUp(() {
          when(() => httpClient.get(any())).thenAnswer(
            (_) async => http.Response('', HttpStatus.ok),
          );
        });

        test('logs reachability for each checked url', () async {
          await runWithOverrides(networkChecker.checkReachability);

          verify(
            () => progress.complete(any(that: contains('OK'))),
          ).called(NetworkChecker.urlsToCheck.length);
        });
      });

      group('when endpoints are not reachable', () {
        setUp(() {
          when(() => httpClient.send(any())).thenThrow(Exception('oops'));
        });

        test('logs reachability for each checked url', () async {
          await runWithOverrides(networkChecker.checkReachability);

          verify(
            () => progress.fail(any(that: contains('unreachable'))),
          ).called(NetworkChecker.urlsToCheck.length);
        });
      });
    });
  });
}
