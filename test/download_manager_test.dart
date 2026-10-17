import 'package:faria2/core/download_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds bt-tracker options only when trackers exist', () {
    expect(DownloadManager.btTrackerOptions(const <String>[]), isEmpty);
    expect(
      DownloadManager.btTrackerOptions(<String>[
        'udp://a.example:1/announce',
        'http://b.example:2/announce',
      ]),
      <String, String>{
        'bt-tracker': 'udp://a.example:1/announce,http://b.example:2/announce',
      },
    );
  });
}
