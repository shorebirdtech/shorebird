import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(MacosNetworkEntitlementValidator, () {
    const entitlementsPlistWithoutEntitlement = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
''';

    const entitlementsPlistWithEntitlement = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
''';

    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late MacosNetworkEntitlementValidator validator;

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

      validator = MacosNetworkEntitlementValidator();
    });

    group('description', () {
      test('returns the correct description', () {
        expect(
          runWithOverrides(() => validator.description),
          'macOS app has Outgoing Connections entitlement',
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
        group('when network client entitlement is missing', () {
          setUp(() {
            setUpProjectRoot(entitlements: entitlementsPlistWithoutEntitlement);
          });

          test('returns a validation issue with a fix', () async {
            final validationResults = await runWithOverrides(
              () => validator.validate(),
            );
            expect(validationResults, hasLength(1));
            final issue = validationResults[0];
            expect(issue.severity, ValidationIssueSeverity.error);
            expect(
              issue.message,
              contains(
                '''is missing the Outgoing Connections (com.apple.security.network.client) entitlement.''',
              ),
            );
            expect(issue.fix, isNotNull);
            expect(
              MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
                plistFile: releaseEntitlementsFile(),
              ),
              isFalse,
            );
            runWithOverrides(() => issue.fix!());
            expect(
              MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
                plistFile: releaseEntitlementsFile(),
              ),
              isTrue,
            );
          });
        });

        group('when network client entitlement is present', () {
          setUp(() {
            setUpProjectRoot(entitlements: entitlementsPlistWithEntitlement);
          });

          test('returns an empty list', () async {
            expect(await runWithOverrides(() => validator.validate()), isEmpty);
          });
        });
      });
    });

    group('fix', () {
      group('when the network client entitlement is missing', () {
        setUp(() {
          setUpProjectRoot(entitlements: entitlementsPlistWithoutEntitlement);
        });

        test('adds the network client entitlement to the entitlements plist',
            () {
          expect(
            MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
              plistFile: releaseEntitlementsFile(),
            ),
            isFalse,
          );

          MacosNetworkEntitlementValidator.addNetworkEntitlementToPlist(
            releaseEntitlementsFile(),
          );

          expect(
            MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
              plistFile: releaseEntitlementsFile(),
            ),
            isTrue,
          );
        });
      });

      group('when the network client entitlement is present', () {
        setUp(() {
          setUpProjectRoot(entitlements: entitlementsPlistWithEntitlement);
        });

        test('does not modify the entitlements plist', () {
          final plistContents = releaseEntitlementsFile().readAsStringSync();
          expect(
            MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
              plistFile: releaseEntitlementsFile(),
            ),
            isTrue,
          );

          MacosNetworkEntitlementValidator.addNetworkEntitlementToPlist(
            releaseEntitlementsFile(),
          );

          expect(
            MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
              plistFile: releaseEntitlementsFile(),
            ),
            isTrue,
          );

          final updatedPlistContents =
              releaseEntitlementsFile().readAsStringSync();
          expect(updatedPlistContents, plistContents);
        });
      });
    });

    group('plistHasNetworkClientEntitlement', () {
      group('when entitlement is present', () {
        setUp(() {
          setUpProjectRoot(entitlements: entitlementsPlistWithEntitlement);
        });

        test('returns true', () {
          expect(
            MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
              plistFile: releaseEntitlementsFile(),
            ),
            isTrue,
          );
        });
      });

      group('when entitlement is not present', () {
        setUp(() {
          setUpProjectRoot(entitlements: entitlementsPlistWithoutEntitlement);
        });

        test('returns false', () {
          expect(
            MacosNetworkEntitlementValidator.hasNetworkClientEntitlement(
              plistFile: releaseEntitlementsFile(),
            ),
            isFalse,
          );
        });
      });
    });
  });
}
