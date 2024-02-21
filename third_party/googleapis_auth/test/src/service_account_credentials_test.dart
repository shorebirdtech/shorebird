import 'package:googleapis_auth/src/service_account_credentials.dart';
import 'package:test/test.dart';

void main() {
  group(ServiceAccountCredentials, () {
    group('fromJson', () {
      test('throws exception if json is not a map', () {
        expect(
          () => ServiceAccountCredentials.fromJson('[1,2,3]'),
          throwsArgumentError,
        );
      });

      test('throws exception if json is not a service account', () {
        expect(
          () => ServiceAccountCredentials.fromJson({
            'type': 'not_service_account',
            'client_id': 'client_id',
            'private_key': 'private_key',
            'client_email': 'client_email',
          }),
          throwsArgumentError,
        );
      });

      test('throws exception if json is missing fields', () {
        expect(
          () => ServiceAccountCredentials.fromJson({
            'type': 'service_account',
            'client_id': 'client_id',
          }),
          throwsArgumentError,
        );
      });
    });
  });
}
