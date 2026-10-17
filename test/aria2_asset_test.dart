import 'dart:ffi' show Abi;

import 'package:faria2/core/aria2_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Aria2Assets.assetFor', () {
    test('uses the official Windows build for x64', () {
      final asset = Aria2Assets.assetFor(
        os: Aria2TargetOs.windows,
        arch: Aria2TargetArch.x64,
      );
      expect(asset, isNotNull);
      expect(
        asset!.url,
        endsWith('/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip'),
      );
      expect(asset.binaryName, 'aria2c.exe');
      expect(asset.archiveFileName, 'aria2-1.37.0-win-64bit-build1.zip');
    });

    test('uses the 32-bit Windows build for ia32', () {
      final asset = Aria2Assets.assetFor(
        os: Aria2TargetOs.windows,
        arch: Aria2TargetArch.ia32,
      );
      expect(asset?.url, contains('win-32bit-build1.zip'));
    });

    test('rejects unsupported Windows architectures', () {
      expect(
        Aria2Assets.assetFor(
          os: Aria2TargetOs.windows,
          arch: Aria2TargetArch.arm64,
        ),
        isNull,
      );
    });

    test('maps Linux architectures to static builds', () {
      final x64 = Aria2Assets.assetFor(
        os: Aria2TargetOs.linux,
        arch: Aria2TargetArch.x64,
      )!;
      expect(x64.url, endsWith('/1.37.0/aria2-x86_64-linux-musl_static.zip'));
      expect(x64.binaryName, 'aria2c');

      final arm64 = Aria2Assets.assetFor(
        os: Aria2TargetOs.linux,
        arch: Aria2TargetArch.arm64,
      )!;
      expect(arm64.url, contains('aarch64-linux-musl_static.zip'));

      final arm = Aria2Assets.assetFor(
        os: Aria2TargetOs.linux,
        arch: Aria2TargetArch.arm,
      )!;
      expect(arm.url, contains('armv7-linux-musleabihf_static.zip'));

      final ia32 = Aria2Assets.assetFor(
        os: Aria2TargetOs.linux,
        arch: Aria2TargetArch.ia32,
      )!;
      expect(ia32.url, contains('i686-linux-musl_static.zip'));
    });

    test('honours a custom version', () {
      final asset = Aria2Assets.assetFor(
        os: Aria2TargetOs.linux,
        arch: Aria2TargetArch.x64,
        version: '9.9.9',
      )!;
      expect(asset.url, contains('/9.9.9/'));
    });
  });

  group('Aria2Assets.targetForAbi', () {
    test('maps desktop ABIs', () {
      expect(Aria2Assets.targetForAbi(Abi.windowsX64), (
        os: Aria2TargetOs.windows,
        arch: Aria2TargetArch.x64,
      ));
      expect(Aria2Assets.targetForAbi(Abi.linuxX64), (
        os: Aria2TargetOs.linux,
        arch: Aria2TargetArch.x64,
      ));
      expect(Aria2Assets.targetForAbi(Abi.linuxArm64), (
        os: Aria2TargetOs.linux,
        arch: Aria2TargetArch.arm64,
      ));
    });

    test('returns null for unsupported ABIs', () {
      expect(Aria2Assets.targetForAbi(Abi.androidArm64), isNull);
    });
  });
}
