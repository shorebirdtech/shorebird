import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/init_command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/gradlew.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/xcodebuild.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockDoctor extends Mock implements Doctor {}

class _MockGradlew extends Mock implements Gradlew {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockXcodeBuild extends Mock implements XcodeBuild {}

void main() {
  group(InitCommand, () {
    const version = '1.2.3';
    const appId = 'test_app_id';
    const appName = 'test_app_name';
    const app = App(id: appId, displayName: appName);
    const appMetadata = AppMetadata(appId: appId, displayName: appName);
    const pubspecYamlContent = '''
name: $appName
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"''';

    late http.Client httpClient;
    late ArgResults argResults;
    late Auth auth;
    late Doctor doctor;
    late Gradlew gradlew;
    late CodePushClient codePushClient;
    late Logger logger;
    late Platform platform;
    late Progress progress;
    late XcodeBuild xcodeBuild;
    late InitCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          doctorRef.overrideWith(() => doctor),
          gradlewRef.overrideWith(() => gradlew),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
          xcodeBuildRef.overrideWith(() => xcodeBuild),
        },
      );
    }

    Directory setUpAppTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, 'android')).createSync(recursive: true);
      Directory(p.join(tempDir.path, 'ios')).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      httpClient = _MockHttpClient();
      argResults = _MockArgResults();
      auth = _MockAuth();
      doctor = _MockDoctor();
      gradlew = _MockGradlew();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      platform = _MockPlatform();
      progress = _MockProgress();
      xcodeBuild = _MockXcodeBuild();

      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenAnswer((_) async => app);
      when(
        () => codePushClient.getApps(),
      ).thenAnswer((_) async => [appMetadata]);
      when(
        () => doctor.runValidators(any(), applyFixes: any(named: 'applyFixes')),
      ).thenAnswer((_) async => {});
      when(() => doctor.allValidators).thenReturn([]);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appName);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => gradlew.productFlavors(any())).thenAnswer((_) async => {});
      when(() => platform.isMacOS).thenReturn(true);
      when(
        () => xcodeBuild.list(any()),
      ).thenAnswer((_) async => const XcodeProjectBuildInfo());

      command = runWithOverrides(
        () => InitCommand(
          buildCodePushClient: ({
            required http.Client httpClient,
            Uri? hostedUri,
          }) {
            return codePushClient;
          },
        ),
      )..testArgResults = argResults;
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.noUser.code);
    });

    test('throws no input error when pubspec.yaml is not found.', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          '''
Could not find a "pubspec.yaml".
Please make sure you are running "shorebird init" from the root of your Flutter project.
''',
        ),
      ).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws software error when pubspec.yaml is malformed.', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(p.join(tempDir.path, 'pubspec.yaml')).createSync();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          any(that: contains('Error parsing "pubspec.yaml":')),
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws software error when shorebird.yaml already exists', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(p.join(tempDir.path, 'shorebird.yaml')).createSync();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          '''
A "shorebird.yaml" already exists.
If you want to reinitialize Shorebird, please run "shorebird init --force".''',
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('--force overwrites existing shorebird.yaml', () async {
      when(() => argResults['force']).thenReturn(true);
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(p.join(tempDir.path, 'shorebird.yaml')).createSync();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verifyNever(
        () => logger.err(
          '''
