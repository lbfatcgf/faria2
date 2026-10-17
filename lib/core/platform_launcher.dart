import 'dart:io';

/// Opens files/folders with the platform file manager.
class PlatformLauncher {
  PlatformLauncher._();

  static Future<void> openDirectory(String path) async {
    if (path.isEmpty) {
      return;
    }
    if (Platform.isWindows) {
      await _run('explorer', <String>[path]);
    } else if (Platform.isLinux) {
      await _run('xdg-open', <String>[path]);
    }
  }

  static Future<void> openFile(String path) async {
    if (path.isEmpty) {
      return;
    }
    if (Platform.isWindows) {
      await _run('explorer', <String>[path]);
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
      await _run('explorer', <String>['/select,', path]);
      return;
    }
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await openDirectory(path);
    } else {
      await openDirectory(File(path).parent.path);
    }
  }

  static Future<void> _run(String executable, List<String> arguments) async {
    try {
      await Process.run(executable, arguments);
    } on Object {
      // Opening a folder is a convenience action, ignore failures.
    }
  }
}
