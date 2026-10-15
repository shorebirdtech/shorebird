import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/credential_source.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../helpers.dart';
import '../matchers.dart';
import '../mocks.dart';

/// A [CredentialSource] that answers [header], or throws [failure].
class _FakeSource implements CredentialSource {
  _FakeSource(
    this.header, {
    this.isAvailable = true,
    this.failure,
  });

  final String header;

  @override
  bool isAvailable;

  CredentialSourceException? failure;

  int calls = 0;

  @override
  Future<String> authorization() async {
    calls++;
    if (failure case final failure?) throw failure;
    return header;
  }
}

void main() {
  useTempWorkingDirectory();

  late ShorebirdLogger logger;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
  });

  setUp(() {
    logger = MockShorebirdLogger();
  });

  R runWithOverrides<R>(R Function() body) {
    return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
  }

  group(CredentialChain, () {
    test('is available when any source is', () {
      expect(CredentialChain([]).isAvailable, isFalse);
      expect(
        CredentialChain([_FakeSource('a', isAvailable: false)]).isAvailable,
        isFalse,
      );
      expect(
        CredentialChain([
          _FakeSource('a', isAvailable: false),
          _FakeSource('b'),
        ]).isAvailable,
        isTrue,
      );
    });

    test('answers with the first available source, in order', () async {
      final first = _FakeSource('Bearer first');
      final second = _FakeSource('Bearer second');
      final chain = CredentialChain([first, second]);

      expect(await runWithOverrides(chain.authorization), 'Bearer first');
      expect(second.calls, isZero);
    });

    test('skips sources that are not available', () async {
      final first = _FakeSource('Bearer first', isAvailable: false);
      final second = _FakeSource('Bearer second');
      final chain = CredentialChain([first, second]);

      expect(await runWithOverrides(chain.authorization), 'Bearer second');
      expect(first.calls, isZero);
    });

    test('asks again when a source becomes available', () async {
      final first = _FakeSource('Bearer first', isAvailable: false);
      final second = _FakeSource('Bearer second');
      final chain = CredentialChain([first, second]);

      expect(await runWithOverrides(chain.authorization), 'Bearer second');
      first.isAvailable = true;
      expect(await runWithOverrides(chain.authorization), 'Bearer first');
    });

    group('when a source fails', () {
      late _FakeSource first;
      late _FakeSource second;

      setUp(() {
        first = _FakeSource(
          'Bearer first',
          failure: const CredentialSourceException(
            'First failed.',
            hint: 'Fix first.',
          ),
        );
        second = _FakeSource('Bearer second');
      });

      test('falls back to the next available source', () async {
        final chain = CredentialChain([first, second]);

        expect(await runWithOverrides(chain.authorization), 'Bearer second');
        verify(
          () => logger.detail(
            'First failed. Trying the next way to authenticate.',
          ),
        ).called(1);
        verifyNever(() => logger.err(any()));
      });

      test('does not try it again', () async {
        final chain = CredentialChain([first, second]);

        await runWithOverrides(chain.authorization);
        await runWithOverrides(chain.authorization);

        expect(first.calls, equals(1));
        expect(second.calls, equals(2));
      });

      test('reports the failure when no source is left', () async {
        second.isAvailable = false;
        final chain = CredentialChain([first, second]);

        await expectLater(
          runWithOverrides(chain.authorization),
          exitsWithCode(ExitCode.software),
        );
        verify(() => logger.err('First failed.')).called(1);
        verify(() => logger.info('Fix first.')).called(1);
      });

      test('reports a failure without a hint', () async {
        final chain = CredentialChain([
          _FakeSource(
            'Bearer only',
            failure: const CredentialSourceException('Only failed.'),
          ),
        ]);

        await expectLater(
          runWithOverrides(chain.authorization),
          exitsWithCode(ExitCode.software),
        );
        verify(() => logger.err('Only failed.')).called(1);
        verifyNever(() => logger.info(any()));
      });
    });

    test('throws when no source is available', () {
      expect(
        runWithOverrides(
          CredentialChain([_FakeSource('a', isAvailable: false)]).authorization,
        ),
        throwsStateError,
      );
    });

    test('lists its sources in order', () {
      final first = _FakeSource('a');
      final second = _FakeSource('b');
      expect(CredentialChain([first, second]).sources, [first, second]);
    });
  });

  group(CredentialSourceException, () {
    test('toString does not include the hint', () {
      expect(
        const CredentialSourceException('message', hint: 'hint').toString(),
        equals('CredentialSourceException: message'),
      );
    });
  });

  group(AuthenticatedClient, () {
    late http.Client httpClient;

    setUp(() {
      httpClient = MockHttpClient();
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), 200),
      );
    });

    test('sends the source answer as the Authorization header', () async {
      final client = AuthenticatedClient(
        credentials: _FakeSource('Bearer token'),
        httpClient: httpClient,
      );

      await runWithOverrides(
        () => client.get(Uri.parse('https://example.com')),
      );

      final request =
          verify(() => httpClient.send(captureAny())).captured.single
              as http.BaseRequest;
      expect(request.headers['Authorization'], equals('Bearer token'));
    });

    test('asks the source again for each request', () async {
      final source = _FakeSource('Bearer token');
      final client = AuthenticatedClient(
        credentials: source,
        httpClient: httpClient,
      );

      await runWithOverrides(() async {
        await client.get(Uri.parse('https://example.com'));
        await client.get(Uri.parse('https://example.com'));
      });

      expect(source.calls, equals(2));
    });
  });
}
