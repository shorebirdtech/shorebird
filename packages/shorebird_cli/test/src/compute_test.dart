import 'package:shorebird_cli/src/compute.dart';
import 'package:test/test.dart';

int test1(int value) => value + 1;
int test2(int value) => throw Exception();
Future<int> test1Async(int value) async => value + 1;
Future<int> test2Async(int value) async => throw Exception();

void main() {
  test('compute()', () async {
    expect(await compute(test1, 0), 1);
    expect(compute(test2, 0), throwsException);

    expect(await compute(test1Async, 0), 1);
    expect(compute(test2Async, 0), throwsException);
  });
}