A "shorebird.yaml" already exists.
If you want to reinitialize Shorebird, please run "shorebird init --force".''',
        ),
      );
      expect(exitCode, ExitCode.success.code);
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $appId'),
      );
    });

    test('fails when an error occurs while extracting flavors', () async {
      final exception = Exception('oops');
      when(() => gradlew.productFlavors(any())).thenThrow(exception);
      final tempDir = setUpAppTempDir();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.progress('Detecting product flavors')).called(1);
      verify(
        () => logger.err(
          any(that: contains('Unable to extract product flavors.')),
        ),
      ).called(1);
      verify(() => progress.fail()).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws software error when error occurs creating app.', () async {
      final error = Exception('oops');
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenThrow(error);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).called(1);
      verify(() => logger.err('$error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    group('on non MacOS', () {
      setUp(() {
        when(() => platform.isMacOS).thenReturn(false);
      });

      test('throws software error when unable to detect schemes', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(exitCode, equals(ExitCode.software.code));
        verify(
          () => logger.err(
            any(that: contains('Unable to detect iOS schemes in')),
          ),
        ).called(1);
        verifyNever(() => xcodeBuild.list(any()));
      });

      test('creates shorebird for an android-only app', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('app_id: $appId'),
        );
        expect(exitCode, equals(ExitCode.success.code));
        verifyNever(() => xcodeBuild.list(any()));
      });

      test('creates shorebird for an app without flavors', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        when(
          () => gradlew.productFlavors(any()),
        ).thenThrow(MissingAndroidProjectException(tempDir.path));
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        File(
          p.join(
            tempDir.path,
            'ios',
            'Runner.xcodeproj',
            'xcshareddata',
            'xcschemes',
            'Runner.xcscheme',
          ),
        ).createSync(recursive: true);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('app_id: $appId'),
        );
        expect(exitCode, equals(ExitCode.success.code));
        verifyNever(() => xcodeBuild.list(any()));
      });

      test('creates shorebird for an app with flavors', () async {
        const appIds = ['test-appId-1', 'test-appId-2'];
        var index = 0;
        when(
          () =>
              codePushClient.createApp(displayName: any(named: 'displayName')),
        ).thenAnswer((invocation) async {
          final displayName = invocation.namedArguments[#displayName] as String;
          return App(id: appIds[index++], displayName: displayName);
        });
        final tempDir = Directory.systemTemp.createTempSync();
        when(
          () => gradlew.productFlavors(any()),
        ).thenThrow(MissingAndroidProjectException(tempDir.path));
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        final schemesPath = p.join(
          tempDir.path,
          'ios',
          'Runner.xcodeproj',
          'xcshareddata',
          'xcschemes',
        );
        File(p.join(schemesPath, 'Runner.xcscheme'))
            .createSync(recursive: true);
        File(p.join(schemesPath, 'internal.xcscheme'))
            .createSync(recursive: true);
        File(p.join(schemesPath, 'stable.xcscheme'))
            .createSync(recursive: true);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('''
