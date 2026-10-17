import 'dart:io';

import 'package:faria2/core/aria2_locator.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _makeExecutable(File file) async {
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['755', file.path]);
  }
}

void main() {
  late Directory temp;
  late Directory engineRoot;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('faria2_locator');
    engineRoot = Directory('${temp.path}/engine/aria2');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('returns null when nothing is available', () async {
    final locator = Aria2Locator(
      engineRoot: engineRoot,
      environment: const <String, String>{'PATH': '/nonexistent'},
      isWindows: Platform.isWindows,
    );
    expect(await locator.locate(), isNull);
  });

  test('finds the managed binary inside the cache', () async {
    final binary = File(
      '${engineRoot.path}/1.37.0/${Platform.isWindows ? 'aria2c.exe' : 'aria2c'}',
    );
    await binary.parent.create(recursive: true);
    await binary.writeAsString('#!/bin/sh\n');
    await _makeExecutable(binary);

    final locator = Aria2Locator(
      engineRoot: engineRoot,
      environment: const <String, String>{'PATH': '/nonexistent'},
      isWindows: Platform.isWindows,
    );
    final result = await locator.locate();
    expect(result, isNotNull);
    expect(result!.source, Aria2Source.cache);
    expect(result.version, '1.37.0');
    expect(result.path, binary.path);
  });

  test('prefers a custom path over the cache', () async {
    final cached = File(
      '${engineRoot.path}/1.37.0/${Platform.isWindows ? 'aria2c.exe' : 'aria2c'}',
    );
    await cached.parent.create(recursive: true);
    await cached.writeAsString('cached');
    await _makeExecutable(cached);

    final custom = File('${temp.path}/custom-aria2c');
    await custom.writeAsString('custom');
    await _makeExecutable(custom);

    final locator = Aria2Locator(
      engineRoot: engineRoot,
      customPath: custom.path,
      environment: const <String, String>{'PATH': '/nonexistent'},
      isWindows: Platform.isWindows,
    );
    final result = await locator.locate();
    expect(result!.source, Aria2Source.custom);
    expect(result.path, custom.path);
  });

  test('lists candidates in priority order', () async {
    final custom = File('${temp.path}/custom-aria2c');
    await custom.writeAsString('custom');
    await _makeExecutable(custom);

    for (final version in <String>['1.36.0', '1.37.0']) {
      final binary = File(
        '${engineRoot.path}/$version/${Platform.isWindows ? 'aria2c.exe' : 'aria2c'}',
      );
      await binary.parent.create(recursive: true);
      await binary.writeAsString(version);
      await _makeExecutable(binary);
    }

    final systemDir = Directory('${temp.path}/system-bin');
    final systemBinary = File(
      '${systemDir.path}/${Platform.isWindows ? 'aria2c.exe' : 'aria2c'}',
    );
    await systemDir.create(recursive: true);
    await systemBinary.writeAsString('system');
    await _makeExecutable(systemBinary);

    final locator = Aria2Locator(
      engineRoot: engineRoot,
      customPath: custom.path,
      environment: <String, String>{'PATH': systemDir.path},
      isWindows: Platform.isWindows,
    );
    final candidates = await locator.candidates();
    expect(candidates.map((candidate) => candidate.source), <Aria2Source>[
      Aria2Source.custom,
      Aria2Source.system,
      Aria2Source.cache,
      Aria2Source.cache,
    ]);
    expect(candidates[2].version, '1.37.0');
    expect(candidates[3].version, '1.36.0');
  });

  test('falls back to the system PATH', () async {
    final systemDir = Directory('${temp.path}/system-bin');
    final binary = File(
      '${systemDir.path}/${Platform.isWindows ? 'aria2c.exe' : 'aria2c'}',
    );
    await systemDir.create(recursive: true);
    await binary.writeAsString('system');
    await _makeExecutable(binary);

    final locator = Aria2Locator(
      engineRoot: engineRoot,
      environment: <String, String>{'PATH': systemDir.path},
      isWindows: Platform.isWindows,
    );
    final result = await locator.locate();
    expect(result!.source, Aria2Source.system);
    expect(result.path, binary.path);
  });
}
