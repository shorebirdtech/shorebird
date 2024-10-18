import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
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

        test('throws a NetworkCheckerException', () async {
          await expectLater(
            runWithOverrides(networkChecker.performGCPSpeedTest),
            throwsA(
              isA<NetworkCheckerException>().having(
                (e) => e.message,
                'message',
                contains('Failed to upload file'),
              ),
            ),
          );
        });
      });

      group('when upload times out', () {
        const uploadTimeout = Duration(milliseconds: 1);
        // Make this a healthy multiple of the upload timeout to avoid flakiness
        // on slow (read: Windows) CI machines.
        final responseTime = uploadTimeout * 5;
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async {
              await Future<void>.delayed(responseTime);
              return http.StreamedResponse(
                const Stream.empty(),
                HttpStatus.noContent,
              );
            },
          );
        });

        test('throws a NetworkCheckerException', () async {
          await expectLater(
            () => runWithOverrides(
              () => networkChecker.performGCPSpeedTest(
                uploadTimeout: uploadTimeout,
              ),
            ),
            throwsA(
              isA<NetworkCheckerException>().having(
                (e) => e.message,
                'message',
                equals('Upload timed out'),
              ),
            ),
          );
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

        test('returns upload rate in MB/s', () async {
          /// 2024-10-16 00:00:00
          final start = DateTime.fromMillisecondsSinceEpoch(1729051200000);

          /// 2024-10-16 00:00:01
          final end = DateTime.fromMillisecondsSinceEpoch(1729051201000);
          var hasReturnedStart = false;

          final clock = Clock(() {
            if (hasReturnedStart) {
              return end;
            } else {
              hasReturnedStart = true;
              return start;
            }
          });
          await withClock(clock, () async {
            final speed =
                await runWithOverrides(networkChecker.performGCPSpeedTest);
            // Our 5MB file took 1 second to upload, so our speed is 5 MB/s.
            expect(speed, equals(5.0));

            final capturedRequest = verify(() => httpClient.send(captureAny()))
                .captured
                .last as http.MultipartRequest;
            expect(capturedRequest.method, equals('POST'));
            expect(capturedRequest.url, equals(gcpUri));
          });
        });
      });
    });
  });
}