app_id: ${appIds[0]}
flavors:
  internal: ${appIds[0]}
  stable: ${appIds[1]}'''),
        );

        verifyInOrder([
          () => codePushClient.createApp(displayName: '$appName (internal)'),
          () => codePushClient.createApp(displayName: '$appName (stable)'),
        ]);
        expect(exitCode, equals(ExitCode.success.code));
        verifyNever(() => xcodeBuild.list(any()));
      });
    });

    test('creates shorebird.yaml for an app without flavors', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $appId'),
      );
    });

    group('creates shorebird.yaml for an app with flavors', () {
      test('android only', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
        ];
        var index = 0;
        when(() => gradlew.productFlavors(any())).thenAnswer(
          (_) async => {
            'development',
            'developmentInternal',
            'production',
            'productionInternal',
            'staging',
            'stagingInternal',
          },
        );
        when(
          () =>
              codePushClient.createApp(displayName: any(named: 'displayName')),
        ).thenAnswer((invocation) async {
          final displayName = invocation.namedArguments[#displayName] as String;
          return App(id: appIds[index++], displayName: displayName);
        });
        final tempDir = setUpAppTempDir();
        when(
          () => xcodeBuild.list(any()),
        ).thenThrow(MissingIOSProjectException(tempDir.path));
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[0]}
  developmentInternal: ${appIds[1]}
  production: ${appIds[2]}
  productionInternal: ${appIds[3]}
  staging: ${appIds[4]}
  stagingInternal: ${appIds[5]}'''),
        );

        verifyInOrder([
          () => codePushClient.createApp(displayName: '$appName (development)'),
          () => codePushClient.createApp(
                displayName: '$appName (developmentInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (production)'),
          () => codePushClient.createApp(
                displayName: '$appName (productionInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (staging)'),
          () => codePushClient.createApp(
                displayName: '$appName (stagingInternal)',
              ),
        ]);
      });

      test('ios only', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6'
        ];
        var index = 0;
        when(() => xcodeBuild.list(any())).thenAnswer(
          (_) async => const XcodeProjectBuildInfo(
            schemes: {
              'development',
              'developmentInternal',
              'production',
              'productionInternal',
              'staging',
              'stagingInternal',
            },
          ),
        );
        when(
          () =>
              codePushClient.createApp(displayName: any(named: 'displayName')),
        ).thenAnswer((invocation) async {
          final displayName = invocation.namedArguments[#displayName] as String;
          return App(id: appIds[index++], displayName: displayName);
        });
        final tempDir = setUpAppTempDir();
        when(
          () => gradlew.productFlavors(any()),
        ).thenThrow(MissingAndroidProjectException(tempDir.path));
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[0]}
  developmentInternal: ${appIds[1]}
  production: ${appIds[2]}
  productionInternal: ${appIds[3]}
  staging: ${appIds[4]}
  stagingInternal: ${appIds[5]}'''),
        );

        verifyInOrder([
          () => codePushClient.createApp(displayName: '$appName (development)'),
          () => codePushClient.createApp(
                displayName: '$appName (developmentInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (production)'),
          () => codePushClient.createApp(
                displayName: '$appName (productionInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (staging)'),
          () => codePushClient.createApp(
                displayName: '$appName (stagingInternal)',
              ),
        ]);
      });

      test('ios w/flavors and android w/out flavors', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
          'test-appId-7'
        ];
        var index = 0;
        when(() => xcodeBuild.list(any())).thenAnswer(
          (_) async => const XcodeProjectBuildInfo(
            schemes: {
              'development',
              'developmentInternal',
              'production',
              'productionInternal',
              'staging',
              'stagingInternal',
            },
          ),
        );
        when(() => gradlew.productFlavors(any())).thenAnswer((_) async => {});
        when(
          () =>
              codePushClient.createApp(displayName: any(named: 'displayName')),
        ).thenAnswer((invocation) async {
          final displayName = invocation.namedArguments[#displayName] as String;
          return App(id: appIds[index++], displayName: displayName);
        });
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[1]}
  developmentInternal: ${appIds[2]}
  production: ${appIds[3]}
  productionInternal: ${appIds[4]}
  staging: ${appIds[5]}
  stagingInternal: ${appIds[6]}'''),
        );

        verifyInOrder([
          () => codePushClient.createApp(displayName: '$appName (development)'),
          () => codePushClient.createApp(
                displayName: '$appName (developmentInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (production)'),
          () => codePushClient.createApp(
                displayName: '$appName (productionInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (staging)'),
          () => codePushClient.createApp(
                displayName: '$appName (stagingInternal)',
              ),
        ]);
      });

      test('android w/flavors and ios w/out flavors', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
          'test-appId-7'
        ];
        var index = 0;
        when(() => xcodeBuild.list(any())).thenAnswer(
          (_) async => const XcodeProjectBuildInfo(),
        );
        when(() => gradlew.productFlavors(any())).thenAnswer(
          (_) async => {
            'development',
            'developmentInternal',
            'production',
            'productionInternal',
            'staging',
            'stagingInternal',
          },
        );
        when(
          () =>
              codePushClient.createApp(displayName: any(named: 'displayName')),
        ).thenAnswer((invocation) async {
          final displayName = invocation.namedArguments[#displayName] as String;
          return App(id: appIds[index++], displayName: displayName);
        });
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[1]}
  developmentInternal: ${appIds[2]}
  production: ${appIds[3]}
  productionInternal: ${appIds[4]}
  staging: ${appIds[5]}
  stagingInternal: ${appIds[6]}'''),
        );

        verifyInOrder([
          () => codePushClient.createApp(displayName: '$appName (development)'),
          () => codePushClient.createApp(
                displayName: '$appName (developmentInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (production)'),
          () => codePushClient.createApp(
                displayName: '$appName (productionInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (staging)'),
          () => codePushClient.createApp(
                displayName: '$appName (stagingInternal)',
              ),
        ]);
      });

      test('ios + android w/same variants', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6'
        ];
        const variants = {
          'development',
          'developmentInternal',
          'production',
          'productionInternal',
          'staging',
          'stagingInternal',
        };
        var index = 0;
        when(
          () => gradlew.productFlavors(any()),
        ).thenAnswer((_) async => variants);
        when(() => xcodeBuild.list(any())).thenAnswer(
          (_) async => const XcodeProjectBuildInfo(schemes: variants),
        );
        when(
          () =>
              codePushClient.createApp(displayName: any(named: 'displayName')),
        ).thenAnswer((invocation) async {
          final displayName = invocation.namedArguments[#displayName] as String;
          return App(id: appIds[index++], displayName: displayName);
        });
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[0]}
  developmentInternal: ${appIds[1]}
  production: ${appIds[2]}
  productionInternal: ${appIds[3]}
  staging: ${appIds[4]}
  stagingInternal: ${appIds[5]}'''),
        );

        verifyInOrder([
          () => codePushClient.createApp(displayName: '$appName (development)'),
          () => codePushClient.createApp(
                displayName: '$appName (developmentInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (production)'),
          () => codePushClient.createApp(
                displayName: '$appName (productionInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (staging)'),
          () => codePushClient.createApp(
                displayName: '$appName (stagingInternal)',
              ),
        ]);
      });

      test('ios + android w/different variants', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
          'test-appId-7',
          'test-appId-8',
        ];
        const androidVariants = {
          'dev',
          'devInternal',
          'production',
          'productionInternal',
        };
        const iosVariants = {
          'development',
          'developmentInternal',
          'production',
          'productionInternal',
          'staging',
          'stagingInternal',
        };
        var index = 0;
        when(
          () => gradlew.productFlavors(any()),
        ).thenAnswer((_) async => androidVariants);
        when(() => xcodeBuild.list(any())).thenAnswer(
          (_) async => const XcodeProjectBuildInfo(schemes: iosVariants),
        );
        when(
          () =>
              codePushClient.createApp(displayName: any(named: 'displayName')),
        ).thenAnswer((invocation) async {
          final displayName = invocation.namedArguments[#displayName] as String;
          return App(id: appIds[index++], displayName: displayName);
        });
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
          contains('''
app_id: test-appId-1
flavors:
  dev: test-appId-1
  devInternal: test-appId-2
  production: test-appId-3
  productionInternal: test-appId-4
  development: test-appId-5
  developmentInternal: test-appId-6
  staging: test-appId-7
  stagingInternal: test-appId-8'''),
        );

        verifyInOrder([
          () => codePushClient.createApp(displayName: '$appName (dev)'),
          () => codePushClient.createApp(displayName: '$appName (devInternal)'),
          () => codePushClient.createApp(displayName: '$appName (production)'),
          () => codePushClient.createApp(
                displayName: '$appName (productionInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (development)'),
          () => codePushClient.createApp(
                displayName: '$appName (developmentInternal)',
              ),
          () => codePushClient.createApp(displayName: '$appName (staging)'),
          () => codePushClient.createApp(
                displayName: '$appName (stagingInternal)',
              ),
        ]);
      });
    });

    test('detects existing shorebird.yaml in pubspec.yaml assets', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync('''
$pubspecYamlContent
flutter:
  assets:
    - shorebird.yaml
''');
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $appId'),
      );
    });

    test('creates flutter.assets and adds shorebird.yaml', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
        equals('''
$pubspecYamlContent
flutter:
  assets:
    - shorebird.yaml
'''),
      );
    });

    test('creates assets and adds shorebird.yaml', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
$pubspecYamlContent
flutter:
  uses-material-design: true
''');
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
        equals('''
$pubspecYamlContent
flutter:
  assets:
    - shorebird.yaml
  uses-material-design: true
'''),
      );
    });

    test('adds shorebird.yaml to assets', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
$pubspecYamlContent
flutter:
  assets:
    - some/asset.txt
''');
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
        equals('''
$pubspecYamlContent
flutter:
  assets:
    - some/asset.txt
    - shorebird.yaml
'''),
      );
    });

    test('fixes fixable validation errors', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(() => doctor.runValidators(any(), applyFixes: true)).called(1);
    });
  });
}
