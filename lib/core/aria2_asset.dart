import 'dart:ffi' show Abi;

/// Operating systems faria2 can provision aria2 for.
enum Aria2TargetOs { windows, linux }

/// CPU architectures covered by the bundled/prebuilt aria2 downloads.
enum Aria2TargetArch { x64, arm64, arm, ia32 }

/// Describes where to download aria2 for a given host.
class Aria2Asset {
  const Aria2Asset({
    required this.os,
    required this.arch,
    required this.version,
    required this.url,
    required this.binaryName,
  });

  final Aria2TargetOs os;
  final Aria2TargetArch arch;
  final String version;
  final String url;
  final String binaryName;

  /// File name of the archive, used for the temporary download file.
  String get archiveFileName => url.split('/').last;

  /// The folder (inside the cache) that holds this version.
  String get versionDirName => version;

  String get expectedPathFragment => binaryName;
}

/// Resolves the download location of the aria2 build for the current host.
///
/// Windows uses the official aria2 release archives, Linux uses the static
/// builds published by abcfy2/aria2-static-build (works on musl and glibc
/// distributions alike because the binary is statically linked).
class Aria2Assets {
  Aria2Assets._();

  /// aria2 release used for the managed/installed engine.
  static const String defaultVersion = '1.37.0';

  static const String _windowsBaseUrl =
      'https://github.com/aria2/aria2/releases/download/release-';
  static const String _linuxBaseUrl =
      'https://github.com/abcfy2/aria2-static-build/releases/download/';

  static Aria2Asset? assetFor({
    required Aria2TargetOs os,
    required Aria2TargetArch arch,
    String version = defaultVersion,
  }) {
    switch (os) {
      case Aria2TargetOs.windows:
        final suffix = switch (arch) {
          Aria2TargetArch.x64 => 'win-64bit-build1',
          Aria2TargetArch.ia32 => 'win-32bit-build1',
          _ => null,
        };
        if (suffix == null) {
          return null;
        }
        return Aria2Asset(
          os: os,
          arch: arch,
          version: version,
          url: '$_windowsBaseUrl$version/aria2-$version-$suffix.zip',
          binaryName: 'aria2c.exe',
        );
      case Aria2TargetOs.linux:
        final assetName = switch (arch) {
          Aria2TargetArch.x64 => 'aria2-x86_64-linux-musl_static.zip',
          Aria2TargetArch.arm64 => 'aria2-aarch64-linux-musl_static.zip',
          Aria2TargetArch.arm => 'aria2-armv7-linux-musleabihf_static.zip',
          Aria2TargetArch.ia32 => 'aria2-i686-linux-musl_static.zip',
        };
        return Aria2Asset(
          os: os,
          arch: arch,
          version: version,
          url: '$_linuxBaseUrl$version/$assetName',
          binaryName: 'aria2c',
        );
    }
  }

  /// Maps the host ABI reported by dart:ffi to a supported target.
  static ({Aria2TargetOs os, Aria2TargetArch arch})? targetForAbi(Abi abi) {
    if (abi == Abi.windowsX64) {
      return (os: Aria2TargetOs.windows, arch: Aria2TargetArch.x64);
    }
    if (abi == Abi.windowsIA32) {
      return (os: Aria2TargetOs.windows, arch: Aria2TargetArch.ia32);
    }
    if (abi == Abi.linuxX64) {
      return (os: Aria2TargetOs.linux, arch: Aria2TargetArch.x64);
    }
    if (abi == Abi.linuxArm64) {
      return (os: Aria2TargetOs.linux, arch: Aria2TargetArch.arm64);
    }
    if (abi == Abi.linuxArm) {
      return (os: Aria2TargetOs.linux, arch: Aria2TargetArch.arm);
    }
    if (abi == Abi.linuxIA32) {
      return (os: Aria2TargetOs.linux, arch: Aria2TargetArch.ia32);
    }
    return null;
  }

  /// Returns the asset for the host, throws [UnsupportedError] when the host
  /// is not supported.
  static Aria2Asset resolveHost({String version = defaultVersion}) {
    final target = targetForAbi(Abi.current());
    if (target == null) {
      throw UnsupportedError(
        '当前系统/架构不在支持范围内（仅支持 Windows x64/x86 与 Linux x64/arm64/arm/x86）。',
      );
    }
    final asset = assetFor(os: target.os, arch: target.arch, version: version);
    if (asset == null) {
      throw UnsupportedError(
        '没有适用于 ${target.os.name}/${target.arch.name} 的 aria2 预编译包。',
      );
    }
    return asset;
  }
}
