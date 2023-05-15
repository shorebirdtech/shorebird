import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group('delete', () {
    const appId = 'test-app-id';
    const channelName = 'my-channel';
    const channel = Channel(id: 0, appId: appId, name: channelName);

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late DeleteChannelsCommand command;

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();
      command = DeleteChannelsCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          return codePushClient;
        },
        logger: logger,
      )..testArgResults = argResults;

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['name']).thenReturn(channelName);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [channel]);
      when(
        () => codePushClient.deleteChannel(channelId: any(named: 'channelId')),
      ).thenAnswer((_) async {});
    });

    test('description is correct', () {
      expect(
        command.description,
        equals('Delete an existing channel for a Shorebird app.'),
      );
    });

    test('returns ExitCode.noUser when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      expect(await command.run(), ExitCode.noUser.code);
    });

    test('returns ExitCode.usage when app id is missing.', () async {
      when(() => argResults['app-id']).thenReturn(null);
      expect(await command.run(), ExitCode.usage.code);
    });

    test('returns ExitCode.success when user aborts', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      expect(await command.run(), ExitCode.success.code);
      verifyNever(
        () => codePushClient.deleteChannel(
          channelId: any(named: 'channelId'),
        ),
      );
      verify(() => logger.info('Aborted.')).called(1);
    });

    test('returns ExitCode.software when fetching channels fails', () async {
      const error = 'oops something went wrong';
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenThrow(error);
      expect(await command.run(), ExitCode.software.code);
      verify(() => logger.err(error)).called(1);
    });

    test('returns ExitCode.software when channel does not exist', () async {
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      expect(await command.run(), ExitCode.software.code);
      verify(
        () => logger.err(
          any(
            that: contains(
              'Could not find a channel with the name "$channelName".',
            ),
          ),
        ),
      ).called(1);
    });

    test('returns ExitCode.software when deleting a channel fails', () async {
      const error = 'oops something went wrong';
      when(
        () => codePushClient.deleteChannel(channelId: any(named: 'channelId')),
      ).thenThrow(error);
      expect(await command.run(), ExitCode.software.code);
      verify(() => logger.err(error)).called(1);
    });

    test('prompts for channel name when not provided', () async {
      when(() => argResults['name']).thenReturn(null);
      when(() => logger.prompt(any())).thenReturn(channelName);
      when(
        () => codePushClient.deleteChannel(channelId: any(named: 'channelId')),
      ).thenAnswer((_) async => channel);
      expect(await command.run(), ExitCode.success.code);
      verify(
        () => logger.prompt(
          '''${lightGreen.wrap('?')} What is the name of the channel you would like to delete?''',
        ),
      ).called(1);
      verify(
        () => codePushClient.deleteChannel(channelId: channel.id),
      ).called(1);
    });

    test('returns ExitCode.success on success', () async {
      when(
        () => codePushClient.deleteChannel(channelId: any(named: 'channelId')),
      ).thenAnswer((_) async => channel);
      expect(await command.run(), ExitCode.success.code);
      verify(() => logger.success('\n✅ Channel Deleted!')).called(1);
    });
  });
}
