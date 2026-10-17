import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset path of the project's MIT license file.
const String faria2LicenseAsset = 'LICENSE';

/// Registers the project's MIT license with Flutter's license registry so it
/// appears on the in-app license page together with third-party notices.
void registerFaria2License() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(faria2LicenseAsset);
    yield LicenseEntryWithLineBreaks(const <String>['faria2'], text);
  });
}
