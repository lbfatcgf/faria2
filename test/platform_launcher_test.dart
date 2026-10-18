import 'package:faria2/core/platform_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows reveal uses cmd with explorer /select', () {
    expect(
      PlatformLauncher.windowsRevealArguments(r'C:\Downloads\a b.txt'),
      <String>['/c', 'explorer.exe', r'/select,C:\Downloads\a b.txt'],
    );
  });

  test('Windows open file uses cmd start with an empty title', () {
    expect(
      PlatformLauncher.windowsOpenFileArguments(r'C:\Downloads\a b.txt'),
      <String>['/c', 'start',r'C:\Downloads\a b.txt'],
    );
  });

  test('Windows open directory uses cmd with explorer', () {
    expect(
      PlatformLauncher.windowsOpenDirectoryArguments(r'C:\Downloads\a b'),
      <String>['/c', 'start', 'explorer.exe',r'C:\Downloads\a b'],
    );
  });
}
