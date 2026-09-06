import 'dart:io' as io;

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template api_keys_command}
/// `shorebird account api-keys`
/// Manage the API keys used to authenticate CI and scripts.
/// {@endtemplate}
class ApiKeysCommand extends ShorebirdCommand {
  /// {@macro api_keys_command}
  ApiKeysCommand() {
    addSubcommand(ApiKeysListCommand());
    addSubcommand(ApiKeysCreateCommand());
    addSubcommand(ApiKeysRevokeCommand());
  }

  @override
  String get name => 'api-keys';

  @override
  String get description =>
      'Manage API keys for CI and scripts.\n\n'
      'API keys authenticate non-interactive callers. Set one as the '
      '${lightCyan.wrap('SHOREBIRD_TOKEN')} environment variable in CI.\n\n'
      'These commands require an interactive login — an API key cannot '
      'manage API keys.';
}

/// {@template api_keys_list_command}
/// `shorebird account api-keys list`
/// List the current user's API keys.
/// {@endtemplate}
class ApiKeysListCommand extends ShorebirdCommand {
  /// {@macro api_keys_list_command}
  ApiKeysListCommand();

  @override
  String get name => 'list';

  @override
  String get description =>
      'List your API keys.\n\n'
      'Example output (space-separated: id  name  scope  created  last used):\n'
      '  7  Production CI  release-and-patch  2026-01-04  2026-09-06\n'
      '  9  Local scripts  full-access        2026-02-11  never\n\n'
      'Secrets are never listed — a key is shown once, when it is created.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird account api-keys list --json')}';

  @override
  Future<int> run() async {
    final List<ApiKeyMetadata> keys;
    try {
      keys = await auth.listApiKeys();
    } on Exception catch (error) {
      return _fail(error, 'Failed to list API keys.');
    }

    if (isJsonMode) {
      emitJsonSuccess({'api_keys': keys.map(_toJson).toList()});
      return ExitCode.success.code;
    }

    // Diagnostic, not content: `list` emits one line per key, so an empty
    // account should emit nothing a pipe can count. On stdout this line would
    // make `list | wc -l` report 1 key where there are none.
    if (keys.isEmpty) {
      io.stderr.writeln('No API keys.');
      return ExitCode.success.code;
    }

    for (final key in keys) {
      logger.info(
        '${key.id}  ${key.name}  ${key.scope?.flagName ?? 'unknown'}  '
        '${_formatDate(key.createdAt)}  '
        '${key.lastUsedAt == null ? 'never' : _formatDate(key.lastUsedAt!)}',
      );
    }
    return ExitCode.success.code;
  }
}

/// {@template api_keys_create_command}
/// `shorebird account api-keys create`
/// Create a new API key.
/// {@endtemplate}
class ApiKeysCreateCommand extends ShorebirdCommand {
  /// {@macro api_keys_create_command}
  ApiKeysCreateCommand() {
    argParser
      ..addOption(
        'name',
        help: 'A name for the key, so you can tell it apart later.',
        mandatory: true,
      )
      ..addOption(
        'scope',
        help: 'What the key is allowed to do.',
        allowed: ApiKeyScope.values.map((s) => s.flagName),
        allowedHelp: {
          ApiKeyScope.releaseAndPatch.flagName:
              'Create releases and patches, and read insights. No deletes, '
              'no member management, no billing. Use this for CI.',
          ApiKeyScope.fullAccess.flagName:
              'Everything your account can do, in every organization you '
              'belong to.',
        },
        mandatory: true,
      )
      ..addOption(
        'expires-in-days',
        help:
            'Days until the key expires (1-3650). Omit for a key that '
            'never expires.',
      );
  }

  @override
  String get name => 'create';

  @override
  String get description =>
      'Create an API key.\n\n'
      'The key is shown once and cannot be retrieved again.\n\n'
      'The key is written to stdout on its own; everything else goes to '
      'stderr, so the command pipes cleanly:\n'
      '  shorebird account api-keys create --name CI '
      '--scope release-and-patch | pbcopy\n\n'
      '${ShorebirdCommand.jsonHint(_createJsonExample)}';

