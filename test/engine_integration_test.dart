@Tags(<String>['integration'])
library;

import 'dart:io';
import 'dart:math';

import 'package:faria2/core/aria2_asset.dart';
import 'package:faria2/core/aria2_installer.dart';
import 'package:faria2/core/aria2_process.dart';
import 'package:faria2/core/aria2_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// End-to-end test: install the managed engine, start aria2c, download a file
/// from a local HTTP server and shut it down again.
///
/// Enable with: FARIA2_INTEGRATION=1 flutter test test/engine_integration_test.dart
void main() {
  final enabled = Platform.environment['FARIA2_INTEGRATION'] == '1';

  test('installs, starts, downloads and stops aria2c', () async {
    if (!enabled) {
      markTestSkipped('set FARIA2_INTEGRATION=1 to run');
      return;
    }

    final cache = await Directory.systemTemp.createTemp('faria2_integration');
    HttpServer? server;
    Aria2Process? process;
    Aria2Rpc? rpc;
    try {
      final asset = Aria2Assets.resolveHost();
      final installer = Aria2Installer(
        cacheDir: cache,
        asset: asset,
        onProgress: (stage, progress) {},
      );
      final location = await installer.install();
      expect(File(location.path).existsSync(), isTrue);
      expect(location.source.name, 'cache');

      final payload = List<int>.generate(256 * 1024, (index) => index & 0xff);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });

      final downloadDir = Directory(p.join(cache.path, 'downloads'));
      await downloadDir.create(recursive: true);
      final port = 16800 + Random().nextInt(1000);
      process = Aria2Process(
        executable: location.path,
        port: port,
        secret: 'integration-secret',
        downloadDir: downloadDir.path,
        sessionFile: File(p.join(cache.path, 'aria2.session')),
        logFile: File(p.join(cache.path, 'aria2.log')),
        maxConcurrentDownloads: 2,
        maxConnectionPerServer: 2,
        split: 2,
      );
      await process.start();
      rpc = Aria2Rpc(port: port, secret: 'integration-secret');

      var ready = false;
      final readyDeadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(readyDeadline)) {
        if (await rpc.ping()) {
          ready = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(
        ready,
        isTrue,
        reason:
            'aria2 RPC did not become ready:\n${await process.readLogTail()}',
      );

      final gid = await rpc.addUri(
        <String>['http://127.0.0.1:${server.port}/file.bin'],
        dir: downloadDir.path,
        out: 'file.bin',
      );
      var status = await rpc.tellStatus(gid);
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (status['status'] != 'complete' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        status = await rpc.tellStatus(gid);
      }
      expect(status['status'], 'complete', reason: 'status: $status');
      expect(
        File(p.join(downloadDir.path, 'file.bin')).lengthSync(),
        payload.length,
      );
    } finally {
      try {
        await rpc?.shutdown().timeout(const Duration(seconds: 3));
      } on Object {
        // Ignore.
      }
      rpc?.close();
      if (process != null) {
        await process.stop().timeout(
          const Duration(seconds: 10),
          onTimeout: () => -1,
        );
      }
      await server?.close(force: true);
      await cache.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
