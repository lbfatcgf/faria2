import 'dart:io';

/// Forces aria2's messages into the C locale so `--version` can be parsed
/// regardless of the user's language. Debian/Ubuntu packages for example
/// print `aria2 版本 1.37.0` under a Chinese locale.
const Map<String, String> aria2ProbeEnvironment = <String, String>{
  'LC_ALL': 'C',
  'LC_MESSAGES': 'C',
  'LANG': 'C',
  'LANGUAGE': 'C',
};

final RegExp _versionToken = RegExp(r'([0-9]+\.[0-9]+(?:\.[0-9]+)*)');

/// Extracts the version from `aria2c --version` output. The first line that
/// contains "aria2" is inspected, which works for localized output because the
/// program name itself is not translated.
String? parseAria2Version(String output) {
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.toLowerCase().contains('aria2')) {
      continue;
    }
    final match = _versionToken.firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

/// Result of running `aria2c --version`.
class Aria2ProbeResult {
  const Aria2ProbeResult({required this.ok, this.version, this.detail = ''});

  final bool ok;
  final String? version;

  /// Combined stdout/stderr, used for diagnostics when [ok] is false.
  final String detail;
}

/// Runs `aria2c --version` and reports whether the binary is usable.
Future<Aria2ProbeResult> probeAria2(
  String executable, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    final result = await Process.run(
      executable,
      const <String>['--version'],
      environment: aria2ProbeEnvironment,
      runInShell: false,
    ).timeout(timeout);
    final output = '${result.stdout}\n${result.stderr}'.trim();
    if (result.exitCode != 0) {
      return Aria2ProbeResult(
        ok: false,
        detail: output.isEmpty ? '退出码 ${result.exitCode}' : output,
      );
    }
    return Aria2ProbeResult(
      ok: true,
      version: parseAria2Version(output),
      detail: output,
    );
  } on Object catch (error) {
    return Aria2ProbeResult(ok: false, detail: '$error');
  }
}
