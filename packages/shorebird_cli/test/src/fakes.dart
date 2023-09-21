import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class FakeRelease extends Fake implements Release {}

class FakeShorebirdProcess extends Fake implements ShorebirdProcess {}
