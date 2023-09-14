// import 'package:path/path.dart' as p;
// import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
// import 'package:test/test.dart';

// void main() {
//   final ipaFixturesBasePath = p.join('test', 'fixtures', 'ipas');
//   final baseIpaBath = p.join(ipaFixturesBasePath, 'base.ipa');
//   final noVersionIpaPath = p.join(ipaFixturesBasePath, 'no_version.ipa');
//   final noPlistIpaPath = p.join(ipaFixturesBasePath, 'no_plist.ipa');
//   final spaceInAppFileNameIpaPath =
//       p.join(ipaFixturesBasePath, 'app_file_space.ipa');

//   group(IpaReader, () {
//     test('creates Ipa', () {
//       final ipa = IpaReader().read(baseIpaBath);
//       expect(ipa.versionNumber, '1.0.0+1');
//     });
//   });

//   group(Ipa, () {
//     test('reads app version from ipa', () {
//       final ipa = Ipa(path: baseIpaBath);
//       expect(ipa.versionNumber, '1.0.0+1');
//     });

//     test('reads app version from ipa with space in app file name', () {
//       final ipa = Ipa(path: spaceInAppFileNameIpaPath);
//       expect(ipa.versionNumber, '1.0.0+1');
//     });

//     test('throws exception if no Info.plist is found', () {
//       final ipa = Ipa(path: noPlistIpaPath);
//       expect(() => ipa.versionNumber, throwsException);
//     });

//     test('throws exception if no version is found in Info.plist', () {
//       final ipa = Ipa(path: noVersionIpaPath);
//       expect(() => ipa.versionNumber, throwsException);
//     });
//   });
// }
