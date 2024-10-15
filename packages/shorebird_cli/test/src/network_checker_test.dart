import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/network_checker.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(NetworkChecker, () {
    late CodePushClientWrapper codePushClientWrapper;
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late Progress progress;
    late NetworkChecker networkChecker;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
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
      codePushClientWrapper = MockCodePushClientWrapper();
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

    group('performGCPSpeedTest', () {
      final gcpUri = Uri.parse('http://localhost');

      setUp(() {
        when(() => codePushClientWrapper.getGCPSpeedTestUrl()).thenAnswer(
          (_) async => gcpUri,
        );
      });

      group('when upload fails', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.badGateway,
            ),
          );
        });

        test('progress fails by printing error', () async {
          await expectLater(
            runWithOverrides(networkChecker.performGCPSpeedTest),
            throwsException,
          );

          verify(
            () => progress.fail(any(that: contains('Failed to upload file'))),
          ).called(1);
        });
      });

      group('when upload times out', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.noContent,
            ),
          );
        });

        test('progress fails by printing error', () {
          fakeAsync((async) {
            expect(
              runWithOverrides(networkChecker.performGCPSpeedTest),
              throwsException,
            );

            async.elapse(const Duration(minutes: 2));

            verify(
              () => progress.fail('CP speed test aborted: upload timed out'),
            ).called(1);
          });
        });
      });

      group('when upload succeeds', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.noContent,
            ),
          );
        });

        test('progress completes by printing rate', () async {
          await runWithOverrides(networkChecker.performGCPSpeedTest);

          final capturedRequest = verify(() => httpClient.send(captureAny()))
              .captured
              .last as http.MultipartRequest;
          expect(capturedRequest.method, equals('POST'));
          expect(capturedRequest.url, equals(gcpUri));
          verify(
            () => progress.complete(any(that: endsWith('MB/s'))),
          ).called(1);
        });
      });
    });
  });
}
