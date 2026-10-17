import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'aria2_asset.dart';
import 'aria2_locator.dart';
import 'aria2_version.dart';
import 'download_client.dart';

/// Progress callback for the installation flow.
typedef InstallProgressCallback = void Function(String stage, double? progress);

/// Raised when aria2 could not be installed.
class Aria2InstallException implements Exception {
  Aria2InstallException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return message;
    }
    return '$message（$cause）';
  }
}

/// Downloads, extracts and validates a managed aria2c binary in the faria2
/// cache directory.
class Aria2Installer {
  Aria2Installer({
    required this.cacheDir,
    required this.asset,
    this.onProgress,
    DownloadClient? downloadClient,
  }) : _downloadClient = downloadClient ?? DownloadClient();

  final Directory cacheDir;
  final Aria2Asset asset;
  final InstallProgressCallback? onProgress;
  final DownloadClient _downloadClient;

  /// Installs aria2 and returns the location of the executable.
  Future<Aria2Location> install() async {
    final targetDir = Directory(
      p.join(cacheDir.path, 'engine', 'aria2', asset.versionDirName),
    );
    final target = File(p.join(targetDir.path, asset.binaryName));
    final tempArchive = File(
      p.join(cacheDir.path, 'tmp', '${asset.archiveFileName}.part'),
    );
    final tempBinary = File(
      p.join(cacheDir.path, 'tmp', '${asset.binaryName}.part'),
    );

    try {
      onProgress?.call('正在下载 aria2 ${asset.version}…', 0);

      await tempArchive.parent.create(recursive: true);
      if (await tempArchive.exists()) {
        await tempArchive.delete();
      }

      var lastReported = -1;
      await _downloadClient.download(
        Uri.parse(asset.url),
        tempArchive,
        onProgress: (received, total) {
          if (total == null || total <= 0) {
            onProgress?.call(
              '正在下载 aria2 ${asset.version}… (${_mib(received)})',
              null,
            );
            return;
          }
          final percent = (received / total * 100).floor();
          if (percent != lastReported) {
            lastReported = percent;
            onProgress?.call(
              '正在下载 aria2 ${asset.version}… ${_mib(received)} / ${_mib(total)}',
              received / total * 0.85,
            );
          }
        },
      );

      onProgress?.call('正在解压 aria2…', 0.9);
      final extractedBytes = await _extractBinary(tempArchive, tempBinary);
      if (!Platform.isWindows) {
        await _makeExecutable(tempBinary);
      }

      onProgress?.call('正在校验 aria2…', 0.95);
      final probe = await probeAria2(tempBinary.path);
      if (!probe.ok) {
        throw Aria2InstallException(
          '下载的 aria2c 无法运行，可能不是当前系统的可执行文件。\n${probe.detail}',
        );
      }

      await targetDir.create(recursive: true);
      if (await target.exists()) {
        await target.delete();
      }
      await tempBinary.rename(target.path);
      if (!Platform.isWindows) {
        await _makeExecutable(target);
      }

      final installedProbe = await probeAria2(target.path);
      if (!installedProbe.ok) {
        throw Aria2InstallException(
          'aria2c 安装后无法运行：${target.path}\n${installedProbe.detail}',
        );
      }
      await _writeManifest(targetDir, extractedBytes: extractedBytes);

      onProgress?.call('aria2 ${asset.version} 已就绪', 1);
      return Aria2Location(
        path: target.path,
        source: Aria2Source.cache,
        version: installedProbe.version ?? probe.version,
      );
    } on Aria2InstallException {
      rethrow;
    } on Object catch (error) {
      throw Aria2InstallException(
        '安装 aria2 失败（下载源：${asset.url}）。请检查网络连接后重试。',
        cause: error,
      );
    } finally {
      await _deleteQuietly(tempArchive);
      await _deleteQuietly(tempBinary);
      _downloadClient.close();
    }
  }

  Future<int> _extractBinary(File archive, File target) async {
    final bytes = await archive.readAsBytes();
    Archive? decoded;
    try {
      decoded = ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw Aria2InstallException('无法解析 aria2 压缩包。', cause: error);
    }

    ArchiveFile? match;
    for (final file in decoded.files) {
      if (!file.isFile) {
        continue;
      }
      final name = p.basename(file.name).toLowerCase();
      if (name == asset.binaryName.toLowerCase()) {
        match = file;
        if (file.name == asset.binaryName) {
          break;
        }
      }
    }
    if (match == null) {
      throw Aria2InstallException('压缩包中未找到 ${asset.binaryName}。');
    }

    final data = match.readBytes();
    if (data == null || data.isEmpty) {
      throw Aria2InstallException('压缩包中的 ${asset.binaryName} 是空的。');
    }
    await target.parent.create(recursive: true);
    await target.writeAsBytes(data, flush: true);
    return data.length;
  }

  Future<void> _makeExecutable(File file) async {
    try {
      await Process.run('chmod', <String>['755', file.path]);
    } on Object catch (error) {
      throw Aria2InstallException('无法为 aria2c 添加可执行权限。', cause: error);
    }
    final stat = await file.stat();
    if (stat.mode & 0x49 == 0) {
      throw Aria2InstallException('无法为 aria2c 添加可执行权限。');
    }
  }

  Future<void> _writeManifest(
    Directory targetDir, {
    required int extractedBytes,
  }) async {
    final manifest = File(p.join(targetDir.path, 'install.json'));
    final content = <String, Object?>{
      'version': asset.version,
      'source': asset.url,
      'archive': asset.archiveFileName,
      'binary': asset.binaryName,
      'bytes': extractedBytes,
      'installedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert(content),
    );
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Ignore cleanup failures.
    }
  }

  String _mib(int bytes) {
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MiB';
  }
}
