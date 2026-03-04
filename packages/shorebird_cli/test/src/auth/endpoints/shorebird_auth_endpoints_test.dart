import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/endpoints/shorebird_auth_endpoints.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(ShorebirdAuthEndpoints, () {
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdAuthEndpoints endpoints;

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      when(
        () => shorebirdEnv.authServiceUri,
      ).thenReturn(Uri.parse('https://auth.shorebird.dev'));
      endpoints = ShorebirdAuthEndpoints();
    });

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    test('is an AuthEndpoints', () {
      expect(endpoints, isA<AuthEndpoints>());
    });

    test('authorizationEndpoint returns correct URI', () {
      runWithOverrides(() {
        expect(
          endpoints.authorizationEndpoint,
          equals(Uri.parse('https://auth.shorebird.dev/login')),
        );
      });
    });

    test('tokenEndpoint returns correct URI', () {
      runWithOverrides(() {
        expect(
          endpoints.tokenEndpoint,
          equals(Uri.parse('https://auth.shorebird.dev/token')),
        );
      });
    });
  });
}
