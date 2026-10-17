import 'dart:io';

import 'package:faria2/core/aria2_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAria2Version', () {
    test('reads English output', () {
      expect(
        parseAria2Version(
          'aria2 version 1.37.0\n'
          'Copyright (C) 2006, 2019 Tatsuhiro Tsujikawa\n',
        ),
        '1.37.0',
      );
    });

    test('reads localized output (Debian zh_CN)', () {
      expect(
        parseAria2Version(
          'aria2 版本 1.37.0\n'
          'Copyright (C) 2006, 2019 Tatsuhiro Tsujikawa\n',
        ),
        '1.37.0',
      );
    });

    test('reads two component versions', () {
      expect(parseAria2Version('aria2 version 1.36'), '1.36');
    });

    test('ignores output without an aria2 line', () {
      expect(parseAria2Version('hello 1.2.3'), isNull);
      expect(parseAria2Version(''), isNull);
    });
  });

  group('probeAria2', () {
    test('forces the C locale so the version can be parsed', () async {
      final dir = await Directory.systemTemp.createTemp('faria2_probe');
      addTearDown(() => dir.delete(recursive: true));
      final script = File('${dir.path}/aria2c');
      await script.writeAsString(
        '#!/bin/sh\n'
        'echo "aria2 version 9.9.9"\n'
        'echo "LC_ALL=\$LC_ALL"\n',
      );
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['755', script.path]);
      }

      final result = await probeAria2(script.path);
      expect(result.ok, isTrue);
      expect(result.version, '9.9.9');
      expect(result.detail, contains('LC_ALL=C'));
    }, skip: Platform.isWindows);

    test('parses localized output even without the C locale', () async {
      final dir = await Directory.systemTemp.createTemp('faria2_probe');
      addTearDown(() => dir.delete(recursive: true));
      final script = File('${dir.path}/aria2c');
      await script.writeAsString('#!/bin/sh\necho "aria2 版本 9.9.9"\n');
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['755', script.path]);
      }

      final result = await probeAria2(script.path);
      expect(result.ok, isTrue);
      expect(result.version, '9.9.9');
    }, skip: Platform.isWindows);

    test('reports a missing executable', () async {
      final result = await probeAria2('/definitely/missing/aria2c');
      expect(result.ok, isFalse);
      expect(result.detail, isNotEmpty);
    });
  });
}
