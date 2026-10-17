import 'dart:io';

import 'package:faria2/core/aria2_process.dart';
import 'package:flutter_test/flutter_test.dart';

Aria2Process createProcess({
  String speedLimit = '',
  String secret = 'secret-token',
  String proxy = '',
}) {
  return Aria2Process(
    executable: '/usr/bin/aria2c',
    port: 6801,
    secret: secret,
    downloadDir: '/downloads',
    sessionFile: File('/data/aria2.session'),
    logFile: File('/data/aria2.log'),
    maxConcurrentDownloads: 4,
    maxConnectionPerServer: 6,
    split: 8,
    speedLimit: speedLimit,
    proxy: proxy,
  );
}

void main() {
  group('buildArguments', () {
    test('configures RPC, session and directories', () {
      final args = createProcess().buildArguments();
      expect(args, contains('--enable-rpc=true'));
      expect(args, contains('--rpc-listen-all=false'));
      expect(args, contains('--rpc-listen-port=6801'));
      expect(args, contains('--rpc-secret=secret-token'));
      expect(args, contains('--dir=/downloads'));
      expect(args, contains('--save-session=/data/aria2.session'));
      expect(args, contains('--console-log-level=warn'));
      expect(args, contains('--max-concurrent-downloads=4'));
      expect(args, contains('--max-connection-per-server=6'));
      expect(args, contains('--split=8'));
      expect(args, contains('--stop-with-process=$pid'));
      expect(args, contains('--file-allocation=none'));
      expect(args, contains('--no-conf=true'));
    });

    test('omits the RPC secret when authentication is disabled', () {
      final args = createProcess(secret: '').buildArguments();
      expect(args, contains('--enable-rpc=true'));
      expect(args.any((arg) => arg.startsWith('--rpc-secret')), isFalse);
    });

    test('adds the proxy only when configured', () {
      expect(
        createProcess(proxy: 'http://127.0.0.1:7890').buildArguments(),
        contains('--all-proxy=http://127.0.0.1:7890'),
      );
      expect(
        createProcess().buildArguments().any(
          (arg) => arg.startsWith('--all-proxy'),
        ),
        isFalse,
      );
    });

    test('adds a speed limit only when configured', () {
      expect(
        createProcess(speedLimit: '2M').buildArguments(),
        contains('--max-overall-download-limit=2M'),
      );
      expect(
        createProcess().buildArguments().any(
          (arg) => arg.startsWith('--max-overall-download-limit'),
        ),
        isFalse,
      );
    });
  });

  group('proxy environment handling', () {
    test('removes every proxy variable from the child environment', () {
      final environment = Aria2Process.withoutProxyEnvironment(<String, String>{
        'PATH': '/usr/bin',
        'http_proxy': 'http://127.0.0.1:7890',
        'all_proxy': 'socks5://127.0.0.1:7890',
        'HTTPS_PROXY': 'socks5h://127.0.0.1:7890',
      });
      expect(environment['PATH'], '/usr/bin');
      expect(
        environment.keys.any((key) => key.toLowerCase().contains('proxy')),
        isFalse,
      );
    });
  });
}
