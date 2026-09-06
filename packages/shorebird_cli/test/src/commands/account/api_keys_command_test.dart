import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/account/api_keys_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 4);
  final lastUsedAt = DateTime.utc(2026, 9, 6);

  final ciKey = ApiKeyMetadata(
    id: '7',
    name: 'Production CI',
    createdAt: createdAt,
    lastUsedAt: lastUsedAt,
    scope: ApiKeyScope.releaseAndPatch,
  );
  final unusedKey = ApiKeyMetadata(
    id: '9',
    name: 'Local scripts',
    createdAt: createdAt,
    scope: ApiKeyScope.fullAccess,
  );

  late Auth auth;
  late ShorebirdLogger logger;
  late ArgResults argResults;

  R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
    return runScoped(
      body,
      values: {
        authRef.overrideWith(() => auth),
        isJsonModeRef.overrideWith(() => jsonMode),
        loggerRef.overrideWith(() => logger),
      },
    );
  }

  setUpAll(() {
    registerFallbackValue(ApiKeyScope.fullAccess);
  });

  setUp(() {
    auth = MockAuth();
    logger = MockShorebirdLogger();
    argResults = MockArgResults();
  });

  group(ApiKeysCommand, () {
    test('registers list, create and revoke subcommands', () {
      final command = runWithOverrides(ApiKeysCommand.new);
      expect(
        command.subcommands.keys,
        containsAll(<String>['list', 'create', 'revoke']),
      );
    });

    test('has a name and a description', () {
      final command = runWithOverrides(ApiKeysCommand.new);
      expect(command.name, equals('api-keys'));
      expect(command.description, isNotEmpty);
    });
  });

  group(ApiKeysListCommand, () {
    late ApiKeysListCommand command;

    setUp(() {
      command = runWithOverrides(ApiKeysListCommand.new)
        ..testArgResults = argResults;
    });

    test('lists each key with its scope and dates', () async {
      when(auth.listApiKeys).thenAnswer((_) async => [ciKey, unusedKey]);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info(
          '7  Production CI  release-and-patch  2026-01-04  2026-09-06',
        ),
      ).called(1);
      verify(
        () => logger.info(
          '9  Local scripts  full-access  2026-01-04  never',
        ),
      ).called(1);
    });

    test('reports an unknown scope rather than guessing', () async {
      when(auth.listApiKeys).thenAnswer(
        (_) async => [
          ApiKeyMetadata(id: '1', name: 'Old', createdAt: createdAt),
        ],
      );

      await runWithOverrides(command.run);

      verify(
        () => logger.info('1  Old  unknown  2026-01-04  never'),
      ).called(1);
    });

    test('says so when there are no keys', () async {
      when(auth.listApiKeys).thenAnswer((_) async => []);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('No API keys.')).called(1);
    });

    test('emits JSON when --json is set', () async {
      when(auth.listApiKeys).thenAnswer((_) async => [ciKey]);

      final captured = <String>[];
      await captureStdout(
        () => runWithOverrides(command.run, jsonMode: true),
        captured: captured,
      );

      final output = json.decode(captured.join()) as Map<String, dynamic>;
      final keys =
          (output['data'] as Map<String, dynamic>)['api_keys'] as List<dynamic>;
      final first = keys.single as Map<String, dynamic>;
      expect(first['id'], equals('7'));
      expect(first['scope'], equals('release_and_patch'));
      expect(first['expires_at'], isNull);
    });

    test('explains that a session is required when there is none', () async {
      when(auth.listApiKeys).thenThrow(
        const ApiKeySessionRequiredException(),
      );

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err(
          any(that: contains('requires an interactive login')),
        ),
      ).called(1);
    });

    test('surfaces the auth service message on failure', () async {
      when(auth.listApiKeys).thenThrow(
        const ApiKeyRequestException('nope'),
      );

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err('Failed to list API keys. nope'),
      ).called(1);
    });

    test('falls back to a generic message for other exceptions', () async {
      when(auth.listApiKeys).thenThrow(Exception('boom'));

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.err('Failed to list API keys.')).called(1);
    });
  });

  group(ApiKeysCreateCommand, () {
    late ApiKeysCreateCommand command;

    setUp(() {
      command = runWithOverrides(ApiKeysCreateCommand.new)
        ..testArgResults = argResults;
      when(() => argResults['name']).thenReturn('Production CI');
      when(() => argResults['scope']).thenReturn('release-and-patch');
      when(() => argResults['expires-in-days']).thenReturn(null);
    });

    test('writes the key alone to stdout so it pipes cleanly', () async {
      when(
        () => auth.createApiKey(
          name: any(named: 'name'),
          scope: any(named: 'scope'),
          expiresInDays: any(named: 'expiresInDays'),
        ),
      ).thenAnswer((_) async => (secret: 'sb_api_abc', metadata: ciKey));

      final out = <String>[];
      final err = <String>[];
      final result = await captureStdout(
        () => runWithOverrides(command.run),
        captured: out,
        stderrCaptured: err,
      );

      expect(result, equals(ExitCode.success.code));
      // Everything a pipe receives, and nothing else.
      expect(out.join().trim(), equals('sb_api_abc'));
    });

    test('keeps the guidance on stderr, out of the pipe', () async {
      when(
        () => auth.createApiKey(
          name: any(named: 'name'),
          scope: any(named: 'scope'),
          expiresInDays: any(named: 'expiresInDays'),
        ),
      ).thenAnswer((_) async => (secret: 'sb_api_abc', metadata: ciKey));

      final out = <String>[];
      final err = <String>[];
      await captureStdout(
        () => runWithOverrides(command.run),
        captured: out,
        stderrCaptured: err,
      );

      final diagnostics = err.join();
      expect(diagnostics, contains('SHOREBIRD_TOKEN'));
      expect(diagnostics, contains('Production CI'));
      expect(diagnostics, contains('release-and-patch'));
      // The secret must never appear on the diagnostic channel.
      expect(diagnostics, isNot(contains('sb_api_abc')));
    });

    test('passes the requested scope and expiry through', () async {
      when(() => argResults['expires-in-days']).thenReturn('90');
      when(
        () => auth.createApiKey(
          name: any(named: 'name'),
          scope: any(named: 'scope'),
          expiresInDays: any(named: 'expiresInDays'),
        ),
      ).thenAnswer((_) async => (secret: 'sb_api_abc', metadata: ciKey));

      await runWithOverrides(command.run);

      verify(
        () => auth.createApiKey(
          name: 'Production CI',
          scope: ApiKeyScope.releaseAndPatch,
          expiresInDays: 90,
        ),
      ).called(1);
    });

    test('rejects a non-numeric --expires-in-days', () async {
      when(() => argResults['expires-in-days']).thenReturn('soon');

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.usage.code));
      verify(
        () => logger.err(any(that: contains('whole number from 1 to 3650'))),
      ).called(1);
      verifyNever(
        () => auth.createApiKey(
          name: any(named: 'name'),
          scope: any(named: 'scope'),
          expiresInDays: any(named: 'expiresInDays'),
        ),
      );
    });

    test('rejects an --expires-in-days outside the accepted range', () async {
      when(() => argResults['expires-in-days']).thenReturn('4000');

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.usage.code));
    });

    test('reports a usage error as JSON when --json is set', () async {
      when(() => argResults['expires-in-days']).thenReturn('0');

      final captured = <String>[];
      await captureStdout(
        () => runWithOverrides(command.run, jsonMode: true),
        captured: captured,
      );

      final output = json.decode(captured.join()) as Map<String, dynamic>;
      expect(output['status'], equals('error'));
      expect(
        (output['error'] as Map<String, dynamic>)['code'],
        equals('usage_error'),
      );
    });

    test('emits the secret as JSON when --json is set', () async {
      when(
        () => auth.createApiKey(
          name: any(named: 'name'),
          scope: any(named: 'scope'),
          expiresInDays: any(named: 'expiresInDays'),
        ),
      ).thenAnswer((_) async => (secret: 'sb_api_abc', metadata: ciKey));

      final captured = <String>[];
      await captureStdout(
        () => runWithOverrides(command.run, jsonMode: true),
        captured: captured,
      );

      final output = json.decode(captured.join()) as Map<String, dynamic>;
      final data = output['data'] as Map<String, dynamic>;
      expect(data['api_key'], equals('sb_api_abc'));
      expect(data['scope'], equals('release_and_patch'));
    });

    test('fails loudly when the server widened the scope', () async {
      when(
        () => auth.createApiKey(
          name: any(named: 'name'),
          scope: any(named: 'scope'),
          expiresInDays: any(named: 'expiresInDays'),
        ),
      ).thenThrow(
        const ApiKeyScopeMismatchException(
          requested: ApiKeyScope.releaseAndPatch,
          granted: ApiKeyScope.fullAccess,
        ),
      );

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err(any(that: contains('revoke it'))),
      ).called(1);
    });
  });

  group(ApiKeysRevokeCommand, () {
    late ApiKeysRevokeCommand command;

    setUp(() {
      command = runWithOverrides(ApiKeysRevokeCommand.new)
        ..testArgResults = argResults;
      when(() => argResults['id']).thenReturn('7');
    });

    test('revokes the requested key', () async {
      when(() => auth.revokeApiKey(id: any(named: 'id'))).thenAnswer(
        (_) async {},
      );

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(() => auth.revokeApiKey(id: '7')).called(1);
      verify(() => logger.info('Revoked API key 7.')).called(1);
    });

    test('emits JSON when --json is set', () async {
      when(() => auth.revokeApiKey(id: any(named: 'id'))).thenAnswer(
        (_) async {},
      );

      final captured = <String>[];
      await captureStdout(
        () => runWithOverrides(command.run, jsonMode: true),
        captured: captured,
      );

      final output = json.decode(captured.join()) as Map<String, dynamic>;
      expect(
        (output['data'] as Map<String, dynamic>)['revoked'],
        equals('7'),
      );
    });

    test('reports failure', () async {
      when(() => auth.revokeApiKey(id: any(named: 'id'))).thenThrow(
        const ApiKeyRequestException('not found'),
      );

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err('Failed to revoke the API key. not found'),
      ).called(1);
    });
  });
}
