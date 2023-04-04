import 'package:shorebird_cli/src/auth/jwt.dart';
import 'package:test/test.dart';

void main() {
  group('Jwt', () {
    group('decodeClaims', () {
      test('returns null jwt does not contain 3 segments', () {
        expect(Jwt.decodeClaims('invalid'), isNull);
      });

      test('returns null when jwt payload segment is malformed', () {
        expect(Jwt.decodeClaims('this.is.invalid'), isNull);
      });

      test('returns correct claims when jwt payload segment is valid', () {
        expect(
          Jwt.decodeClaims(
            '''eyJhbGciOiJSUzI1NiIsImN0eSI6IkpXVCJ9.eyJlbWFpbCI6InRlc3RAZW1haWwuY29tIn0.pD47BhF3MBLyIpfsgWCzP9twzC1HJxGukpcR36DqT6yfiOMHTLcjDbCjRLAnklWEHiT0BQTKTfhs8IousU90Fm5bVKObudfKu8pP5iZZ6Ls4ohDjTrXky9j3eZpZjwv8CnttBVgRfMJG-7YASTFRYFcOLUpnb4Zm5R6QdoCDUYg''',
          ),
          equals({'email': 'test@email.com'}),
        );
      });
    });
  });
}
