import 'dart:io';

import 'package:faria2/core/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Linux paths', () {
    test('use XDG defaults', () {
      final dirs = AppPaths.resolveDirectories(
        environment: <String, String>{'HOME': '/home/user'},
        isWindows: false,
      );
      expect(dirs.support, '/home/user/.local/share/faria2');
      expect(dirs.cache, '/home/user/.cache/faria2');
      expect(dirs.downloads, '/home/user/Downloads/faria2');
    });

    test('honour XDG environment variables', () {
      final dirs = AppPaths.resolveDirectories(
        environment: <String, String>{
          'HOME': '/home/user',
          'XDG_DATA_HOME': '/data',
          'XDG_CACHE_HOME': '/cache',
          'XDG_CONFIG_HOME': '/config',
        },
        isWindows: false,
      );
      expect(dirs.support, '/data/faria2');
      expect(dirs.cache, '/cache/faria2');
      expect(dirs.downloads, '/home/user/Downloads/faria2');
    });

    test('read the XDG download directory', () async {
      final config = await Directory.systemTemp.createTemp('faria2_xdg');
      addTearDown(() => config.delete(recursive: true));
      await File(
        p.join(config.path, 'user-dirs.dirs'),
      ).writeAsString('XDG_DOWNLOAD_DIR="\$HOME/下载"\n');

      final dirs = AppPaths.resolveDirectories(
        environment: <String, String>{
          'HOME': '/home/user',
          'XDG_CONFIG_HOME': config.path,
        },
        isWindows: false,
      );
      expect(dirs.downloads, '/home/user/下载/faria2');
    });
  });

  group('Windows paths', () {
    test('use AppData and the Downloads folder', () {
      final dirs = AppPaths.resolveDirectories(
        environment: <String, String>{
          'USERPROFILE': p.windows.join('C:', 'Users', 'user'),
          'APPDATA': p.windows.join(
            'C:',
            'Users',
            'user',
            'AppData',
            'Roaming',
          ),
          'LOCALAPPDATA': p.windows.join(
            'C:',
            'Users',
            'user',
            'AppData',
            'Local',
          ),
        },
        isWindows: true,
      );
      expect(
        dirs.support,
        p.windows.join('C:', 'Users', 'user', 'AppData', 'Roaming', 'faria2'),
      );
      expect(
        dirs.cache,
        p.windows.join(
          'C:',
          'Users',
          'user',
          'AppData',
          'Local',
          'faria2',
          'cache',
        ),
      );
      expect(
        dirs.downloads,
        p.windows.join('C:', 'Users', 'user', 'Downloads', 'faria2'),
      );
    });

    test('fall back to the user profile', () {
      final dirs = AppPaths.resolveDirectories(
        environment: <String, String>{
          'USERPROFILE': p.windows.join('D:', 'home'),
        },
        isWindows: true,
      );
      expect(
        dirs.support,
        p.windows.join('D:', 'home', 'AppData', 'Roaming', 'faria2'),
      );
      expect(
        dirs.cache,
        p.windows.join('D:', 'home', 'AppData', 'Local', 'faria2', 'cache'),
      );
      expect(
        dirs.downloads,
        p.windows.join('D:', 'home', 'Downloads', 'faria2'),
      );
    });
  });

  test('engine, temp and runtime files live below the cache/support dirs', () {
    final paths = AppPaths(
      cacheDir: Directory('/cache/faria2'),
      supportDir: Directory('/data/faria2'),
      downloadsDir: Directory('/downloads/faria2'),
    );
    expect(paths.engineRoot.path, p.join('/cache/faria2', 'engine', 'aria2'));
    expect(paths.tempDir.path, p.join('/cache/faria2', 'tmp'));
    expect(paths.settingsFile.path, p.join('/data/faria2', 'settings.json'));
    expect(paths.sessionFile.path, p.join('/data/faria2', 'aria2.session'));
    expect(paths.aria2LogFile.path, p.join('/data/faria2', 'aria2.log'));
  });
}
