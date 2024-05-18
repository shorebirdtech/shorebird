import 'dart:io';

import 'package:args/args.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart' show Cache;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/pubspec_editor.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class MockAccessCredentials extends Mock implements AccessCredentials {}

class MockAdb extends Mock implements Adb {}

class MockAndroidArchiveDiffer extends Mock implements AndroidArchiveDiffer {}

class MockAndroidSdk extends Mock implements AndroidSdk {}

class MockAndroidStudio extends Mock implements AndroidStudio {}

class MockAotTools extends Mock implements AotTools {}

class MockAppMetadata extends Mock implements AppMetadata {}

class MockAppleDevice extends Mock implements AppleDevice {}

class MockArchiveDiffer extends Mock implements ArchiveDiffer {}

class MockArgResults extends Mock implements ArgResults {}

class MockArtifactBuilder extends Mock implements ArtifactBuilder {}

class MockArtifactManager extends Mock implements ArtifactManager {}

class MockAuth extends Mock implements Auth {}

class MockBundleTool extends Mock implements Bundletool {}

class MockCache extends Mock implements Cache {}

class MockCodePushClient extends Mock implements CodePushClient {}

class MockCodePushClientWrapper extends Mock implements CodePushClientWrapper {}

class MockDevicectl extends Mock implements Devicectl {}

class MockDirectory extends Mock implements Directory {}

class MockDoctor extends Mock implements Doctor {}

class MockEngineConfig extends Mock implements EngineConfig {}

class MockFile extends Mock implements File {}

class MockFileSetDiff extends Mock implements FileSetDiff {}

class MockGit extends Mock implements Git {}

class MockGradlew extends Mock implements Gradlew {}

class MockHttpClient extends Mock implements http.Client {}

class MockIDeviceSysLog extends Mock implements IDeviceSysLog {}

class MockIOSDeploy extends Mock implements IOSDeploy {}

class MockIOSink extends Mock implements IOSink {}

class MockIos extends Mock implements Ios {}

class MockIosArchiveDiffer extends Mock implements IosArchiveDiffer {}

class MockJava extends Mock implements Java {}

class MockJwtHeader extends Mock implements JwtHeader {}

class MockJwtPayload extends Mock implements JwtPayload {}

class MockOperatingSystemInterface extends Mock
    implements OperatingSystemInterface {}

class MockPatchDiffChecker extends Mock implements PatchDiffChecker {}

class MockPatchExecutable extends Mock implements PatchExecutable {}

class MockPatcher extends Mock implements Patcher {}

class MockPlatform extends Mock implements Platform {}

class MockProcessResult extends Mock implements ShorebirdProcessResult {}

class MockProcessSignal extends Mock implements ProcessSignal {}

class MockProcessWrapper extends Mock implements ProcessWrapper {}

class MockProcess extends Mock implements Process {}

class MockProgress extends Mock implements Progress {}

class MockPubspecEditor extends Mock implements PubspecEditor {}

class MockRelease extends Mock implements Release {}

class MockReleaser extends Mock implements Releaser {}

class MockReleaseArtifact extends Mock implements ReleaseArtifact {}

class MockShorebirdAndroidArtifacts extends Mock
    implements ShorebirdAndroidArtifacts {}

class MockShorebirdArtifacts extends Mock implements ShorebirdArtifacts {}

class MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class MockShorebirdFlutter extends Mock implements ShorebirdFlutter {}

class MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class MockShorebirdLogger extends Mock implements ShorebirdLogger {}

class MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class MockShorebirdProcessResult extends Mock
    implements ShorebirdProcessResult {}

class MockShorebirdValidator extends Mock implements ShorebirdValidator {}

class MockShorebirdVersion extends Mock implements ShorebirdVersion {}

class MockShorebirdYaml extends Mock implements ShorebirdYaml {}

class MockStdin extends Mock implements Stdin {}

class MockUpdaterTools extends Mock implements UpdaterTools {}

class MockValidator extends Mock implements Validator {}

class MockXcodeBuild extends Mock implements XcodeBuild {}
