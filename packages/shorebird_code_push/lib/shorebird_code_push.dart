/// Get info about your Shorebird code push app
library shorebird_code_push;

export 'src/shorebird_code_push_io.dart'
    if (dart.library.html) 'src/shorebird_code_push_web.dart';
