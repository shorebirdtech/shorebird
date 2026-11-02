import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/abi.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(UserAgentClient, () {
    late http.Client httpClient;
    late LocalAbi abi;
    late NativePlatform platform;
    late UserAgentClient userAgentClient;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          abiRef.overrideWith(() => abi),
          platformRef.overrideWith(() => platform),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      abi = MockAbi();
      when(() => abi.hostArchitecture).thenReturn('arm64');
      httpClient = MockHttpClient();
      platform = TestNativePlatform(
        operatingSystem: NativePlatform.linux,
        version:
            '3.9.0 (stable) (Mon Aug 11 00:00:00 2025 +0000) on "linux_x64"',
      );
      userAgentClient = UserAgentClient(httpClient: httpClient);

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );
    });

    test(
      'names the CLI version, OS, CPU architecture and Dart version',
      () {
        expect(
          runWithOverrides(() => shorebirdUserAgent),
          equals('shorebird-cli/$packageVersion (linux; arm64; dart 3.9.0)'),
        );
      },
    );

    test('sets the User-Agent header', () async {
      final request = http.Request('GET', Uri.parse('https://example.com'));

      await runWithOverrides(() => userAgentClient.send(request));

      final sent =
          verify(() => httpClient.send(captureAny())).captured.single
              as http.BaseRequest;
      expect(
        sent.headers['user-agent'],
        equals('shorebird-cli/$packageVersion (linux; arm64; dart 3.9.0)'),
      );
    });

    test('keeps a User-Agent the request already sets', () async {
      final request = http.Request('GET', Uri.parse('https://example.com'))
        ..headers['user-agent'] = 'custom/1.0';

      await runWithOverrides(() => userAgentClient.send(request));

      final sent =
          verify(() => httpClient.send(captureAny())).captured.single
              as http.BaseRequest;
      expect(sent.headers['User-Agent'], equals('custom/1.0'));
      expect(sent.headers, hasLength(1));
    });

    test('closes the wrapped client', () {
      userAgentClient.close();

      verify(() => httpClient.close()).called(1);
    });
  });
}
