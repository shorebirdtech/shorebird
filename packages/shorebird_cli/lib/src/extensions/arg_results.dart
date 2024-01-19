import 'package:args/args.dart';
import 'package:collection/collection.dart';

extension OptionFinder on ArgResults {
  String? findOption(String name) {
    if (wasParsed(name)) {
      return this[name] as String?;
    }

    final flagStart = '--$name=';
    return rest
        .firstWhereOrNull((extra) => extra.startsWith(flagStart))
        ?.substring(flagStart.length);
  }
}
