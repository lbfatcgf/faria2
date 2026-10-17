import 'dart:io';

import 'package:path/path.dart' as p;

/// Where a usable aria2c binary was found.
enum Aria2Source {
  /// User configured path from the settings page.
  custom,

  /// Managed binary inside the faria2 cache directory.
  cache,

  /// Binary found on the system PATH.
  system,
}

class Aria2Location {
  const Aria2Location({required this.path, required this.source, this.version});

  final String path;
  final Aria2Source source;
  final String? version;

  Aria2Location copyWith({String? path, Aria2Source? source, String? version}) {
    return Aria2Location(
      path: path ?? this.path,
      source: source ?? this.source,
      version: version ?? this.version,
    );
  }

  String get sourceLabel {
    return switch (source) {
      Aria2Source.custom => '用户指定',
      Aria2Source.cache => 'faria2 缓存',
      Aria2Source.system => '系统 PATH',
    };
  }
}

/// Finds an aria2c executable: explicit setting, managed cache copy, then PATH.
class Aria2Locator {
  Aria2Locator({
    required this.engineRoot,
    this.customPath = '',
    Map<String, String>? environment,
    bool? isWindows,
  }) : _environment = environment ?? Platform.environment,
       _isWindows = isWindows ?? Platform.isWindows;

  final Directory engineRoot;
  final String customPath;
  final Map<String, String> _environment;
  final bool _isWindows;

  String get binaryName => _isWindows ? 'aria2c.exe' : 'aria2c';

  /// All candidate binaries in priority order: the user setting, every aria2c
  /// found on PATH, then the managed cache (newest version first).
  ///
  /// A system installation is preferred, which matches "start aria2c; only
  /// install one when it is missing". Candidates are not executed here; the
  /// caller probes them so a broken installation can be skipped instead of
  /// blocking startup.
  Future<List<Aria2Location>> candidates() async {
    final results = <Aria2Location>[];
    final seen = <String>{};

    void add(Aria2Location location) {
      final key = p.normalize(p.absolute(location.path));
      if (seen.add(key)) {
        results.add(location);
      }
    }

    final custom = customPath.trim();
    if (custom.isNotEmpty) {
      final file = File(custom);
      if (await _isUsable(file)) {
        add(Aria2Location(path: file.path, source: Aria2Source.custom));
      }
    }

    for (final file in await _pathBinaries()) {
      add(Aria2Location(path: file.path, source: Aria2Source.system));
    }

    for (final file in await managedBinaries()) {
      add(
        Aria2Location(
          path: file.path,
          source: Aria2Source.cache,
          version: p.basename(file.parent.path),
        ),
      );
    }

    return results;
  }

  /// Returns the first candidate location or null when nothing was found.
  Future<Aria2Location?> locate() async {
    final all = await candidates();
    return all.isEmpty ? null : all.first;
  }

  /// All managed binaries, newest version first.
  Future<List<File>> managedBinaries() async {
    if (!await engineRoot.exists()) {
      return const <File>[];
    }
    final dirs = await engineRoot
        .list()
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    dirs.sort(
      (a, b) => _compareVersions(p.basename(b.path), p.basename(a.path)),
    );
    final result = <File>[];
    for (final dir in dirs) {
      final file = File(p.join(dir.path, binaryName));
      if (await _isUsable(file)) {
        result.add(file);
      }
    }
    return result;
  }

  Future<List<File>> _pathBinaries() async {
    final rawPath = _environment['PATH'] ?? _environment['Path'] ?? '';
    if (rawPath.isEmpty) {
      return const <File>[];
    }
    final separator = _isWindows ? ';' : ':';
    final seen = <String>{};
    final result = <File>[];
    for (final entry in rawPath.split(separator)) {
      final dir = entry.trim();
      if (dir.isEmpty || !seen.add(dir)) {
        continue;
      }
      final candidate = File(p.join(dir, binaryName));
      if (await _isUsable(candidate)) {
        result.add(candidate);
      }
    }
    return result;
  }

  Future<bool> _isUsable(File file) async {
    try {
      if (!await file.exists()) {
        return false;
      }
      if (_isWindows) {
        return true;
      }
      final stat = await file.stat();
      // Owner/group/other execute bits.
      return stat.mode & 0x49 != 0;
    } on Object {
      return false;
    }
  }
}

int _compareVersions(String a, String b) {
  List<int> parts(String value) {
    return value
        .split(RegExp(r'[.\-_]'))
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }

  final left = parts(a);
  final right = parts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) {
      return l.compareTo(r);
    }
  }
  return a.compareTo(b);
}
