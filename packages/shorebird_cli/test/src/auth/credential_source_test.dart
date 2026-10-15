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
class _FakeSource extends CredentialSource {
  _FakeSource(
    this.header, {
    this.isAvailable = true,
    this.failure,
    this.unavailableReason,
  });

  final String header;

  @override
  bool isAvailable;

  @override
  final CredentialSourceException? unavailableReason;

  CredentialSourceException? failure;

  int calls = 0;

  final checkedResponses = <http.BaseResponse>[];

  Exception? responseFailure;

  @override
  void checkResponse(http.BaseResponse response) {
    checkedResponses.add(response);
    if (responseFailure case final failure?) throw failure;
  }

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

  /// The `Authorization` header value [chain] resolves.
  Future<String> authorize(CredentialChain chain) => runWithOverrides(
    () async => (await chain.resolve()).authorization,
  );

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

      expect(await authorize(chain), 'Bearer first');
      expect(second.calls, isZero);
    });

    test('skips sources that are not available', () async {
      final first = _FakeSource('Bearer first', isAvailable: false);
      final second = _FakeSource('Bearer second');
      final chain = CredentialChain([first, second]);

      expect(await authorize(chain), 'Bearer second');
      expect(first.calls, isZero);
    });

    test('asks again when a source becomes available', () async {
      final first = _FakeSource('Bearer first', isAvailable: false);
      final second = _FakeSource('Bearer second');
      final chain = CredentialChain([first, second]);

      expect(await authorize(chain), 'Bearer second');
      first.isAvailable = true;
      expect(await authorize(chain), 'Bearer first');
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

        expect(await authorize(chain), 'Bearer second');
        verify(
          () => logger.detail(
            'First failed. Trying the next way to authenticate.',
          ),
        ).called(1);
        verifyNever(() => logger.err(any()));
      });

      test('does not try it again', () async {
        final chain = CredentialChain([first, second]);

        await authorize(chain);
        await authorize(chain);

        expect(first.calls, equals(1));
        expect(second.calls, equals(2));
      });

      test('reports the failure when no source is left', () async {
        second.isAvailable = false;
        final chain = CredentialChain([first, second]);

        await expectLater(
          authorize(chain),
          exitsWithCode(ExitCode.software),
        );
        verify(() => logger.err('First failed.')).called(1);
        verify(() => logger.info('Fix first.')).called(1);
      });

      test('reports why a source meant to be used is not available', () async {
        final chain = CredentialChain([
          _FakeSource(
            'Bearer unusable',
            isAvailable: false,
            unavailableReason: const CredentialSourceException(
              'Unusable needs a setting.',
              hint: 'Set it.',
            ),
          ),
          first,
        ]);

        await expectLater(
          authorize(chain),
          exitsWithCode(ExitCode.software),
        );
        verifyInOrder([
          () => logger.err('First failed.'),
          () => logger.info('Fix first.'),
          () => logger.info('Unusable needs a setting.'),
          () => logger.info('Set it.'),
        ]);
      });

      test('ends the command with the exit code of the failure', () async {
        final chain = CredentialChain([
          _FakeSource(
            'Bearer only',
            failure: const CredentialSourceException(
              'Only failed for now.',
              exitCode: ExitCode.tempFail,
            ),
          ),
        ]);

        await expectLater(
          authorize(chain),
          exitsWithCode(ExitCode.tempFail),
        );
      });

      test('reports a failure without a hint', () async {
        final chain = CredentialChain([
          _FakeSource(
            'Bearer only',
            failure: const CredentialSourceException('Only failed.'),
          ),
        ]);

        await expectLater(
          authorize(chain),
          exitsWithCode(ExitCode.software),
        );
        verify(() => logger.err('Only failed.')).called(1);
        verifyNever(() => logger.info(any()));
      });
    });

    test('throws when no source is available', () {
      expect(
        authorize(CredentialChain([_FakeSource('a', isAvailable: false)])),
        throwsStateError,
      );
    });

    test('reports the first reason a source is not available', () {
      const reason = CredentialSourceException('Needs a setting.');
      expect(CredentialChain([_FakeSource('a')]).unavailableReason, isNull);
      expect(
        CredentialChain([
          _FakeSource('a'),
          _FakeSource('b', isAvailable: false, unavailableReason: reason),
          _FakeSource(
            'c',
            isAvailable: false,
            unavailableReason: const CredentialSourceException('Other.'),
          ),
        ]).unavailableReason,
        same(reason),
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

    AuthenticatedClient clientFor(List<CredentialSource> sources) =>
        AuthenticatedClient(
          credentials: CredentialChain(sources),
          httpClient: httpClient,
        );

    test('sends the source answer as the Authorization header', () async {
      final client = clientFor([_FakeSource('Bearer token')]);

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
      final client = clientFor([source]);

      await runWithOverrides(() async {
        await client.get(Uri.parse('https://example.com'));
        await client.get(Uri.parse('https://example.com'));
      });

      expect(source.calls, equals(2));
    });

    test('lets the source that answered check the response', () async {
      final unavailable = _FakeSource('Bearer first', isAvailable: false);
      final source = _FakeSource('Bearer second');
      final client = clientFor([unavailable, source]);

      final response = await runWithOverrides(
        () => client.get(Uri.parse('https://example.com')),
      );

      expect(source.checkedResponses.single.statusCode, response.statusCode);
      expect(unavailable.checkedResponses, isEmpty);
    });

    test('throws what the source throws for a response', () async {
      final source = _FakeSource('Bearer token')
        ..responseFailure = Exception('refused');
      final client = clientFor([source]);

      await expectLater(
        runWithOverrides(() => client.get(Uri.parse('https://example.com'))),
        throwsA(isA<Exception>()),
      );
    });
  });

  test('a source accepts every response by default', () {
    const _AcceptingSource().checkResponse(
      http.Response('', 401, headers: {'www-authenticate': 'Bearer'}),
    );
  });

  test('a source has no unavailable reason by default', () {
    expect(const _AcceptingSource().unavailableReason, isNull);
  });
}

/// A [CredentialSource] that keeps the default [checkResponse].
class _AcceptingSource extends CredentialSource {
  const _AcceptingSource();

  @override
  bool get isAvailable => true;

  @override
  Future<String> authorization() async => 'Bearer token';
}