  @override
  Future<int> run() async {
    final scopeFlag = results['scope'] as String;
    final scope = ApiKeyScope.values.firstWhere(
      (s) => s.flagName == scopeFlag,
    );

    final expiresInDaysArg = results['expires-in-days'] as String?;
    int? expiresInDays;
    if (expiresInDaysArg != null) {
      expiresInDays = int.tryParse(expiresInDaysArg);
      if (expiresInDays == null || expiresInDays < 1 || expiresInDays > 3650) {
        if (isJsonMode) {
          emitJsonError(
            code: JsonErrorCode.usageError,
            message: _expiresInDaysUsage,
          );
        } else {
          logger.err(_expiresInDaysUsage);
        }
        return ExitCode.usage.code;
      }
    }

    final ({String secret, ApiKeyMetadata metadata}) created;
    try {
      created = await auth.createApiKey(
        name: results['name'] as String,
        scope: scope,
        expiresInDays: expiresInDays,
      );
    } on Exception catch (error) {
      return _fail(error, 'Failed to create the API key.');
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'api_key': created.secret,
        ..._toJson(created.metadata),
      });
      return ExitCode.success.code;
    }

    // The key is content; everything around it is diagnostic. Content goes to
    // stdout by itself so the command composes —
    //
    //   shorebird account api-keys create … | op item create …
    //
    // gets the key and nothing else. The guidance goes to stderr, where a
    // human still reads it and a pipe never sees it. Same split the logger
    // already applies to progress ("progress is diagnostic, never content"),
    // and the same shape as `gh auth token` and `kubectl create token`.
    io.stdout.writeln(created.secret);
    io.stderr
      ..writeln()
      ..writeln('Created "${created.metadata.name}" (${scope.flagName}).')
      ..writeln(
        'This is the only time the key will be shown. In CI, set it as the '
        'SHOREBIRD_TOKEN environment variable.',
      );
    return ExitCode.success.code;
  }
}

/// {@template api_keys_revoke_command}
/// `shorebird account api-keys revoke`
/// Revoke an API key.
/// {@endtemplate}
class ApiKeysRevokeCommand extends ShorebirdCommand {
  /// {@macro api_keys_revoke_command}
  ApiKeysRevokeCommand() {
    argParser.addOption(
      'id',
      help:
          'The id of the key to revoke, as shown by '
          '`shorebird account api-keys list`.',
      mandatory: true,
    );
  }

  @override
  String get name => 'revoke';

  @override
  String get description =>
      'Revoke an API key.\n\n'
      'Takes effect immediately and cannot be undone. Anything using the key '
      'will start failing.\n\n'
      '${ShorebirdCommand.jsonHint(_revokeJsonExample)}';

  @override
  Future<int> run() async {
    final id = results['id'] as String;
    try {
      await auth.revokeApiKey(id: id);
    } on Exception catch (error) {
      return _fail(error, 'Failed to revoke the API key.');
    }

    if (isJsonMode) {
      emitJsonSuccess({'revoked': id});
      return ExitCode.success.code;
    }

    logger.info('Revoked API key $id.');
    return ExitCode.success.code;
  }
}

extension on ShorebirdCommand {
  /// Reports [error] on whichever output channel is active and returns the
  /// exit code to use.
  ///
  /// [fallback] describes the operation, for exceptions that carry no message
  /// worth surfacing on their own.
  int _fail(Exception error, String fallback) {
    final message = switch (error) {
      ApiKeySessionRequiredException() => error.toString(),
      ApiKeyScopeMismatchException() => error.toString(),
      ApiKeyRequestException() => '$fallback ${error.message}',
      _ => fallback,
    };
    _emitError(message);
    return ExitCode.software.code;
  }

  /// Emits [message] as an error on whichever output channel is active.
  void _emitError(String message) {
    if (isJsonMode) {
      emitJsonError(code: JsonErrorCode.fetchFailed, message: message);
    } else {
      logger.err(message);
    }
  }
}

/// The `--json` example shown in `api-keys create` help.
const _createJsonExample = 'shorebird account api-keys create --json';

/// The `--json` example shown in `api-keys revoke` help.
const _revokeJsonExample = 'shorebird account api-keys revoke --json';

/// The message shown when `--expires-in-days` is outside the range the auth
/// service accepts.
const _expiresInDaysUsage =
    '--expires-in-days must be a whole number from 1 to 3650.';

Map<String, Object?> _toJson(ApiKeyMetadata key) => {
  'id': key.id,
  'name': key.name,
  'scope': key.scope?.wireName,
  'created_at': key.createdAt.toIso8601String(),
  'last_used_at': key.lastUsedAt?.toIso8601String(),
  'expires_at': key.expiresAt?.toIso8601String(),
};

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
