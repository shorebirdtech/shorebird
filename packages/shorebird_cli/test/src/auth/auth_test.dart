import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:test/test.dart';

void main() {
  group('Auth', () {
    const apiKey = 'test-api-key';
    const projectId = 'test-project-id';

    late Auth auth;

    setUp(() {
      auth = Auth()..logout();
    });

    group('login', () {
      test('should set the current session', () {
        auth.login(apiKey: apiKey, projectId: projectId);
        expect(
          auth.currentSession,
          isA<Session>()
              .having((s) => s.apiKey, 'apiKey', apiKey)
              .having((s) => s.projectId, 'projectId', projectId),
        );
        expect(
          Auth().currentSession,
          isA<Session>()
              .having((s) => s.apiKey, 'apiKey', apiKey)
              .having((s) => s.projectId, 'projectId', projectId),
        );
      });
    });

    group('logout', () {
      test('clears session and wipes state', () {
        auth.login(apiKey: apiKey, projectId: projectId);
        expect(
          auth.currentSession,
          isA<Session>()
              .having((s) => s.apiKey, 'apiKey', apiKey)
              .having((s) => s.projectId, 'projectId', projectId),
        );

        auth.logout();
        expect(auth.currentSession, isNull);
        expect(Auth().currentSession, isNull);
      });
    });
  });
}
