import 'dart:io';

import 'package:path/path.dart' as p;

/// All runtime locations used by faria2.
///
/// * [cacheDir] stores the managed aria2 engine and temporary files, this is
///   the "faria2 cache directory" used by the install flow.
/// * [supportDir] stores settings, the aria2 session file and the aria2 log.
/// * [downloadsDir] is the default download target.
class AppPaths {
  const AppPaths({
    required this.cacheDir,
    required this.supportDir,
    required this.downloadsDir,
  });

  final Directory cacheDir;
  final Directory supportDir;
  final Directory downloadsDir;

  /// Resolves and creates the application directories.
  static Future<AppPaths> resolve({
    Map<String, String>? environment,
    bool? isWindows,
  }) async {
    final resolved = resolveDirectories(
      environment: environment ?? Platform.environment,
      isWindows: isWindows ?? Platform.isWindows,
    );
    final paths = AppPaths(
      cacheDir: Directory(resolved.cache),
      supportDir: Directory(resolved.support),
      downloadsDir: Directory(resolved.downloads),
    );
    await paths.ensure();
    return paths;
  }

  /// Pure directory resolution, kept free of side effects for testing.
  ///
  /// Linux follows the XDG base directory specification, Windows uses the
  /// roaming/local AppData folders and the user's Downloads folder.
  static ({String cache, String support, String downloads}) resolveDirectories({
    required Map<String, String> environment,
    required bool isWindows,
  }) {
    if (isWindows) {
      final profile =
          _firstNonEmpty(<String?>[
            environment['USERPROFILE'],
            environment['HOME'],
          ]) ??
          p.windows.dirname(p.windows.dirname(environment['APPDATA'] ?? '.'));
      final appData =
          _firstNonEmpty(<String?>[
            environment['APPDATA'],
            p.windows.join(profile, 'AppData', 'Roaming'),
          ]) ??
          profile;
      final localAppData =
          _firstNonEmpty(<String?>[
            environment['LOCALAPPDATA'],
            p.windows.join(profile, 'AppData', 'Local'),
          ]) ??
          appData;
      return (
        cache: p.windows.join(localAppData, 'faria2', 'cache'),
        support: p.windows.join(appData, 'faria2'),
        downloads: p.windows.join(profile, 'Downloads', 'faria2'),
      );
    }

    final home = _firstNonEmpty(<String?>[environment['HOME']]) ?? '.';
    final dataHome =
        _firstNonEmpty(<String?>[environment['XDG_DATA_HOME']]) ??
        p.posix.join(home, '.local', 'share');
    final cacheHome =
        _firstNonEmpty(<String?>[environment['XDG_CACHE_HOME']]) ??
        p.posix.join(home, '.cache');
    final configHome =
        _firstNonEmpty(<String?>[environment['XDG_CONFIG_HOME']]) ??
        p.posix.join(home, '.config');
    final downloadBase =
        _xdgDownloadDirectory(configHome, home) ??
        p.posix.join(home, 'Downloads');

    return (
      cache: p.posix.join(cacheHome, 'faria2'),
      support: p.posix.join(dataHome, 'faria2'),
      downloads: p.posix.join(downloadBase, 'faria2'),
    );
  }

  /// The root folder that contains managed aria2 installations.
  Directory get engineRoot =>
      Directory(p.join(cacheDir.path, 'engine', 'aria2'));

  /// Temporary folder for in-flight engine downloads.
  Directory get tempDir => Directory(p.join(cacheDir.path, 'tmp'));

  File get settingsFile => File(p.join(supportDir.path, 'settings.json'));
  File get sessionFile => File(p.join(supportDir.path, 'aria2.session'));
  File get aria2LogFile => File(p.join(supportDir.path, 'aria2.log'));

  Future<void> ensure() async {
    await supportDir.create(recursive: true);
    await cacheDir.create(recursive: true);
    await downloadsDir.create(recursive: true);
    await tempDir.create(recursive: true);
  }
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _xdgDownloadDirectory(String configHome, String home) {
  try {
    final file = File(p.posix.join(configHome, 'user-dirs.dirs'));
    if (!file.existsSync()) {
      return null;
    }
    final match = RegExp(
      r'^XDG_DOWNLOAD_DIR="(.*)"\s*$',
      multiLine: true,
    ).firstMatch(file.readAsStringSync());
    if (match == null) {
      return null;
    }
    final value = match.group(1)!.replaceAll(r'$HOME', home).trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  } on Object {
    return null;
  }
}
