import 'dart:io';

import 'package:faria2/core/app_settings.dart';
import 'package:faria2/core/network_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults generate a 32 character secret', () {
    final settings = AppSettings.defaults('/tmp/downloads');
    expect(settings.rpcSecret.length, 32);
    expect(settings.themeMode, AppThemeMode.system);
    expect(settings.downloadDir, '/tmp/downloads');
    expect(settings.minimizeToTray, isTrue);
    expect(settings.startMinimized, isTrue);
    expect(settings.useProxy, isFalse);
    expect(settings.proxyUrl, defaultProxyAddress);
    expect(settings.trackerUrls, isEmpty);
    expect(settings.manualTrackers, isEmpty);
  });

  test('json round trip keeps every field', () {
    const settings = AppSettings(
      downloadDir: '/data/downloads',
      rpcPort: 6800,
      maxConcurrentDownloads: 3,
      maxConnectionPerServer: 4,
      split: 6,
      speedLimit: '2M',
      aria2Path: '/usr/bin/aria2c',
      rpcSecret: 'secret',
      themeMode: AppThemeMode.dark,
      minimizeToTray: false,
      startMinimized: false,
      useProxy: true,
      proxyUrl: 'http://127.0.0.1:7891',
      trackerUrls: <String>['https://extra.example/list.txt'],
      manualTrackers: <String>['udp://manual.example:1/announce'],
    );
    final restored = AppSettings.fromJson(
      settings.toJson(),
      defaultDownloadDir: '/fallback',
    );
    expect(restored.downloadDir, settings.downloadDir);
    expect(restored.rpcPort, 6800);
    expect(restored.maxConcurrentDownloads, 3);
    expect(restored.maxConnectionPerServer, 4);
    expect(restored.split, 6);
    expect(restored.speedLimit, '2M');
    expect(restored.aria2Path, '/usr/bin/aria2c');
    expect(restored.rpcSecret, 'secret');
    expect(restored.themeMode, AppThemeMode.dark);
    expect(restored.minimizeToTray, isFalse);
    expect(restored.startMinimized, isFalse);
    expect(restored.useProxy, isTrue);
    expect(restored.proxyUrl, 'http://127.0.0.1:7891');
    expect(restored.trackerUrls, <String>['https://extra.example/list.txt']);
    expect(restored.manualTrackers, <String>[
      'udp://manual.example:1/announce',
    ]);
  });

  test('startMinimized defaults to true for existing settings', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'downloadDir': '/downloads',
    }, defaultDownloadDir: '/downloads');
    expect(settings.startMinimized, isTrue);
    expect(settings.copyWith(startMinimized: false).startMinimized, isFalse);
  });

  test('invalid values are clamped', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'rpcPort': 99999,
      'maxConcurrentDownloads': 0,
      'maxConnectionPerServer': 99,
      'split': -1,
    }, defaultDownloadDir: '/downloads');
    expect(settings.rpcPort, 65535);
    expect(settings.maxConcurrentDownloads, 1);
    expect(settings.maxConnectionPerServer, 16);
    expect(settings.split, 1);
  });

  test('engineEquals ignores the theme', () {
    const base = AppSettings(downloadDir: '/d', rpcSecret: 's');
    expect(
      base.engineEquals(base.copyWith(themeMode: AppThemeMode.dark)),
      isTrue,
    );
    expect(base.engineEquals(base.copyWith(split: 2)), isFalse);
    expect(base.engineEquals(base.copyWith(startMinimized: false)), isTrue);
    expect(base.engineEquals(base.copyWith(useProxy: true)), isFalse);
    expect(
      base.engineEquals(base.copyWith(proxyUrl: '127.0.0.1:7891')),
      isFalse,
    );
    expect(
      base.engineEquals(
        base.copyWith(manualTrackers: const <String>['udp://a:1']),
      ),
      isTrue,
    );
  });

  test('tracker lists are trimmed and de-duplicated', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'trackerUrls': <String>[
        'https://a.example/list',
        'https://a.example/list',
        '',
      ],
      'manualTrackers': <String>[' udp://m.example:1 ', 'udp://m.example:1'],
    }, defaultDownloadDir: '/downloads');
    expect(settings.trackerUrls, <String>['https://a.example/list']);
    expect(settings.manualTrackers, <String>['udp://m.example:1']);
  });

  test('load returns defaults for a missing file', () async {
    final dir = await Directory.systemTemp.createTemp('faria2_settings');
    addTearDown(() => dir.delete(recursive: true));
    final settings = await AppSettings.load(
      File('${dir.path}/settings.json'),
      defaultDownloadDir: dir.path,
    );
    expect(settings.downloadDir, dir.path);
    expect(settings.rpcSecret, isNotEmpty);
  });

  test('an empty rpcSecret is preserved on load', () async {
    final dir = await Directory.systemTemp.createTemp('faria2_settings');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/settings.json');
    const settings = AppSettings(downloadDir: '/data', rpcSecret: '');
    await settings.save(file);
    final restored = await AppSettings.load(
      file,
      defaultDownloadDir: '/fallback',
    );
    expect(restored.rpcSecret, isEmpty);
  });

  test('save and load round trip', () async {
    final dir = await Directory.systemTemp.createTemp('faria2_settings');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/settings.json');
    const settings = AppSettings(
      downloadDir: '/data',
      rpcPort: 6800,
      rpcSecret: 'abc',
      themeMode: AppThemeMode.light,
    );
    await settings.save(file);
    final restored = await AppSettings.load(
      file,
      defaultDownloadDir: '/fallback',
    );
    expect(restored.downloadDir, '/data');
    expect(restored.rpcPort, 6800);
    expect(restored.themeMode, AppThemeMode.light);
  });
}
