import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/api_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(ApiCommand, () {
    const appId = 'app-id';
    const prodAppId = 'prod-app-id';
    final apiBaseUri = Uri.parse('https://api.shorebird.dev/api/v1');

    late CodePushClient codePushClient;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late _FakeStdout fakeStdout;
    late _FakeStdout fakeStderr;
    late List<int> stdinBytes;
    late ApiCommand command;

    // The response the API sends back, set per test.
    late int responseStatus;
    late String responseBody;
    late Map<String, String> responseHeaders;

    setUpAll(() {
      registerFallbackValue(http.Request('GET', Uri()));
    });

    /// Runs `shorebird api [args]` and returns its exit code.
    Future<int> runApi(List<String> args, {bool jsonMode = false}) {
      command = ApiCommand()..testRunner = usageRunner();
      command.testArgResults = command.argParser.parse(args);
      return runScoped(
        () => IOOverrides.runZoned(
          command.run,
          stdout: () => fakeStdout,
          stderr: () => fakeStderr,
          stdin: () => _FakeStdin(stdinBytes),
        ),
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    /// The request the command sent.
    http.Request sentRequest() =>
        verify(() => codePushClient.send(captureAny())).captured.single
            as http.Request;

    setUp(() {
      codePushClient = MockCodePushClient();
      codePushClientWrapper = MockCodePushClientWrapper();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      logger = MockShorebirdLogger();
      fakeStdout = _FakeStdout();
      fakeStderr = _FakeStdout();
      stdinBytes = [];

      responseStatus = HttpStatus.ok;
      responseBody = '[{"app_id":"app-id"}]';
      responseHeaders = {'content-type': 'application/json'};

      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(() => codePushClient.apiBaseUri).thenReturn(apiBaseUri);
      when(() => codePushClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode(responseBody)),
          responseStatus,
          headers: responseHeaders,
          reasonPhrase: responseStatus == HttpStatus.ok ? 'OK' : null,
        ),
      );
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
        const ShorebirdYaml(appId: appId, flavors: {'prod': prodAppId}),
      );
    });

    test('has the right name, invocation and help', () {
      final command = ApiCommand();
      expect(command.name, equals('api'));
      expect(
        command.invocation,
        equals('shorebird api <endpoint> [arguments]'),
      );
      expect(command.reservesStdout, isTrue);
      expect(
        command.summary,
        equals(
          'Makes an authenticated HTTP request to the Shorebird API and '
          'prints the response.',
        ),
      );
      expect(
        command.description,
        allOf(
          contains('https://api.shorebird.dev/openapi.json'),
          contains('https://docs.shorebird.dev/account/api/'),
          contains('no compatibility guarantee'),
          contains(r'$ shorebird api /apps'),
          contains(r'$ shorebird api /apps/{appId}/releases'),
          contains('-f channel=beta'),
        ),
      );
    });

    group('argument validation', () {
      test('requires exactly one endpoint', () async {
        await expectLater(runApi([]), throwsA(isA<UsageException>()));
        await expectLater(
          runApi(['/apps', '/organizations']),
          throwsA(isA<UsageException>()),
        );
        verifyNever(() => codePushClient.send(any()));
      });

      test('rejects --silent with --verbose', () async {
        await expectLater(
          runApi(['/apps', '--silent', '--verbose']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('Only one of --silent or --verbose'),
            ),
          ),
        );
      });

      test('rejects --json', () async {
        await expectLater(
          runApi(['/apps'], jsonMode: true),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('does not support --json'),
            ),
          ),
        );
      });
    });

    group('when the user is not logged in', () {
      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          ),
        ).thenThrow(UserNotAuthorizedException());
      });

      test('exits with the precondition exit code', () async {
        expect(await runApi(['/apps']), equals(ExitCode.noUser.code));
        verifyNever(() => codePushClient.send(any()));
      });
    });

    group('endpoint', () {
      test('is relative to the API base URI', () async {
        expect(await runApi(['/apps']), equals(ExitCode.success.code));
        final request = sentRequest();
        expect(request.method, equals('GET'));
        expect(
          request.url,
          equals(Uri.parse('https://api.shorebird.dev/api/v1/apps')),
        );
        expect(request.headers['accept'], equals('*/*'));
        expect(request.bodyBytes, isEmpty);
      });

      test('accepts a path without a leading slash', () async {
        await runApi(['apps']);
        expect(
          sentRequest().url,
          equals(Uri.parse('https://api.shorebird.dev/api/v1/apps')),
        );
      });

      test('keeps a query string', () async {
        await runApi(['/apps/a/releases?sideloadable=true']);
        expect(
          sentRequest().url,
          equals(
            Uri.parse(
              'https://api.shorebird.dev/api/v1/apps/a/releases'
              '?sideloadable=true',
            ),
          ),
        );
      });

      test('accepts a full URL on the API host', () async {
        await runApi(['https://api.shorebird.dev/api/v1/users/me']);
        expect(
          sentRequest().url,
          equals(Uri.parse('https://api.shorebird.dev/api/v1/users/me')),
        );
      });

      test('rejects a full URL on another host', () async {
        await expectLater(
          runApi(['https://example.com/api/v1/users/me']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('only sends requests'),
            ),
          ),
        );
        verifyNever(() => codePushClient.send(any()));
      });

      group('{appId} placeholder', () {
        test('is filled from shorebird.yaml', () async {
          await runApi(['/apps/{appId}/releases']);
          expect(
            sentRequest().url.path,
            equals('/api/v1/apps/$appId/releases'),
          );
        });

        test('uses the --flavor app ID', () async {
          await runApi(['/apps/{appId}', '--flavor', 'prod']);
          expect(sentRequest().url.path, equals('/api/v1/apps/$prodAppId'));
        });

        test('rejects an unknown flavor', () async {
          await expectLater(
            runApi(['/apps/{appId}', '--flavor', 'staging']),
            throwsA(
              isA<UsageException>().having(
                (e) => e.message,
                'message',
                contains('does not have a flavor named "staging"'),
              ),
            ),
          );
        });

        test('leaves other placeholders alone', () async {
          await runApi(['/apps/{appId}/releases/{releaseId}']);
          expect(
            Uri.decodeComponent(sentRequest().url.path),
            equals('/api/v1/apps/$appId/releases/{releaseId}'),
          );
        });

        test('does not need shorebird.yaml when unused', () async {
          when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
          expect(await runApi(['/apps']), equals(ExitCode.success.code));
        });

        group('when there is no shorebird.yaml', () {
          setUp(() {
            when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
          });

          test('is a usage error that names the fix', () async {
            await expectLater(
              runApi(['/apps/{appId}']),
              throwsA(
                isA<UsageException>().having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('unable to expand placeholder {appId}'),
                    contains('put the app ID in the endpoint'),
                  ),
                ),
              ),
            );
            verifyNever(() => codePushClient.send(any()));
          });
        });
      });
    });

    group('fields', () {
      test('-f sends a JSON body and switches to POST', () async {
        await runApi(['/apps/{appId}/channels', '-f', 'channel=beta']);
        final request = sentRequest();
        expect(request.method, equals('POST'));
        expect(
          request.headers['content-type'],
          equals('application/json; charset=utf-8'),
        );
        expect(jsonDecode(request.body), equals({'channel': 'beta'}));
      });

      test('-f keeps values as strings', () async {
        await runApi(['/x', '-f', 'a=1', '-f', 'b=true', '-f', 'c=a,b']);
        expect(
          jsonDecode(sentRequest().body),
          equals({'a': '1', 'b': 'true', 'c': 'a,b'}),
        );
      });

      test('-F converts literals and fills placeholders', () async {
        await runApi([
          '/x',
          '-F',
          'n=42',
          '-F',
          'neg=-3',
          '-F',
          't=true',
          '-F',
          'f=false',
          '-F',
          'z=null',
          '-F',
          's=hello',
          '-F',
          'id={appId}',
        ]);
        expect(
          jsonDecode(sentRequest().body),
          equals({
            'n': 42,
            'neg': -3,
            't': true,
            'f': false,
            'z': null,
            's': 'hello',
            'id': appId,
          }),
        );
      });

      test('-f does not fill placeholders', () async {
        await runApi(['/x', '-f', 'id={appId}']);
        expect(jsonDecode(sentRequest().body), equals({'id': '{appId}'}));
      });

      test('-F reads @file and @- values', () async {
        File('notes.txt').writeAsStringSync('from a file');
        stdinBytes = utf8.encode('from stdin');
        await runApi(['/x', '-F', 'a=@notes.txt', '-F', 'b=@-']);
        expect(
          jsonDecode(sentRequest().body),
          equals({'a': 'from a file', 'b': 'from stdin'}),
        );
      });

      test('-F @file is a usage error when the file is missing', () async {
        await expectLater(
          runApi(['/x', '-F', 'a=@missing.txt']),
          throwsA(isA<UsageException>()),
        );
      });

      test('supports nested keys and arrays', () async {
        await runApi([
          '/x',
          '-f',
          'release[version]=1.0.0',
          '-F',
          'release[build]=3',
          '-f',
          'tags[]=a',
          '-f',
          'tags[]=b',
          '-f',
          'empty[]',
          '-f',
          'items[][name]=first',
          '-f',
          'items[][size]=1',
          '-f',
          'items[][name]=second',
        ]);
        expect(
          jsonDecode(sentRequest().body),
          equals({
            'release': {'version': '1.0.0', 'build': 3},
            'tags': ['a', 'b'],
            'empty': <Object?>[],
            'items': [
              {'name': 'first', 'size': '1'},
              {'name': 'second'},
            ],
          }),
        );
      });

      test('become the query string for GET', () async {
        await runApi([
          '-X',
          'GET',
          '/apps/{appId}/metrics/patch-installs',
          '-f',
          'granularity=day',
          '-f',
          'start=2026-01-01T00:00:00Z',
          '-F',
          'limit=5',
          '-f',
          'ids[]=1',
          '-f',
          'ids[]=2',
        ]);
        final request = sentRequest();
        expect(request.method, equals('GET'));
        expect(request.bodyBytes, isEmpty);
        expect(
          request.url.query,
          equals(
            'granularity=day&ids%5B%5D=1&ids%5B%5D=2&limit=5'
            '&start=2026-01-01T00%3A00%3A00Z',
          ),
        );
      });

      test('keep an explicit --method', () async {
        await runApi(['-X', 'patch', '/x', '-f', 'a=b']);
        expect(sentRequest().method, equals('PATCH'));
      });

      group('usage errors', () {
        for (final (field, message) in [
          ('a', 'invalid key: "a"'),
          ('a[b]', 'field "a[b]" requires a value'),
          ('a=1', 'unexpected override existing field under "a"'),
          ('a[b]=1', 'expected map type under "a", got string'),
          ('a[]=1', 'expected array type under "a", got string'),
        ]) {
          test('rejects $field', () async {
            await expectLater(
              runApi(['/x', '-f', 'a=x', '-f', field]),
              throwsA(
                isA<UsageException>().having(
                  (e) => e.message,
                  'message',
                  contains(message),
                ),
              ),
            );
          });
        }

        for (final (existing, type) in [
          ('-Fa=1', 'integer'),
          ('-Fa=true', 'boolean'),
          ('-Fa=null', 'null'),
          ('-fa[b]=1', 'map'),
        ]) {
          test('names the $type type it found', () async {
            await expectLater(
              runApi(['/x', existing, '-F', 'a[]=1']),
              throwsA(
                isA<UsageException>().having(
                  (e) => e.message,
                  'message',
                  contains('expected array type under "a", got $type'),
                ),
              ),
            );
          });
        }

        test('names the array type it found', () async {
          await expectLater(
            runApi(['/x', '-f', 'a[]=1', '-F', 'a[b]=1']),
            throwsA(
              isA<UsageException>().having(
                (e) => e.message,
                'message',
                contains('expected map type under "a", got array'),
              ),
            ),
          );
        });

        test('rejects an array of non-maps used as one', () async {
          await expectLater(
            runApi(['/x', '-f', 'a=x', '-f', 'a[][b]=1']),
            throwsA(
              isA<UsageException>().having(
                (e) => e.message,
                'message',
                contains('expected array type under "a"'),
              ),
            ),
          );
        });
      });
    });

    group('headers', () {
      test('-H adds headers and can replace Accept', () async {
        await runApi([
          '/x',
          '-H',
          'Accept: application/json',
          '-H',
          'X-Thing:  one ',
          '-H',
          'X-Thing: two',
        ]);
        final request = sentRequest();
        expect(request.headers['accept'], equals('application/json'));
        expect(request.headers['x-thing'], equals('one, two'));
      });

      test('-H can replace the JSON Content-Type', () async {
        await runApi(['/x', '-f', 'a=b', '-H', 'Content-Type: text/plain']);
        expect(sentRequest().headers['content-type'], equals('text/plain'));
      });

      test('-H without a colon is a usage error', () async {
        await expectLater(
          runApi(['/x', '-H', 'Accept']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('requires a value separated by ":"'),
            ),
          ),
        );
      });
    });

    group('--input', () {
      test('sends the file as the body and switches to POST', () async {
        File('body.json').writeAsStringSync('{"display_name":"Acme"}');
        await runApi(['/apps', '--input', 'body.json', '-f', 'dry_run=true']);
        final request = sentRequest();
        expect(request.method, equals('POST'));
        expect(request.body, equals('{"display_name":"Acme"}'));
        expect(request.url.query, equals('dry_run=true'));
        expect(request.headers.containsKey('content-type'), isFalse);
      });

      test('reads stdin for -', () async {
        stdinBytes = utf8.encode('{"a":1}');
        await runApi(['-X', 'PATCH', '/x', '--input', '-']);
        final request = sentRequest();
        expect(request.method, equals('PATCH'));
        expect(request.body, equals('{"a":1}'));
      });

      test('is a usage error when the file is missing', () async {
        await expectLater(
          runApi(['/x', '--input', 'missing.json']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('--input: no file found at missing.json'),
            ),
          ),
        );
      });
    });

    group('output', () {
      test('prints the body as-is when stdout is not a terminal', () async {
        expect(await runApi(['/apps']), equals(ExitCode.success.code));
        expect(fakeStdout.text, equals(responseBody));
        expect(fakeStderr.text, isEmpty);
      });

      group('when stdout is a terminal', () {
        setUp(() => fakeStdout.hasTerminal = true);

        test('pretty-prints JSON', () async {
          await runApi(['/apps']);
          expect(
            fakeStdout.text,
            equals('[\n  {\n    "app_id": "app-id"\n  }\n]\n'),
          );
        });

        test('prints a JSON content type that fails to parse as-is', () async {
          responseBody = 'not json';
          await runApi(['/apps']);
          expect(fakeStdout.text, equals('not json'));
        });

        test('prints non-JSON as-is', () async {
          responseHeaders = {'content-type': 'text/plain'};
          responseBody = 'ok';
          await runApi(['/apps']);
          expect(fakeStdout.text, equals('ok'));
        });
      });

      test('--include prints the status line and headers', () async {
        responseHeaders = {
          'content-type': 'application/json',
          'x-request-id': 'abc',
        };
        await runApi(['/apps', '-i']);
        expect(
          fakeStdout.text,
          equals(
            'HTTP/1.1 200 OK\n'
            'Content-Type: application/json\r\n'
            'X-Request-Id: abc\r\n'
            '\r\n'
            '$responseBody',
          ),
        );
      });

      test('--include prints a status line without a reason phrase', () async {
        responseStatus = HttpStatus.notFound;
        responseHeaders = {};
        responseBody = '';
        await runApi(['/apps', '-i']);
        expect(fakeStdout.text, equals('HTTP/1.1 404\n\r\n'));
      });

      test('--silent prints no body', () async {
        expect(await runApi(['/apps', '--silent']), ExitCode.success.code);
        expect(fakeStdout.text, isEmpty);
      });

      test('--silent with --include still prints headers', () async {
        await runApi(['/apps', '--silent', '-i']);
        expect(fakeStdout.text, startsWith('HTTP/1.1 200 OK\n'));
        expect(fakeStdout.text, isNot(contains(responseBody)));
      });

      test('prints nothing for 204 No Content', () async {
        responseStatus = HttpStatus.noContent;
        responseBody = '';
        expect(
          await runApi(['-X', 'DELETE', '/x']),
          equals(ExitCode.success.code),
        );
        expect(fakeStdout.text, isEmpty);
      });

      group('--verbose', () {
        setUp(() {
          when(() => codePushClient.send(any())).thenAnswer((invocation) async {
            // The authenticated client adds the credential as it sends.
            (invocation.positionalArguments.single as http.Request)
                    .headers['authorization'] =
                'Bearer secret-token';
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"ok":true}')),
              HttpStatus.ok,
              headers: {'content-type': 'application/json'},
              reasonPhrase: 'OK',
            );
          });
        });

        test(
          'prints the request and response, masking the credential',
          () async {
            await runApi(['/apps?x=1', '-f', 'a=b', '-X', 'POST', '--verbose']);
            final text = fakeStdout.text;
            for (final line in [
              '* Request to https://api.shorebird.dev/api/v1/apps?x=1\n',
              '> POST /api/v1/apps?x=1 HTTP/1.1\n',
              '> Host: api.shorebird.dev\n',
              '> Accept: */*\n',
              '> Authorization: Bearer ████████████████████\n',
              '{"a":"b"}\n',
              '< HTTP/1.1 200 OK\n',
              '< Content-Type: application/json\n',
              '{"ok":true}\n',
              '* Request took ',
            ]) {
              expect(text, contains(line));
            }
            expect(text, isNot(contains('secret-token')));
          },
        );
      });
    });

    group('when the request fails', () {
      test('prints the body and the server message (HTTP 404)', () async {
        responseStatus = HttpStatus.notFound;
        responseBody = '{"code":"not_found","message":"App not found"}';
        expect(await runApi(['/apps/nope']), equals(1));
        expect(fakeStdout.text, equals(responseBody));
        expect(
          fakeStderr.text,
          equals('shorebird: App not found (HTTP 404)\n'),
        );
      });

      test(
        'falls back to the status for a JSON body with no message',
        () async {
          responseStatus = HttpStatus.forbidden;
          responseBody = '{"code":"forbidden"}';
          expect(await runApi(['/x']), equals(1));
          expect(fakeStderr.text, equals('shorebird: HTTP 403\n'));
        },
      );

      test('falls back to the status for a non-JSON body', () async {
        responseStatus = HttpStatus.badGateway;
        responseHeaders = {'content-type': 'text/html'};
        responseBody = '<html>Bad Gateway</html>';
        expect(await runApi(['/x']), equals(1));
        expect(fakeStdout.text, equals(responseBody));
        expect(fakeStderr.text, equals('shorebird: HTTP 502\n'));
      });

      test('falls back to the status for invalid JSON', () async {
        responseStatus = HttpStatus.internalServerError;
        responseBody = 'oops';
        expect(await runApi(['/x']), equals(1));
        expect(fakeStderr.text, equals('shorebird: HTTP 500\n'));
      });

      test('reports a redirect as a failure', () async {
        responseStatus = HttpStatus.movedPermanently;
        responseBody = '';
        responseHeaders = {};
        expect(await runApi(['/x']), equals(1));
        expect(fakeStderr.text, equals('shorebird: HTTP 301\n'));
      });

      test('reports a connection failure', () async {
        when(
          () => codePushClient.send(any()),
        ).thenThrow(http.ClientException('Connection refused'));
        expect(await runApi(['/x']), equals(1));
        expect(fakeStderr.text, equals('shorebird: Connection refused\n'));
      });

      test('reports a socket failure', () async {
        when(
          () => codePushClient.send(any()),
        ).thenThrow(const SocketException('No route to host'));
        expect(await runApi(['/x']), equals(1));
        expect(fakeStderr.text, equals('shorebird: No route to host\n'));
      });
    });
  });

  group('addQuery', () {
    test('returns the URL unchanged without params', () {
      expect(addQuery('/x', {}), equals('/x'));
    });

    test('appends to an existing query string', () {
      expect(
        addQuery('/x?a=1', {'b': 'two words'}),
        equals('/x?a=1&b=two+words'),
      );
    });

    test('flattens nested maps and encodes null as empty', () {
      expect(
        addQuery('/x', {
          'outer': {'inner': true},
          'none': null,
        }),
        equals('/x?inner=true&none='),
      );
    });
  });

  group('canonicalHeaderName', () {
    test('capitalizes each hyphenated part', () {
      expect(canonicalHeaderName('x-request-ID'), equals('X-Request-Id'));
      expect(canonicalHeaderName('-odd--name'), equals('-Odd--Name'));
    });
  });

  group('redactAuthorization', () {
    test('masks the credential and keeps the scheme', () {
      expect(
        redactAuthorization('Bearer abc'),
        equals('Bearer ████████████████████'),
      );
      expect(redactAuthorization('abc'), equals('████████████████████'));
    });
  });
}

class _FakeStdout extends Fake implements Stdout {
  final _bytes = BytesBuilder();

  @override
  bool hasTerminal = false;

  String get text => utf8.decode(_bytes.toBytes());

  @override
  void add(List<int> data) => _bytes.add(data);

  @override
  void write(Object? object) => _bytes.add(utf8.encode('$object'));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

class _FakeStdin extends StreamView<List<int>> implements Stdin {
  _FakeStdin(List<int> bytes) : super(Stream.value(bytes));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
