import 'package:shorebird_cli/src/executables/devicectl/nserror.dart';
import 'package:test/test.dart';

void main() {
  group(NSError, () {
    test('(de)serialization', () {
      const error = NSError(
        code: 1,
        domain: 'com.example',
        userInfo: UserInfo(
          description: StringContainer('description'),
          localizedDescription: StringContainer('localizedDescription'),
          localizedFailureReason: StringContainer('localizedFailureReason'),
        ),
      );

      final json = error.toJson();
      final decoded = NSError.fromJson(json);

      expect(decoded, error);
    });

    group('toString', () {
      test('returns a string representation of the error', () {
        const error = NSError(
          code: 1,
          domain: 'com.example',
          userInfo: UserInfo(
            description: StringContainer('description'),
            localizedDescription: StringContainer('localizedDescription'),
            localizedFailureReason: StringContainer('localizedFailureReason'),
          ),
        );

        expect(error.toString(), '''
NSError(
  code: 1,
  domain: com.example,
  userInfo: UserInfo(
  description: description,
  localizedDescription: localizedDescription,
  localizedFailureReason: localizedFailureReason,
  underlyingError: null
)
)''');
      });
    });
  });

  group(UserInfo, () {
    test('(de)serialization', () {
      const userInfo = UserInfo(
        description: StringContainer('description'),
        localizedDescription: StringContainer('localizedDescription'),
        localizedFailureReason: StringContainer('localizedFailureReason'),
      );

      final json = userInfo.toJson();
      final decoded = UserInfo.fromJson(json);

      expect(decoded, userInfo);
    });

    group('toString', () {
      test('returns a string representation of the user info', () {
        const userInfo = UserInfo(
          description: StringContainer('description'),
          localizedDescription: StringContainer('localizedDescription'),
          localizedFailureReason: StringContainer('localizedFailureReason'),
        );

        expect(userInfo.toString(), '''
UserInfo(
  description: description,
  localizedDescription: localizedDescription,
  localizedFailureReason: localizedFailureReason,
  underlyingError: null
)''');
      });
    });
  });

  group(StringContainer, () {
    test('(de)serialization', () {
      const stringContainer = StringContainer('string');

      final json = stringContainer.toJson();
      final decoded = StringContainer.fromJson(json);

      expect(decoded, stringContainer);
    });

    group('toString', () {
      test('returns a string representation of the string container', () {
        const stringContainer = StringContainer('string');

        expect(stringContainer.toString(), 'string');
      });
    });
  });

  group(NSUnderlyingError, () {
    test('(de)serialization', () {
      const underlyingError = NSUnderlyingError(
        error: NSError(
          code: 1,
          domain: 'com.example',
          userInfo: UserInfo(
            description: StringContainer('description'),
            localizedDescription: StringContainer('localizedDescription'),
            localizedFailureReason: StringContainer('localizedFailureReason'),
          ),
        ),
      );

      final json = underlyingError.toJson();
      final decoded = NSUnderlyingError.fromJson(json);

      expect(decoded, underlyingError);
    });

    group('toString', () {
      test('returns a string representation of the underlying error', () {
        const underlyingError = NSUnderlyingError(
          error: NSError(
            code: 1,
            domain: 'com.example',
            userInfo: UserInfo(
              description: StringContainer('description'),
              localizedDescription: StringContainer('localizedDescription'),
              localizedFailureReason: StringContainer('localizedFailureReason'),
            ),
          ),
        );

        expect(underlyingError.toString(), '''
NSUnderlyingError(
  NSError(
  code: 1,
  domain: com.example,
  userInfo: UserInfo(
  description: description,
  localizedDescription: localizedDescription,
  localizedFailureReason: localizedFailureReason,
  underlyingError: null
)
)
)''');
      });
    });
  });
}
