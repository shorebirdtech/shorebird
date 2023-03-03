import 'package:shorebird_code_push_api/src/config.dart' as config;
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';

const _versionStore = VersionStore(cachePath: config.cachePath);

final versionStoreProvider = provider<VersionStore>((_) => _versionStore);
