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
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
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

    // Whether the shared client would have retried the request.
    bool? retriesEnabled;

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
      when(() => logger.level).thenReturn(Level.info);
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
      retriesEnabled = null;
      when(() => codePushClient.send(any())).thenAnswer((_) async {
        retriesEnabled = read(retryFailedRequestsRef, orElse: () => true);
        return http.StreamedResponse(
          Stream.value(utf8.encode(responseBody)),
          responseStatus,
          headers: responseHeaders,
          reasonPhrase: responseStatus == HttpStatus.ok ? 'OK' : null,
        );
      });
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
        const ShorebirdYaml(appId: appId, flavors: {'prod': prodAppId}),
      );
    });

    Matcher usageError(String message) => throwsA(
      isA<UsageException>().having(
        (e) => e.message,
        'message',
        contains(message),
      ),
    );

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
      for (final text in [
        'https://api.shorebird.dev/openapi.json',
        'https://docs.shorebird.dev/account/api/',
        'no compatibility guarantee',
        r'$ shorebird api /apps',
        r"$ shorebird api /apps/{appId}/releases --jq '.releases[].version'",
        '-f channel=beta',
        '.[1:3]',
        'pass --method GET',
      ]) {
        expect(command.description, contains(text));
      }
    });

    group('argument validation', () {
      test('requires exactly one endpoint', () async {
        await expectLater(runApi([]), usageError('exactly one <endpoint>'));
        await expectLater(
          runApi(['/apps', '/organizations']),
          usageError('exactly one <endpoint>'),
        );
        verifyNever(() => codePushClient.send(any()));
      });

      test('rejects --json', () async {
        await expectLater(
          runApi(['/apps'], jsonMode: true),
          usageError('does not support --json'),
        );
      });

      test('rejects an unsupported --jq expression before sending', () async {
        await expectLater(
          runApi(['/apps', '--jq', 'group_by(.a)']),
          usageError('--jq: unsupported jq function or keyword "group_by"'),
        );
        verifyNever(() => codePushClient.send(any()));
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

      test('prints the login hints to stderr, not stdout', () async {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          ),
        ).thenAnswer((_) async {
          read(loggerRef).info('Run shorebird login to sign in.');
          throw UserNotAuthorizedException();
        });

        expect(await runApi(['/apps']), equals(ExitCode.noUser.code));
        expect(fakeStdout.text, isEmpty);
        expect(fakeStderr.text, equals('Run shorebird login to sign in.\n'));
      });
    });

    group('with --verbose', () {
      setUp(() {
        when(() => logger.level).thenReturn(Level.verbose);
        when(() => codePushClient.send(any())).thenAnswer((_) async {
          // As LoggingClient does for each request.
          read(loggerRef).detail('[HTTP] GET /apps');
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
        });
      });

      test('logs requests to stderr, not stdout', () async {
        expect(await runApi(['/apps']), equals(ExitCode.success.code));
        expect(fakeStdout.text, equals('{}'));
        expect(fakeStderr.text, contains('[HTTP] GET /apps'));
      });
    });

    group('when a token refresh fails', () {
      setUp(() {
        when(() => codePushClient.send(any())).thenAnswer((_) async {
          // As AuthenticatedClient does when the refresh is rejected.
          read(loggerRef).info('Run shorebird login to log in again.');
          throw ProcessExit(ExitCode.software.code);
        });
      });

      test('prints the login hint to stderr, not stdout', () async {
        await expectLater(runApi(['/apps']), throwsA(isA<ProcessExit>()));
        expect(fakeStdout.text, isEmpty);
        expect(
          fakeStderr.text,
          equals('Run shorebird login to log in again.\n'),
        );
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

      group('as a full URL', () {
        test('is used as its path when under the API base URI', () async {
          await runApi([
            'https://api.shorebird.dev/api/v1/apps/{appId}/releases?x=1',
          ]);
          expect(
            sentRequest().url,
            equals(
              Uri.parse(
                'https://api.shorebird.dev/api/v1/apps/$appId/releases?x=1',
              ),
            ),
          );
        });

        test('may be the API base URI itself', () async {
          await runApi(['https://api.shorebird.dev/api/v1']);
          expect(
            sentRequest().url,
            equals(Uri.parse('https://api.shorebird.dev/api/v1/')),
          );
        });

        test('follows the configured hosted URL', () async {
          when(
            () => codePushClient.apiBaseUri,
          ).thenReturn(Uri.parse('http://localhost:8080/api/v1'));
          await runApi(['http://localhost:8080/api/v1/apps']);
          expect(
            sentRequest().url,
            equals(Uri.parse('http://localhost:8080/api/v1/apps')),
          );
        });

        for (final url in [
          'https://example.com/api/v1/apps',
          'https://api.shorebird.dev.example.com/api/v1/apps',
          'http://api.shorebird.dev/api/v1/apps',
          'https://api.shorebird.dev/openapi.json',
          'https://api.shorebird.dev/api/v10/apps',
        ]) {
          test('rejects $url without sending it', () async {
            await expectLater(
              runApi([url]),
              usageError(
                'Only URLs under https://api.shorebird.dev/api/v1 are '
                'accepted',
              ),
            );
            verifyNever(() => codePushClient.send(any()));
          });
        }
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
            usageError('does not have a flavor named "staging"'),
          );
        });

        test('does not need shorebird.yaml when unused', () async {
          when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
          expect(await runApi(['/apps']), equals(ExitCode.success.code));
        });

        test(
          'without shorebird.yaml is a usage error naming the fix',
          () async {
            when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
            await expectLater(
              runApi(['/apps/{appId}']),
              usageError('put the app ID in the endpoint'),
            );
            verifyNever(() => codePushClient.send(any()));
          },
        );
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
        await runApi(['/x', '-f', 'a=1', '-f', 'b=true', '-f', 'c=x=y,z']);
        expect(
          jsonDecode(sentRequest().body),
          equals({'a': '1', 'b': 'true', 'c': 'x=y,z'}),
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
          '-f',
          'raw={appId}',
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
            'raw': '{appId}',
          }),
        );
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
          usageError('--field: no file found at missing.txt'),
        );
      });

      test('must be in key=value format', () async {
        await expectLater(
          runApi(['/x', '-f', 'channel']),
          usageError('field "channel" must be in key=value format'),
        );
        await expectLater(
          runApi(['/x', '-F', '=x']),
          usageError('field "=x" must be in key=value format'),
        );
      });

      test('become the query string for GET', () async {
        await runApi([
          '-X',
          'GET',
          '/apps/{appId}/metrics/patch-installs?group_by=release',
          '-f',
          'granularity=day',
          '-F',
          'limit=5',
          '-F',
          'none=null',
        ]);
        final request = sentRequest();
        expect(request.method, equals('GET'));
        expect(request.bodyBytes, isEmpty);
        expect(
          request.url.query,
          equals('group_by=release&granularity=day&limit=5&none='),
        );
      });

      test('keep an explicit --method', () async {
        await runApi(['-X', 'patch', '/x', '-f', 'a=b']);
        expect(sentRequest().method, equals('PATCH'));
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
        expect(
          request.headers['content-type'],
          equals('application/json; charset=utf-8'),
        );
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
          usageError('--input: no file found at missing.json'),
        );
      });
    });

    group('retries', () {
      test('are left on for GET', () async {
        await runApi(['/apps']);
        expect(retriesEnabled, isTrue);
      });

      test('are turned off for other methods', () async {
        await runApi(['/apps/{appId}/channels', '-f', 'channel=beta']);
        expect(retriesEnabled, isFalse);
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

      test('prints nothing for 204 No Content', () async {
        responseStatus = HttpStatus.noContent;
        responseBody = '';
        expect(
          await runApi(['-X', 'DELETE', '/x']),
          equals(ExitCode.success.code),
        );
        expect(fakeStdout.text, isEmpty);
      });
    });

    group('--jq', () {
      setUp(() {
        responseBody = jsonEncode([
          {
            'version': '1.0.0',
            'id': 1,
            'tags': ['a'],
          },
          {'version': '1.0.1', 'id': 2, 'tags': <String>[]},
        ]);
      });

      test('prints strings raw and other values as compact JSON', () async {
        expect(
          await runApi(['/x', '--jq', '.[] | .version, .tags']),
          equals(ExitCode.success.code),
        );
        expect(fakeStdout.text, equals('1.0.0\n["a"]\n1.0.1\n[]\n'));
      });

      test('indents JSON results when stdout is a terminal', () async {
        fakeStdout.hasTerminal = true;
        await runApi(['/x', '-q', '.[0] | {id}']);
        expect(fakeStdout.text, equals('{\n  "id": 1\n}\n'));
      });

      test('reports an evaluation error and exits 1', () async {
        expect(await runApi(['/x', '--jq', '.foo']), equals(1));
        expect(
          fakeStderr.text,
          equals('shorebird: --jq: Cannot index array with "foo"\n'),
        );
      });

      test('reports a response that is not JSON', () async {
        responseBody = 'plain';
        expect(await runApi(['/x', '--jq', '.']), equals(1));
        expect(
          fakeStderr.text,
          equals('shorebird: --jq: the response is not JSON\n'),
        );
      });

      test('is not applied to an error response', () async {
        responseStatus = HttpStatus.notFound;
        responseBody = '{"message":"App not found"}';
        expect(await runApi(['/x', '--jq', '.message']), equals(1));
        expect(fakeStdout.text, equals(responseBody));
        expect(
          fakeStderr.text,
          equals('shorebird: App not found (HTTP 404)\n'),
        );
      });
    });

    group('when the path repeats the base path', () {
      test('requests the route under the base and says so', () async {
        expect(await runApi(['/api/v1/apps']), equals(0));
        expect(
          sentRequest().url,
          equals(Uri.parse('https://api.shorebird.dev/api/v1/apps')),
        );
        expect(
          fakeStderr.text,
          equals(
            'shorebird: Endpoints are relative to '
            'https://api.shorebird.dev/api/v1, so requesting "/apps" rather '
            'than "/api/v1/apps".\n',
          ),
        );
      });

      test('accepts it without a leading slash', () async {
        expect(await runApi(['api/v1/apps']), equals(0));
        expect(
          sentRequest().url,
          equals(Uri.parse('https://api.shorebird.dev/api/v1/apps')),
        );
      });

      test('leaves a path that only starts with the same text', () async {
        expect(await runApi(['/api/v10']), equals(0));
        expect(
          sentRequest().url,
          equals(Uri.parse('https://api.shorebird.dev/api/v1/api/v10')),
        );
        expect(fakeStderr.text, isEmpty);
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

      group('with 405 Method Not Allowed', () {
        setUp(() {
          responseStatus = HttpStatus.methodNotAllowed;
          responseBody =
              '{"message":"This route does not accept the request method."}';
        });

        const error =
            'shorebird: This route does not accept the request method. '
            '(HTTP 405)\n';
        const hint =
            'shorebird: Fields switch the default method to POST. For a GET '
            'with query parameters, add --method GET or put them in the '
            'URL.\n';

        test('hints at --method GET when fields made it a POST', () async {
          expect(await runApi(['/x', '-f', 'order=desc']), equals(1));
          expect(sentRequest().method, equals('POST'));
          expect(fakeStderr.text, equals('$error$hint'));
        });

        test('does not hint when the method was set explicitly', () async {
          expect(
            await runApi(['-X', 'POST', '/x', '-F', 'order=desc']),
            equals(1),
          );
          expect(fakeStderr.text, equals(error));
        });

        test('does not hint without fields', () async {
          expect(await runApi(['/x']), equals(1));
          expect(fakeStderr.text, equals(error));
        });

        test('does not hint when --input made it a POST', () async {
          File('body.json').writeAsStringSync('{}');
          expect(
            await runApi(['/x', '--input', 'body.json', '-f', 'a=b']),
            equals(1),
          );
          expect(fakeStderr.text, equals(error));
        });
      });

      test('does not hint on other errors from a field POST', () async {
        responseStatus = HttpStatus.notFound;
        responseBody = '{"message":"App not found"}';
        expect(await runApi(['/x', '-f', 'a=b']), equals(1));
        expect(
          fakeStderr.text,
          equals('shorebird: App not found (HTTP 404)\n'),
        );
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
}

class _FakeStdout extends Fake implements Stdout {
  final _bytes = BytesBuilder();

  @override
  bool hasTerminal = false;

  @override
  bool get supportsAnsiEscapes => false;

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
