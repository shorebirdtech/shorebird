import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(MacosEntitlementsValidator, () {
    const entitlementsPlistWithoutEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
''';

    const entitlementsPlistWithAllEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
''';

    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late MacosEntitlementsValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    File releaseEntitlementsFile() => File(
          p.join(projectRoot.path, 'macos', 'Runner', 'Release.entitlements'),
        );

    void setUpProjectRoot({String? entitlements}) {
      Directory(
        p.join(projectRoot.path, 'macos', 'Runner'),
      ).createSync(recursive: true);

      if (entitlements != null) {
        releaseEntitlementsFile()
          ..createSync(recursive: true)
          ..writeAsStringSync(entitlements);
      }
    }

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();

      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);

      validator = MacosEntitlementsValidator();
    });

    group('description', () {
      test('returns the correct description', () {
        expect(
          runWithOverrides(() => validator.description),
          'macOS app has correct entitlements',
        );
      });
    });

    group('canRunInCurrentContext', () {
      group('when macos directory exists', () {
        setUp(setUpProjectRoot);

        test('returns true', () {
          expect(
            runWithOverrides(() => validator.canRunInCurrentContext()),
            isTrue,
          );
        });
      });

      group('when macos directory does not exist', () {
        test('returns false', () {
          expect(
            runWithOverrides(() => validator.canRunInCurrentContext()),
            isFalse,
          );
          expect(
            runWithOverrides(() => validator.incorrectContextMessage),
            contains(
              '''The command you are running must be run within a Flutter app project that supports the macOS platform.''',
            ),
          );
        });
      });
    });

    group('validate', () {
      group('when release entitlements plist does not exist', () {
        setUp(setUpProjectRoot);

        test('returns a validation issue with no fix', () async {
          final issues = await runWithOverrides(() => validator.validate());
          expect(issues, hasLength(1));
          expect(
            issues[0],
            equals(
              const ValidationIssue(
                severity: ValidationIssueSeverity.error,
                message: 'Unable to find a Release.entitlements file',
              ),
            ),
          );
        });
      });

      group('when release entitlements plist exists', () {
        group('when entitlements are missing', () {
          setUp(() {
            setUpProjectRoot(
              entitlements: entitlementsPlistWithoutEntitlements,
            );
          });

          test('returns validation issues with fixes', () async {
            final validationResults = await runWithOverrides(
              () => validator.validate(),
            );
            expect(validationResults, hasLength(2));
            final networkIssue = validationResults[0];
            expect(networkIssue.severity, ValidationIssueSeverity.error);
            expect(
              networkIssue.message,
              contains(
                '''is missing the Outgoing Connections (com.apple.security.network.client) entitlement.''',
              ),
            );
            expect(networkIssue.fix, isNotNull);
            expect(
              MacosEntitlementsValidator.hasNetworkClientEntitlement(
                plistFile: releaseEntitlementsFile(),
              ),
              isFalse,
            );
            runWithOverrides(() => networkIssue.fix!());
            expect(
              MacosEntitlementsValidator.hasNetworkClientEntitlement(
                plistFile: releaseEntitlementsFile(),
              ),
              isTrue,
            );

            final unsignedMemoryIssue = validationResults[1];
            expect(unsignedMemoryIssue.severity, ValidationIssueSeverity.error);
            expect(
              unsignedMemoryIssue.message,
              contains(
                '''is missing the Allow Unsigned Executable Memory (com.apple.security.cs.allow-unsigned-executable-memory) entitlement.''',
              ),
            );
            expect(unsignedMemoryIssue.fix, isNotNull);
            expect(
              MacosEntitlementsValidator
                  .hasAllowUnsignedExecutableMemoryEntitlement(
                plistFile: releaseEntitlementsFile(),
              ),
              isFalse,
            );
            runWithOverrides(() => unsignedMemoryIssue.fix!());
            expect(
              MacosEntitlementsValidator
                  .hasAllowUnsignedExecutableMemoryEntitlement(
                plistFile: releaseEntitlementsFile(),
              ),
              isTrue,
            );
          });
        });

        group('when entitlements are present', () {
          setUp(() {
            setUpProjectRoot(
              entitlements: entitlementsPlistWithAllEntitlements,
            );
          });

          test('returns an empty list', () async {
            expect(await runWithOverrides(() => validator.validate()), isEmpty);
          });
        });
      });
    });
  });
}
