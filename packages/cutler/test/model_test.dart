import 'package:cutler/model.dart';
import 'package:test/test.dart';

void main() {
  test('Version', () {
    const one = Version(
      repo: Repo.flutter,
      hash: 'abc123',
    );
    const two = Version(
      repo: Repo.flutter,
      hash: 'abc123',
      aliases: ['foo', 'bar'],
    );
    const three = Version(
      repo: Repo.flutter,
      hash: 'def456',
    );
    expect(one, equals(two));
    expect(one, isNot(equals(three)));
    expect(one.hashCode, equals(two.hashCode));
    expect(one.hashCode, isNot(equals(three.hashCode)));

    expect(one.ref, equals('abc123'));
    expect(two.ref, equals('foo'));
    expect(three.ref, equals('def456'));

    expect(one.toString(), equals('abc123'));
    expect(two.toString(), equals('abc123 (foo, bar)'));
    expect(three.toString(), equals('def456'));
  });

  test('VersionSet', () {
    const one = VersionSet(
      engine: Version(
        repo: Repo.engine,
        hash: 'e1',
      ),
      flutter: Version(
        repo: Repo.flutter,
        hash: 'f1',
      ),
      buildroot: Version(
        repo: Repo.buildroot,
        hash: 'b1',
      ),
      dart: Version(
        repo: Repo.dart,
        hash: 'd1',
      ),
    );
    final two = one.copyWith(
      engine: const Version(
        repo: Repo.engine,
        hash: 'e2',
      ),
      flutter: const Version(
        repo: Repo.flutter,
        hash: 'f2',
      ),
      buildroot: const Version(
        repo: Repo.buildroot,
        hash: 'b2',
      ),
      dart: const Version(
        repo: Repo.dart,
        hash: 'd2',
      ),
    );
    expect(one, isNot(equals(two)));
    expect(one.hashCode, isNot(equals(two.hashCode)));
    expect(
      one[Repo.engine],
      equals(const Version(repo: Repo.engine, hash: 'e1')),
    );
    expect(
      one[Repo.flutter],
      equals(const Version(repo: Repo.flutter, hash: 'f1')),
    );
    expect(
      one[Repo.buildroot],
      equals(const Version(repo: Repo.buildroot, hash: 'b1')),
    );
    expect(one[Repo.dart], equals(const Version(repo: Repo.dart, hash: 'd1')));
    expect(
      two[Repo.engine],
      equals(const Version(repo: Repo.engine, hash: 'e2')),
    );
    expect(
      two[Repo.flutter],
      equals(const Version(repo: Repo.flutter, hash: 'f2')),
    );
    expect(
      two[Repo.buildroot],
      equals(const Version(repo: Repo.buildroot, hash: 'b2')),
    );
    expect(two[Repo.dart], equals(const Version(repo: Repo.dart, hash: 'd2')));
  });
}
