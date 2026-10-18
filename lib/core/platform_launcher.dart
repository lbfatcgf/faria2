import 'dart:io';

import 'package:flutter/foundation.dart';

/// Opens files/folders with the platform file manager.
class PlatformLauncher {
  PlatformLauncher._();

  static Future<void> openDirectory(String path) async {
    if (path.isEmpty) {
      return;
    }
    if (Platform.isWindows) {
      await _run('cmd.exe', windowsOpenDirectoryArguments(path));
    } else if (Platform.isLinux) {
      await _run('xdg-open', <String>[path]);
    }
  }

  static Future<void> openFile(String path) async {
    if (path.isEmpty) {
      return;
    }
    if (Platform.isWindows) {
      // "start" resolves the file association. The empty quoted argument is
      // the window title so a path containing spaces is not treated as one.
      await _run('cmd.exe', windowsOpenFileArguments(path));
    } else if (Platform.isLinux) {
      await _run('xdg-open', <String>[path]);
    }
  }

  /// Selects [path] in the file manager when possible.
  static Future<void> reveal(String path) async {
    if (path.isEmpty) {
      return;
    }
    if (Platform.isWindows) {
      // Calling explorer.exe directly from Dart can lose the /select argument
      // (especially for paths containing spaces). Going through cmd.exe keeps
      // /select,"<path>" intact and reliably selects the file.
      await _run('cmd.exe', windowsRevealArguments(path));
      return;
    }
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await openDirectory(path);
    } else {
      await openDirectory(File(path).parent.path);
    }
  }

  /// Arguments for `cmd.exe` that reveal [path] in Explorer.
  static List<String> windowsRevealArguments(String path) {
    path = path.replaceAll('/', r'\');
    if (kDebugMode) {
      print(path);
    }
    return <String>['/c', 'explorer.exe', '/select,$path'];
  }

  /// Arguments for `cmd.exe` that open [path] with its associated app.
  static List<String> windowsOpenFileArguments(String path) {
    return <String>['/c', 'start', path];
  }

  /// Arguments for `cmd.exe` that open [path] in Explorer.
  static List<String> windowsOpenDirectoryArguments(String path) {
    return <String>['/c', 'start', 'explorer.exe', path];
  }

  static Future<void> _run(String executable, List<String> arguments) async {
    try {
      await Process.run(executable, arguments);
    } on Object {
      // Opening a folder is a convenience action, ignore failures.
    }
  }
}
