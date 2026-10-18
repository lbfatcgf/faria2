import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/license_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFaria2License();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(900, 600),
    center: true,
    title: 'faria2',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  // Apply the window options. The native runners do not show the window on
  // their own; Faria2App decides after settings and the tray are ready.
  try {
    await windowManager.waitUntilReadyToShow(options);
  } on Object {
    // Continue; Faria2App will show the window when needed.
  }

  runApp(const Faria2App());
}
