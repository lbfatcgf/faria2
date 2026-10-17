import 'package:faria2/core/app_settings.dart';
import 'package:faria2/core/tracker_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses lists and removes invalid/duplicate trackers', () {
    final parsed = TrackerService.parseTrackerList(
      'udp://a.example:1/announce\n'
      '# comment\n'
      'http://b.example:2/announce\n'
      'not a tracker\n'
      'udp://a.example:1/announce\n',
    );
    expect(parsed, <String>[
      'udp://a.example:1/announce',
      'http://b.example:2/announce',
    ]);
    expect(
      TrackerService.dedupe(<String>[
        'udp://a.example:1/announce',
        'udp://a.example:1/announce',
        'http://b.example:2/announce',
        'invalid',
      ]),
      <String>['udp://a.example:1/announce', 'http://b.example:2/announce'],
    );
  });

  test('merges URL sources with manual trackers and de-duplicates', () async {
    final settings = AppSettings(
      downloadDir: '/downloads',
      trackerUrls: const <String>['https://extra.example/list.txt'],
      manualTrackers: const <String>[
        'udp://manual.example:1/announce',
        'udp://b.example:2/announce',
      ],
    );
    final service = TrackerService(
      settings: settings,
      clientFactory: () => MockClient((request) async {
        final url = request.url.toString();
        if (url.endsWith('trackers_best.txt')) {
          return http.Response(
            'udp://a.example:1/announce\nudp://b.example:2/announce\n',
            200,
          );
        }
        if (url.endsWith('trackers_all.txt')) {
          return http.Response(
            'udp://b.example:2/announce\nudp://c.example:3/announce\n',
            200,
          );
        }
        return http.Response('udp://d.example:4/announce\n', 200);
      }),
    );
    addTearDown(service.dispose);

    await service.refresh();

    expect(service.trackers, <String>[
      'udp://a.example:1/announce',
      'udp://b.example:2/announce',
      'udp://c.example:3/announce',
      'udp://d.example:4/announce',
      'udp://manual.example:1/announce',
    ]);
    expect(service.urlTrackerCount, 4);
    expect(service.manualTrackerCount, 2);
    expect(service.lastError, isNull);
    expect(service.lastUpdated, isNotNull);
  });

  test('manual trackers never remove or replace fetched trackers', () async {
    final settings = AppSettings(
      downloadDir: '/downloads',
      manualTrackers: const <String>['udp://manual.example:1/announce'],
    );
    final service = TrackerService(
      settings: settings,
      clientFactory: () => MockClient((request) async {
        return http.Response('udp://a.example:1/announce\n', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.refresh();

    service.updateSettings(
      settings.copyWith(
        manualTrackers: const <String>[
          'udp://manual2.example:2/announce',
          'udp://a.example:1/announce',
        ],
      ),
    );

    expect(service.trackers, <String>[
      'udp://a.example:1/announce',
      'udp://manual2.example:2/announce',
    ]);
  });

  test('keeps previous trackers when all sources fail', () async {
    var offline = false;
    final service = TrackerService(
      settings: const AppSettings(downloadDir: '/downloads'),
      clientFactory: () => MockClient((request) async {
        if (offline) {
          throw Exception('offline');
        }
        return http.Response('udp://a.example:1/announce\n', 200);
      }),
    );
    addTearDown(service.dispose);

    await service.refresh();
    expect(service.trackers, <String>['udp://a.example:1/announce']);

    offline = true;
    await service.refresh();
    expect(service.trackers, <String>['udp://a.example:1/announce']);
    expect(service.lastError, isNotNull);
  });
}
